"""Source-aware privacy/IPC checks; Nix also runs niri's real KDL validator.

This deliberately checks the repository's top-level block layout, not arbitrary
KDL. A source/layout change fails closed instead of silently skipping a check.
No compositor, shell service or screencast is started.
"""

import argparse
import re
from pathlib import Path


PANEL_NAMESPACES = {"noctalia-panel", "noctalia-attached-panel"}
SHELL_BINDINGS = {
    "Mod+Shift+P": ("panel-toggle", "control-center"),
    "Mod+L": ("session", "lock"),
    "Mod+Backspace": ("panel-toggle", "session"),
    "Ctrl+Alt+W": ("bar-toggle",),
    "Mod+Space": ("panel-toggle", "launcher"),
    "Mod+A": ("panel-toggle", "launcher"),
    "Mod+Tab": ("panel-toggle", "launcher"),
    "Mod+Shift+A": ("panel-toggle", "launcher"),
    "Mod+N": ("panel-toggle", "control-center", "notifications"),
    "Mod+Shift+N": ("notification-clear-active",),
    "Mod+Ctrl+N": ("notification-dnd-toggle",),
    "Alt+F10": ("volume-mute",),
    "F11": ("volume-down", "5"),
    "F12": ("volume-up", "5"),
    "XF86AudioMute": ("volume-mute",),
    "XF86AudioLowerVolume": ("volume-down", "5"),
    "XF86AudioRaiseVolume": ("volume-up", "5"),
    "XF86AudioPlay": ("media", "toggle"),
    "XF86AudioPause": ("media", "toggle"),
    "XF86AudioNext": ("media", "next"),
    "XF86AudioPrev": ("media", "previous"),
    "XF86MonBrightnessUp": ("brightness-up", "current", "5%"),
    "XF86MonBrightnessDown": ("brightness-down", "current", "5%"),
    "Alt+F8": ("nightlight-force-on",),
    "Alt+F9": ("nightlight-force-off",),
    "Mod+Alt+Right": ("wallpaper-next",),
    "Mod+Alt+Left": ("wallpaper-previous",),
    "Mod+Shift+W": ("panel-toggle", "wallpaper"),
    "Mod+Shift+T": ("theme-mode-toggle",),
    "Mod+Shift+R": ("settings-toggle",),
    "Mod+V": ("panel-toggle", "clipboard"),
    "Mod+Shift+V": ("panel-toggle", "clipboard"),
}


def check_source(root: Path) -> None:
    def read(relative: str) -> str:
        return (root / "src" / relative).read_text()

    manager = read("shell/panel/panel_manager.cpp")
    namespaces = set(re.findall(r'\.nameSpace\s*=\s*"([^"]+)"', manager))
    assert namespaces == PANEL_NAMESPACES, (
        "Noctalia panel namespaces changed; review screencast privacy rules"
    )
    persistent = read("shell/panel/persistent_panel_host.cpp")
    assert set(re.findall(r'\.nameSpace\s*=\s*"([^"]+)"', persistent)) == {"noctalia-panel"}

    # These are panels, not toplevel windows with translated titles as in DMS.
    # Check the class and registration route, not only unused string literals.
    registrations = read("app/application_ui.cpp")
    for directory, name, panel_id in (
        ("clipboard", "ClipboardPanel", "clipboard"),
        ("polkit", "PolkitPanel", "polkit"),
        ("control_center", "ControlCenterPanel", "control-center"),
    ):
        header = read(f"shell/{directory}/{directory}_panel.h")
        assert re.search(rf"class {name}\s*:\s*public Panel\b", header)
        assert re.search(rf'm_panelManager\.registerPanel\("{panel_id}"', registrations)
        assert f"std::make_unique<{name}>" in registrations

    center = read("shell/control_center/control_center_panel.cpp")
    assert "std::make_unique<NetworkTab>" in center
    assert "std::make_unique<BluetoothTab>" in center

    schema = read("cli/schema_msg.h")
    known_commands = set(re.findall(r'inline constexpr Command \w+\s*\{\s*"([^"]+)"', schema))
    for command, *_ in SHELL_BINDINGS.values():
        assert command in known_commands, f"Noctalia IPC command disappeared: {command}"

    # Panel IDs and the selected control-center tab are separate from CLI verbs.
    for args in SHELL_BINDINGS.values():
        if args[0] == "panel-toggle":
            assert re.search(rf'm_panelManager\.registerPanel\(\s*"{args[1]}"', registrations)
    assert 'TabId::Notifications, "notifications"' in read("shell/control_center/control_center_panel.h")
    assert '"current"' in read("system/brightness_service.cpp")


def check(path: Path) -> None:
    text = re.sub(r"(?m)^\s*//[^\n]*", "", path.read_text())
    assert not re.search(r'\b(?:dms|quickshell)\b', text), f"{path}: stale shell reference"
    rules = re.findall(r"(?ms)^layer-rule\s*\{\n(.*?)^\}", text)
    privacy_patterns = [
        re.compile(pattern)
        for rule in rules
        if re.search(r'^\s*block-out-from "screencast"\s*$', rule, re.M)
        for pattern in re.findall(r'^\s*match namespace="([^"]+)"\s*$', rule, re.M)
    ]
    assert privacy_patterns, f"{path}: no screencast privacy rules found"
    for namespace in PANEL_NAMESPACES:
        assert any(p.search(namespace) for p in privacy_patterns), (
            f"{path}: sensitive layer {namespace} is not protected"
        )
    for namespace in (
        "noctalia-bar-main", "noctalia-dock", "noctalia-wallpaper", "noctalia-backdrop",
        "noctalia-notification", "noctalia-panel-click-shield", "noctalia-panels", "other-panel",
    ):
        assert not any(p.search(namespace) for p in privacy_patterns), (
            f"{path}: unrelated layer {namespace} is unexpectedly hidden"
        )

    # Polkit is a panel. Only the explicit external Wi-Fi QR helper needs a
    # toplevel rule; Settings and ordinary Kitty windows must remain visible.
    window_patterns = []
    for rule in re.findall(r"(?ms)^window-rule\s*\{\n(.*?)^\}", text):
        if 'block-out-from "screencast"' not in rule:
            continue
        matches = re.findall(
            r'^\s*match app-id=r#"([^"]+)"# title=r#"([^"]+)"#\s*$', rule, re.M
        )
        assert matches, f"{path}: privacy window rule must constrain app-id AND title"
        assert len(matches) == len(re.findall(r"^\s*match\b", rule, re.M))
        window_patterns.extend((re.compile(app), re.compile(title)) for app, title in matches)

    def protected(app: str, title: str) -> bool:
        return any(a.search(app) and t.search(title) for a, t in window_patterns)

    assert protected("noctalia-wifi-qr", "Wi-Fi QR"), f"{path}: Wi-Fi QR helper is exposed"
    for app in ("kitty", "dev.noctalia.Noctalia", "firefox", "noctalia-wifi-qr.extra", "other-noctalia-wifi-qr"):
        assert not protected(app, "Wi-Fi QR"), f"{path}: QR privacy app-id is too broad"
    for title in ("Settings", "Wi-Fi QR extra", "Other Wi-Fi QR", ""):
        assert not protected("noctalia-wifi-qr", title), f"{path}: QR privacy title is too broad"
    assert not protected("dev.noctalia.Noctalia", "Settings")

    binds_text = text.split("binds {", 1)[1].split("\n}", 1)[0]
    matches = re.findall(r'(?ms)^    ([A-Za-z0-9][^\s{]*)\s*([^\n{]*)\{([^}]+)\}', binds_text)
    bindings = {key: body for key, _, body in matches}
    assert len(bindings) == len(matches), f"{path}: duplicate binding"
    headers = {key: header for key, header, _ in matches}
    for key, args in SHELL_BINDINGS.items():
        expected = "spawn " + " ".join(f'"{arg}"' for arg in ("noctalia", "msg", *args))
        assert bindings.get(key, "").strip().rstrip(";") == expected, (
            f"{path}: {key} no longer calls {expected}"
        )
    for key in ("Alt+F10", "F11", "F12", "XF86AudioMicMute"):
        assert "allow-when-locked=true" in headers[key]
    for key in bindings:
        if key.startswith("XF86"):
            assert "allow-when-locked=true" in headers[key]
    assert "filesearch.sh" in bindings["Mod+Shift+E"]
    assert 'spawn "kitty" "-e" "htop"' in bindings["Mod+Shift+Escape"]
    assert 'spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle"' in bindings["XF86AudioMicMute"]
    assert len(re.findall(r'^workspace "scratch"\s*$', text, re.M)) == 1
    assert 'move-column-to-workspace "scratch" focus=false' in bindings["Mod+Alt+S"]
    assert 'focus-workspace "scratch"' in bindings["Mod+Ctrl+S"]
    assert "toggle-overview" in bindings["Mod+S"]
    assert not re.search(r"move-column-to-workspace\s+99\b", text)
    print(f"{path}: Noctalia privacy, IPC bindings and scratch checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--noctalia-root", type=Path)
    parser.add_argument("configs", type=Path, nargs="+")
    args = parser.parse_args()
    if args.noctalia_root is not None:
        check_source(args.noctalia_root)
    for path in args.configs:
        check(path)

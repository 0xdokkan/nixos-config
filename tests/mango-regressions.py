"""Regressions for the mango config, on the directories home-manager links.

`mango -p` (home/mango-configs.nix) already rejects unknown options, keys
and dispatchers. This checks what it cannot see: the binds kept from niri,
commands that mango would split on commas, the screencast privacy rule,
the per-host layout and the game-mode overrides.
"""

import argparse
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--laptop", type=Path, required=True)
parser.add_argument("--desktop", type=Path, required=True)
args = parser.parse_args()

BIND = re.compile(r"^(bind|mousebind|axisbind|gesturebind)([a-z]*)=(.*)$")


def lines(path):
    return path.read_text().splitlines()


def settings(path):
    """key=value lines, without binds, rules and comments."""
    out = {}
    for line in lines(path):
        if line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        out.setdefault(key, []).append(value)
    return out


def binds(path):
    """{(kind, MODS, key): (flags, action)} for every bind line."""
    table = {}
    for number, line in enumerate(lines(path), 1):
        match = BIND.match(line)
        if not match:
            continue
        kind, flags, body = match.groups()
        fields = body.split(",")
        if kind == "gesturebind":
            mods, key, action = fields[0], ",".join(fields[1:3]), fields[3:]
        else:
            mods, key, action = fields[0], fields[1], fields[2:]
        mods = "+".join(sorted(m.upper() for m in mods.split("+") if m.upper() != "NONE"))
        entry = (kind, mods, key.lower())
        assert entry not in table, f"{path}:{number}: duplicate {entry}"
        table[entry] = (flags, ",".join(action))
    return table


def check_binds(path):
    table = binds(path)

    def action(mods, key, kind="bind"):
        return table.get((kind, mods, key.lower()), ("", None))[1]

    # The binds the user asked to keep from niri.
    expected = {
        ("SUPER", "q"): "spawn,dontkillsteam.sh",
        ("ALT", "F4"): "spawn,dontkillsteam.sh",
        ("SUPER", "Delete"): "quit",
        ("SUPER", "l"): "spawn,loginctl lock-session",
        ("SUPER", "BackSpace"): "spawn,powermenu.sh",
        ("SUPER", "t"): "spawn,kitty",
        ("SUPER", "e"): "spawn,nautilus --new-window",
        ("SHIFT+SUPER", "e"): "spawn,filesearch.sh",
        ("SUPER", "c"): "spawn,kitty nvim",
        ("SUPER", "f"): "spawn,firefox",
        ("CTRL+SHIFT", "Escape"): "spawn,kitty -e htop",
        ("SHIFT+SUPER", "Escape"): "spawn,kitty -e htop",
        ("SUPER", "space"): "spawn,rofi -show drun",
        ("SUPER", "a"): "spawn,rofi -show drun",
        ("SUPER", "Tab"): "spawn,rofi -show drun",
        ("SHIFT+SUPER", "a"): "spawn,rofi -show drun",
        ("SUPER", "v"): "spawn,clipboard.sh",
        ("SHIFT+SUPER", "code:61"): "spawn,cheatsheet.sh",
        ("SHIFT+SUPER", "p"): "spawn,swaync-client -t -sw",
        ("SUPER", "n"): "spawn,swaync-client -t -sw",
        ("SUPER", "w"): "togglefloating",
        ("SUPER", "z"): "togglefloating",
        ("SHIFT+SUPER", "f"): "spawn,windowpin.sh",
        ("SUPER", "m"): "togglemaximizescreen",
        ("SHIFT+SUPER", "m"): "togglefullscreen",
        ("ALT", "Return"): "togglefullscreen",
        ("SUPER", "r"): "switch_proportion_preset",
        ("SUPER", "period"): "scroller_stack,right",
        ("SUPER", "comma"): "scroller_stack,left",
        ("SUPER", "s"): "toggleoverview",
        ("ALT+SUPER", "s"): "minimized",
        ("CTRL+SUPER", "s"): "toggle_scratchpad",
        ("ALT", "Tab"): "focus_window_or_workspace,right",
        ("SUPER", "k"): "spawn,keyboardswitch.sh",
        ("ALT+SUPER", "g"): "spawn,gamemode.sh",
        ("SUPER", "p"): "spawn,screenshot.sh region",
        ("NONE", "Print"): "spawn,screenshot.sh screen",
        ("ALT+SUPER", "Right"): "spawn,wallpaper.sh next",
        ("ALT+SUPER", "Left"): "spawn,wallpaper.sh prev",
        ("SHIFT+SUPER", "w"): "spawn,wallpaper.sh pick",
    }
    for (mods, key), want in expected.items():
        mods = "" if mods == "NONE" else mods
        got = action(mods, key)
        assert got == want, f"{path}: {mods}+{key} is {got!r}, expected {want!r}"

    for n in range(1, 11):
        key = str(n % 10)
        assert action("SUPER", key) == f"view,{n}"
        assert action("SHIFT+SUPER", key) == f"tag,{n}"
        assert action("ALT+SUPER", key) == f"tagsilent,{n}"
    for arrow in ("left", "right", "up", "down"):
        assert action("SUPER", arrow) == f"focusdir,{arrow}"
        assert action("CTRL+SHIFT+SUPER", arrow) == f"exchange_client,{arrow}"

    # Left free on purpose (were Noctalia's theme and settings).
    for key in ("t", "r"):
        assert ("bind", "SHIFT+SUPER", key) not in table, f"Mod+Shift+{key} must stay free"
    # F11/F12 alone belong to the apps (fullscreen, devtools).
    assert not any(key in ("f11", "f12") and mods == "" for _, mods, key in table)

    # Volume, brightness and media also work on the lock screen.
    for (kind, mods, key), (flags, command) in table.items():
        if key.startswith("xf86") or (mods == "ALT" and key in ("f10", "f11", "f12")):
            assert "l" in flags, f"{path}: {mods}+{key} must be bindl"
    assert action("", "XF86AudioMicMute") == "spawn,swayosd-client --input-volume mute-toggle"

    # mango splits arguments on commas: a comma or a lone "0" field inside
    # a spawn command would silently cut it. Complex commands go in scripts.
    for (kind, mods, key), (_, command) in table.items():
        if command.startswith(("spawn,", "spawn_shell,")):
            body = command.split(",", 1)[1]
            assert "," not in body, f"{path}: comma in command of {mods}+{key}: {body!r}"

    # Every "#:" description belongs to the bind right below it.
    text = lines(path)
    for number, line in enumerate(text):
        if line.startswith("#:"):
            assert BIND.match(text[number + 1]), f"{path}:{number + 1}: '#:' without a bind"
            assert line[2:].strip(), f"{path}:{number + 1}: empty description"


def check_rules(path):
    text = path.read_text()
    shielded = re.findall(r"^windowrule=(.*shield_when_capture:1.*)$", text, re.M)
    # The Wi-Fi QR window shows the network password.
    assert any(re.search(r"(^|,)appid:\^wifi-qr\$($|,)", rule) for rule in shielded), shielded
    for rule in re.findall(r"^(?:windowrule|layerrule)=(.*)$", text, re.M):
        for field in rule.split(","):
            assert ":" in field, f"{path}: malformed rule field {field!r} in {rule!r}"


def check_dir(directory, layout):
    config = settings(directory / "config.conf")
    for name in ("theme.conf", "host.conf", "rules.conf", "binds.conf"):
        assert f"./{name}" in config["source"], f"config.conf does not source {name}"
    assert config["tagrule"] == ["id:*,layout_name:scroller"]
    assert config["tag_num"] == ["10"]
    assert config["exec-once"][0] == "mango-session-start"
    assert config["scroller_ignore_proportion_single"] == ["0"]
    assert config["scroller_default_proportion_single"] == ["1.0"]
    for key, value in {
        "tap_to_click": "1", "trackpad_disable_while_typing": "1",
        "trackpad_natural_scrolling": "1", "trackpad_click_method": "2",
        "mouse_accel_profile": "1", "enable_hotarea": "0",
        "numlockon": "1", "repeat_delay": "600", "repeat_rate": "25",
        # Mod+S and the 4-finger swipe must close the overview, not cycle.
        "ov_tab_mode": "0",
        # Cover-flow overview, from patches/mango-overview-carousel.patch.
        "ov_carousel": "1",
    }.items():
        assert config.get(key) == [value], f"config.conf: {key}={config.get(key)}"

    # The layout lives only in the generated host.conf.
    for name in ("config.conf", "binds.conf", "rules.conf", "gaming.conf", "theme.conf"):
        keys = settings(directory / name)
        assert not any(key.startswith("xkb_rules") for key in keys), f"{name} sets xkb"
    assert settings(directory / "host.conf")["xkb_rules_layout"] == [layout]

    theme = settings(directory / "theme.conf")
    assert theme["focuscolor"] == ["0x7aa2f7ff"], theme["focuscolor"]
    assert theme["cursor_theme"] == ["Bibata-Modern-Ice"]
    assert theme["cursor_size"] == ["20"]

    gaming = lines(directory / "gaming.conf")
    body = [line for line in gaming if line and not line.startswith("#")]
    assert body[0] == "source=./config.conf", "gaming.conf must start from config.conf"
    overrides = settings(directory / "gaming.conf")
    for key in ("gappih", "gappiv", "gappoh", "gappov", "animations", "blur"):
        assert overrides.get(key) == ["0"], f"gaming.conf: {key}"

    # niri may appear in comments (where a setting came from), the old
    # shells may not: their commands would fail silently on a keypress.
    for path in directory.iterdir():
        text = path.read_text().lower()
        for stale in ("noctalia", "dms", "quickshell"):
            assert not re.search(rf"\b{stale}\b", text), f"{path}: stale reference to {stale}"

    check_binds(directory / "binds.conf")
    check_rules(directory / "rules.conf")


# Laptop: it + us on Mod+K. Desktop: us only.
check_dir(args.laptop, "it,us")
check_dir(args.desktop, "us")
print("mango-regressions: ok")

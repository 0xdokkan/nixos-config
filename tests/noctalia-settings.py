#!/usr/bin/env python3
"""Validate the generated config and Storm palette using the real Noctalia CLI."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import tomllib


ROLE_TOKENS = {
    "mPrimary": "primary",
    "mOnPrimary": "on_primary",
    "mSecondary": "secondary",
    "mOnSecondary": "on_secondary",
    "mTertiary": "tertiary",
    "mOnTertiary": "on_tertiary",
    "mError": "error",
    "mOnError": "on_error",
    "mSurface": "surface",
    "mOnSurface": "on_surface",
    "mSurfaceVariant": "surface_variant",
    "mOnSurfaceVariant": "on_surface_variant",
    "mOutline": "outline",
    "mShadow": "shadow",
    "mHover": "hover",
    "mOnHover": "on_hover",
}
ANSI_COLORS = {"black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"}
TERMINAL_TOKENS = {
    "background": "terminal_background",
    "foreground": "terminal_foreground",
    "cursor": "terminal_cursor",
    "cursorText": "terminal_cursor_text",
    "selectionBg": "terminal_selection_bg",
    "selectionFg": "terminal_selection_fg",
}
DIAGNOSTIC = re.compile(r"\b(?:warn(?:ing)?|error|unknown setting|obsolete)\b", re.I)
HEX_COLOR = re.compile(r"#[0-9a-fA-F]{6}")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def without_ansi(text):
    return re.sub(r"\x1b\[[0-9;]*m", "", text)


def validate_result(result):
    output = without_ansi(result.stdout + result.stderr)
    require(result.returncode == 0, f"Noctalia validator failed:\n{output}")
    # Upstream returns 0 even for unknown/obsolete keys. They must fail our check.
    require(not DIAGNOSTIC.search(output), f"Noctalia validation diagnostic:\n{output}")
    require("Config is valid" in output, f"Validator did not confirm validity:\n{output}")


def check_config(config):
    shell = config["shell"]
    require(shell["font_family"] == "Monaspace Argon", "Shell font changed")
    require(shell["launch_apps_as_systemd_services"], "Launcher apps must survive shell restarts")
    require(shell["polkit_agent"], "Native polkit agent is disabled")
    require(shell["clipboard_enabled"], "Clipboard history is disabled")
    require(shell["clipboard_auto_paste"] == "off", "Clipboard must not paste automatically")
    require(not shell["telemetry_enabled"], "Telemetry was enabled")
    theme = config["theme"]
    require(theme["source"] == "custom", "Theme must use the checked-in custom palette")
    require(theme["custom_palette"] == "TokyoNightStorm", "Wrong palette selected")
    require(theme["mode"] == "dark", "Default mode must remain dark")
    templates = theme["templates"]
    require(not templates["enable_builtin_templates"], "Built-in app theming was enabled")
    require(not templates["enable_community_templates"], "Community app theming was enabled")
    require(templates["builtin_ids"] == [], "Unexpected built-in app templates")
    require(templates["community_ids"] == [], "Unexpected community app templates")
    require(not templates.get("user"), "Unexpected custom app templates")

    bar = config["bar"]["default"]
    require(bar["enabled"] and bar["position"] == "top", "Top bar is disabled or moved")
    require(bar["start"] == ["launcher", "workspaces", "active_window"], "Start widgets changed")
    require(bar["center"] == ["media", "audio_visualizer", "clock", "weather"], "Center widgets changed")
    require(
        bar["end"] == ["tray", "clipboard", "cpu", "ram", "notifications", "battery", "control-center"],
        "End widgets changed",
    )
    require(not config["dock"]["enabled"], "Dock must remain disabled")
    require(config["widget"]["cpu"]["stat"] == "cpu_usage", "CPU widget stat changed")
    require(config["widget"]["ram"]["stat"] == "ram_pct", "RAM widget stat changed")
    qr_action = config["widget"]["control-center"]["actions"]["middle"]
    require(
        re.fullmatch(r"exec /nix/store/[a-z0-9]{32}-noctalia-wifi-qr/bin/noctalia-wifi-qr", qr_action),
        "Wi-Fi QR action must use the packaged helper via an absolute path",
    )
    # Inspect only: never run nmcli or read actual network credentials in tests.
    qr_script = Path(qr_action.removeprefix("exec ")).read_text()
    qr_exec = qr_script[qr_script.index("\nexec ") + 1:].replace("\\\n", " ")
    qr_args = shlex.split(qr_exec)
    require(qr_args[0] == "exec", "Wi-Fi QR helper must directly replace itself with Kitty")
    require(re.fullmatch(r"/nix/store/[^/]+-kitty-[^/]+/bin/kitty", qr_args[1]), "Kitty path must be absolute")
    require(qr_args[2:9] == ["--class", "noctalia-wifi-qr", "--title", "Wi-Fi QR", "--hold", "--env", "PAGER="], "Wi-Fi QR privacy window identifiers changed")
    require(re.fullmatch(r"/nix/store/[^/]+-networkmanager-[^/]+/bin/nmcli", qr_args[9]), "nmcli path must be absolute")
    require(qr_args[10:] == ["device", "wifi", "show-password"], "Wi-Fi QR helper must not persist or send credentials")
    battery = config["widget"]["battery"]
    require(battery["device"] == "auto", "Battery must use automatic system-battery selection")
    require(battery["show_label"] and battery["label_content"] == "percent", "Battery percentage hidden")
    require(config["system"]["monitor"]["enabled"], "System monitoring disabled")
    require(config["weather"]["enabled"], "Weather disabled")
    require(not config["location"]["auto_locate"], "IP geolocation was enabled implicitly")
    require(config["notification"]["enable_daemon"], "Notification daemon disabled")
    require(config["lockscreen"]["enabled"], "Session lock disabled")
    require(config["lockscreen"]["lock_before_suspend"], "Lock before sleep disabled")
    require(not config["lockscreen"]["allow_empty_password"], "Empty-password submissions enabled")


def check_palette(palette, generated):
    require(set(palette) == {"dark", "light"}, "Both palette modes must be present")
    expected_core = {
        "dark": {"mPrimary": "#7aa2f7", "mSurface": "#24283b", "mOnSurface": "#c0caf5"},
        "light": {"mPrimary": "#3a5bab", "mSurface": "#f0f2f7", "mOnSurface": "#1a1b26"},
    }
    for mode, colors in palette.items():
        tokens = generated[mode]
        for key, expected in expected_core[mode].items():
            require(colors[key] == expected, f"{mode}.{key} is not the Storm color")
        for key, token in ROLE_TOKENS.items():
            require(isinstance(colors.get(key), str) and HEX_COLOR.fullmatch(colors[key]), f"Invalid {mode}.{key}")
            require(HEX_COLOR.fullmatch(tokens[token]), f"Noctalia did not produce {mode}.{token}")
            # Noctalia enforces minimum contrast for outlines and derives container
            # shades. The other explicit role tokens preserve the input palette.
            if key != "mOutline":
                require(tokens[token] == colors[key], f"Noctalia changed {mode}.{token}")
        terminal = colors["terminal"]
        for key, token in TERMINAL_TOKENS.items():
            require(HEX_COLOR.fullmatch(terminal[key]), f"Invalid {mode}.terminal.{key}")
            require(tokens[token] == terminal[key], f"Noctalia changed {mode}.{token}")
        for group in ("normal", "bright"):
            require(set(terminal[group]) == ANSI_COLORS, f"Incomplete {mode}.terminal.{group}")
            for color, value in terminal[group].items():
                require(HEX_COLOR.fullmatch(value), f"Invalid {mode}.terminal.{group}.{color}")
                require(tokens[f"terminal_{group}_{color}"] == value, f"ANSI color changed: {mode}.{group}.{color}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--noctalia", required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--palette", type=Path, required=True)
    args = parser.parse_args()
    check_config(tomllib.loads(args.config.read_text()))
    palette = json.loads(args.palette.read_text())

    with tempfile.TemporaryDirectory(prefix="noctalia-settings-") as temporary:
        root = Path(temporary)
        env = os.environ.copy()
        # Noctalia-specific roots leave HOME untouched while isolating all its
        # config/state/data. The real desktop and D-Bus session are never used.
        env.update({
            "NOCTALIA_CONFIG_HOME": str(root / "config"),
            "NOCTALIA_STATE_HOME": str(root / "state"),
            "NOCTALIA_DATA_HOME": str(root / "data"),
            "XDG_CACHE_HOME": str(root / "cache"),
            "XDG_RUNTIME_DIR": str(root / "runtime"),
            "NO_COLOR": "1",
        })
        (root / "runtime").mkdir(mode=0o700)
        for variable in ("WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "DBUS_SYSTEM_BUS_ADDRESS"):
            env.pop(variable, None)

        def run(*command):
            return subprocess.run([args.noctalia, *map(str, command)], env=env, capture_output=True, text=True, timeout=30)

        validate_result(run("config", "validate", args.config))

        # Prove that advisory unknown-key warnings cannot sneak through merely
        # because Noctalia considers their exit code successful.
        unknown_config = root / "unknown.toml"
        unknown_config.write_text("[shell]\nunknown_noctalia_regression_option = true\n")
        unknown_result = run("config", "validate", unknown_config)
        require(DIAGNOSTIC.search(without_ansi(unknown_result.stdout + unknown_result.stderr)), "Unknown key produced no diagnostic")
        try:
            validate_result(unknown_result)
        except AssertionError:
            pass
        else:
            raise AssertionError("Validation wrapper accepted an unknown key")

        theme = run("theme", "--theme-json", args.palette, "--both")
        require(theme.returncode == 0, f"Palette conversion failed:\n{theme.stderr}")
        require(not DIAGNOSTIC.search(without_ansi(theme.stderr)), f"Palette diagnostic:\n{theme.stderr}")
        check_palette(palette, json.loads(theme.stdout))

    print("Noctalia: config, warning rejection and both Tokyo Night Storm variants passed")


if __name__ == "__main__":
    main()

"""Static behavior checks; the derivation also runs niri's real KDL validator.

This deliberately checks the repository's top-level block layout, not arbitrary
KDL. Failing to find a block is an error, so a format change cannot silently skip
the privacy checks. No compositor or screencast is started.
"""

import re
import sys
from pathlib import Path


def check(path: Path) -> None:
    text = re.sub(r"(?m)^\s*//[^\n]*", "", path.read_text())
    rules = re.findall(r"(?ms)^layer-rule\s*\{\n(.*?)^\}", text)
    privacy_patterns = [
        re.compile(pattern)
        for rule in rules
        if re.search(r'^\s*block-out-from "screencast"\s*$', rule, re.M)
        for pattern in re.findall(r'^\s*match namespace="([^"]+)"\s*$', rule, re.M)
    ]
    assert privacy_patterns, f"{path}: no screencast privacy rules found"

    for namespace in (
        "dms:clipboard",
        "dms:clipboard-popout",
        "dms:clipboard-context-menu",
        "dms:clipboard:clickcatcher",
        "dms:clipboard-popout:clickcatcher",
        "dms:wifi-password",
        "dms:wifi-qrcode",
        "dms:wifi-qrcode:clickcatcher",
        "dms:bluetooth-pairing",
        "dms:polkit-auth-surface",
    ):
        assert any(p.search(namespace) for p in privacy_patterns), (
            f"{path}: sensitive layer {namespace} is not protected"
        )
    for namespace in ("dms:bar", "dms:dock", "dms:clipboards", "other:clipboard"):
        assert not any(p.search(namespace) for p in privacy_patterns), (
            f"{path}: unrelated layer {namespace} is unexpectedly hidden"
        )

    assert len(re.findall(r'^workspace "scratch"\s*$', text, re.M)) == 1
    bindings = {
        key: body
        for key, body in re.findall(r"(?ms)^\s*(Mod\+[^\s{]+)[^\n{]*\{([^}]+)\}", text)
    }
    assert 'move-column-to-workspace "scratch" focus=false' in bindings["Mod+Alt+S"]
    assert 'focus-workspace "scratch"' in bindings["Mod+Ctrl+S"]
    assert "toggle-overview" in bindings["Mod+S"]
    assert not re.search(r"move-column-to-workspace\s+99\b", text)
    print(f"{path}: privacy and scratch checks passed")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: niri-regressions.py CONFIG...")
    for argument in sys.argv[1:]:
        check(Path(argument))

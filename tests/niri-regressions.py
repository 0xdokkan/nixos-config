"""Static behavior checks; the derivation also runs niri's real KDL validator.

This deliberately checks the repository's top-level block layout, not arbitrary
KDL. Failing to find a block is an error, so a format change cannot silently skip
the privacy checks. No compositor or screencast is started.
"""

import argparse
import json
import re
from pathlib import Path


def polkit_identity(dms_root: Path | None) -> tuple[str, set[str]]:
    app_id = "com.danklinux.dms"
    titles = {"Authentication", "Autenticazione"}
    if dms_root is None:
        return app_id, titles

    shell = (dms_root / "shell.qml").read_text()
    assert re.search(rf"^//@ pragma AppId {re.escape(app_id)}$", shell, re.M), (
        "DMS changed its app-id; review the Polkit privacy rule"
    )
    modal = (dms_root / "Modals/PolkitAuthModal.qml").read_text()
    assert re.search(r'^\s*title: I18n\.tr\("Authentication"\)\s*$', modal, re.M), (
        "DMS changed its Polkit window title; review the privacy rule"
    )
    translations = list((dms_root / "translations/poexports").glob("*.json"))
    assert translations, "DMS translations not found; do not silently skip this check"
    for translation in translations:
        # I18n.tr checks the term's context first, then the other contexts.
        # Cover every non-empty translation of this term, including fallbacks.
        for context in json.loads(translation.read_text()).values():
            translated = context.get("Authentication")
            if translated:
                assert isinstance(translated, str)
                titles.add(translated)
    return app_id, titles


def check(path: Path, app_id: str, titles: set[str]) -> None:
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

    window_patterns = []
    for rule in re.findall(r"(?ms)^window-rule\s*\{\n(.*?)^\}", text):
        if not re.search(r'^\s*block-out-from "screencast"\s*$', rule, re.M):
            continue
        matches = re.findall(
            r'^\s*match app-id=r#"([^"]+)"# title=r#"([^"]+)"#\s*$', rule, re.M
        )
        assert matches, f"{path}: privacy window rule must constrain app-id AND title"
        assert len(matches) == len(re.findall(r"^\s*match\b", rule, re.M)), (
            f"{path}: untested match in privacy window rule"
        )
        window_patterns.extend((re.compile(app), re.compile(title)) for app, title in matches)

    def protected(app: str, title: str) -> bool:
        return any(a.search(app) and t.search(title) for a, t in window_patterns)

    for title in titles:
        assert protected(app_id, title), f"{path}: Polkit title {title!r} is not protected"
        for unrelated in ("firefox", "comXdanklinuxXdms", "com.danklinux.dms.extra"):
            assert not protected(unrelated, title), f"{path}: privacy app-id is too broad"
    for title in ("Settings", "Notepad", "Authentication settings", "", "My Authentication"):
        assert not protected(app_id, title), f"{path}: unrelated DMS window is hidden"

    assert len(re.findall(r'^workspace "scratch"\s*$', text, re.M)) == 1
    bindings = {
        key: body
        for key, body in re.findall(r"(?ms)^\s*(Mod\+[^\s{]+)[^\n{]*\{([^}]+)\}", text)
    }
    assert 'move-column-to-workspace "scratch" focus=false' in bindings["Mod+Alt+S"]
    assert 'focus-workspace "scratch"' in bindings["Mod+Ctrl+S"]
    assert "toggle-overview" in bindings["Mod+S"]
    assert not re.search(r"move-column-to-workspace\s+99\b", text)
    print(f"{path}: privacy ({len(titles)} Polkit titles) and scratch checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dms-root", type=Path)
    parser.add_argument("configs", type=Path, nargs="+")
    args = parser.parse_args()
    app_id, titles = polkit_identity(args.dms_root)
    for path in args.configs:
        check(path, app_id, titles)

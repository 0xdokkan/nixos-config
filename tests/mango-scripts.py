"""Gli script di dotfiles/mango/scripts con comandi finti al posto di mango,
rofi, awww & co.: nessuno tocca il compositor, gli appunti o i file veri.

    python mango-scripts.py SCRIPTS_DIR BINDS_CONF

Ogni comando finto registra argomenti e stdin in calls.jsonl e risponde
secondo le regole del test (stdout, codice di uscita, una volta sola...).
filesearch.sh e gamemode.sh hanno i loro test (filesearch.py, gamemode.nix).
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


STUB = r'''
import fnmatch, json, os, sys
from pathlib import Path

root = Path(os.environ["STUB_ROOT"])
name = Path(sys.argv[0]).name
args = sys.argv[1:]
stdin = sys.stdin.buffer.read().decode("utf-8", "surrogateescape") if not sys.stdin.isatty() else ""
env = {k: os.environ[k] for k in ("SWAYNC_TOGGLE_STATE",) if k in os.environ}
with (root / "calls.jsonl").open("a") as calls:
    calls.write(json.dumps({"cmd": name, "args": args, "stdin": stdin, "env": env}) + "\n")

used_file = root / "used.json"
used = json.loads(used_file.read_text()) if used_file.exists() else []
for index, rule in enumerate(json.loads((root / "rules.json").read_text())):
    if rule["cmd"] != name or index in used:
        continue
    if not fnmatch.fnmatchcase(" ".join(args), rule.get("args", "*")):
        continue
    if rule.get("once"):
        used_file.write_text(json.dumps(used + [index]))
    if rule.get("grim"):
        if args[-1] == "-":
            sys.stdout.write("PNG")
        else:
            Path(args[-1]).write_text("PNG")
    sys.stdout.write(rule.get("stdout", ""))
    sys.exit(rule.get("status", 0))
'''

STUBBED = ["mmsg", "xdotool", "notify-send", "busctl", "rofi", "loginctl",
           "systemctl", "cliphist", "wl-copy", "grim", "slurp", "swappy", "awww"]


class Harness:
    def __init__(self, root: Path, scripts: Path):
        self.root = root
        self.scripts = scripts
        self.bin = root / "bin"
        self.bin.mkdir()
        for name in STUBBED:
            stub = self.bin / name
            stub.write_text(f"#!{sys.executable}\n{STUB}")
            stub.chmod(0o755)
        self.base_env = {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "HOME": str(root / "home"),
            "STUB_ROOT": str(root),
            "LC_ALL": "C",
        }
        (root / "home").mkdir()

    def run(self, script, *args, rules=(), env=None, status=0):
        for name in ("calls.jsonl", "used.json"):
            (self.root / name).unlink(missing_ok=True)
        (self.root / "rules.json").write_text(json.dumps(list(rules)))
        result = subprocess.run(
            ["bash", str(self.scripts / script), *args],
            env={**self.base_env, **(env or {})}, cwd=self.root,
            stdin=subprocess.DEVNULL, capture_output=True, text=True,
        )
        assert result.returncode == status, (script, args, result.returncode, result.stderr)
        calls_file = self.root / "calls.jsonl"
        calls = [json.loads(line) for line in calls_file.read_text().splitlines()] if calls_file.exists() else []
        return calls, result


def cmds(calls):
    return [[call["cmd"], *call["args"]] for call in calls]


SUCCESS = '{"success":true}\n'


def client(**fields):
    return json.dumps({"id": 3, "appid": "kitty", "is_floating": False, "is_global": False, **fields})


def test_dontkillsteam(h: Harness):
    rules = [{"cmd": "mmsg", "args": "get focusing-client", "stdout": client()},
             {"cmd": "mmsg", "args": "dispatch *", "stdout": SUCCESS}]
    calls, _ = h.run("dontkillsteam.sh", rules=rules)
    assert cmds(calls) == [["mmsg", "get", "focusing-client"], ["mmsg", "dispatch", "killclient"]]

    for appid in ("steam", "Steam"):
        rules[0]["stdout"] = client(appid=appid)
        calls, _ = h.run("dontkillsteam.sh", rules=rules)
        assert cmds(calls)[1:] == [["xdotool", "getactivewindow", "windowunmap"]], calls

    # xdotool non ce la fa: Steam si chiude come le altre finestre.
    calls, _ = h.run("dontkillsteam.sh", rules=rules + [{"cmd": "xdotool", "status": 1}])
    assert cmds(calls)[-1] == ["mmsg", "dispatch", "killclient"]

    rules[0]["stdout"] = '{"error":"no focused client"}\n'
    calls, _ = h.run("dontkillsteam.sh", rules=rules)
    assert "xdotool" not in [c["cmd"] for c in calls]


def test_windowpin(h: Harness):
    def dispatched(focused, extra=(), status=0):
        rules = [{"cmd": "mmsg", "args": "get focusing-client", "stdout": focused},
                 *extra, {"cmd": "mmsg", "args": "dispatch *", "stdout": SUCCESS}]
        calls, _ = h.run("windowpin.sh", rules=rules, status=status)
        return [c["args"][1] for c in calls if c["args"][0] == "dispatch"]

    assert dispatched(client()) == ["togglefloating", "centerwin", "toggleglobal"]
    assert dispatched(client(is_floating=True)) == ["centerwin", "toggleglobal"]
    assert dispatched(client(is_global=True)) == ["togglefloating", "centerwin"]
    assert dispatched(client(is_floating=True, is_global=True)) == ["toggleglobal", "togglefloating"]
    assert dispatched('{"error":"no focused client"}\n') == []
    # mango rifiuta il comando: si ferma con errore, senza andare avanti.
    error = [{"cmd": "mmsg", "args": "dispatch togglefloating", "stdout": '{"error":"unknown function"}\n'}]
    assert dispatched(client(), error, status=1) == ["togglefloating"]


def test_keyboardswitch(h: Harness):
    rules = [{"cmd": "mmsg", "args": "get keyboardlayout", "stdout": '{"layout":"us"}\n'},
             {"cmd": "mmsg", "stdout": SUCCESS}]
    calls, _ = h.run("keyboardswitch.sh", rules=rules)
    assert cmds(calls)[0] == ["mmsg", "dispatch", "switch_keyboard_layout"]
    assert cmds(calls)[-1][0] == "notify-send" and cmds(calls)[-1][-1] == "us"
    # Senza demone delle notifiche il cambio di layout è comunque fatto.
    h.run("keyboardswitch.sh", rules=rules + [{"cmd": "notify-send", "status": 1}])


def test_nightlight(h: Harness):
    get = "--user get-property rs.wl-gammarelay / rs.wl.gammarelay Temperature"
    set_ = ["busctl", "--user", "set-property", "rs.wl-gammarelay", "/", "rs.wl.gammarelay", "Temperature", "q"]

    def at(kelvin):
        return [{"cmd": "busctl", "args": get, "stdout": f"q {kelvin}\n"}]

    for kelvin, expected in ((4000, "true"), (6500, "false")):
        _, result = h.run("nightlight.sh", "status", rules=at(kelvin))
        assert result.stdout == f"{expected}\n"
    _, result = h.run("nightlight.sh", "status", rules=[{"cmd": "busctl", "status": 1}])
    assert result.stdout == "false\n", "servizio fermo = luce spenta"

    for state, kelvin in (("true", "4000"), ("false", "6500")):
        calls, _ = h.run("nightlight.sh", "toggle", rules=at(4000 if state == "false" else 6500),
                         env={"SWAYNC_TOGGLE_STATE": state})
        assert cmds(calls) == [set_ + [kelvin]], calls
    for now, kelvin in ((6500, "4000"), (4000, "6500")):
        calls, _ = h.run("nightlight.sh", "toggle", rules=at(now))
        assert cmds(calls)[-1] == set_ + [kelvin]
    for arg, kelvin in (("on", "4000"), ("off", "6500")):
        calls, _ = h.run("nightlight.sh", arg)
        assert cmds(calls) == [set_ + [kelvin]]
    h.run("nightlight.sh", "boh", status=2)


def test_powermenu(h: Harness):
    expected = [["loginctl", "lock-session"], ["mmsg", "dispatch", "quit"],
                ["systemctl", "suspend"], ["systemctl", "reboot"], ["systemctl", "poweroff"]]
    for index, action in enumerate(expected):
        calls, _ = h.run("powermenu.sh", rules=[{"cmd": "rofi", "stdout": f"{index}\n"}])
        assert calls[0]["cmd"] == "rofi" and "-no-custom" in calls[0]["args"]
        labels = [line.split("  ", 1)[1] for line in calls[0]["stdin"].splitlines()]
        assert labels == ["Blocca", "Esci da mango", "Sospendi", "Riavvia", "Spegni"], labels
        assert cmds(calls)[1:] == [action], calls
    for rules in ([{"cmd": "rofi", "status": 1}], [{"cmd": "rofi", "stdout": "9\n"}]):
        calls, _ = h.run("powermenu.sh", rules=rules)
        assert [c["cmd"] for c in calls] == ["rofi"]


def test_clipboard(h: Harness):
    history = [{"cmd": "cliphist", "args": "list", "stdout": "12\tciao\n7\tvecchio\n"},
               {"cmd": "cliphist", "args": "decode", "stdout": "ciao"}]
    calls, _ = h.run("clipboard.sh", rules=history + [{"cmd": "rofi", "stdout": "12\tciao\n"}])
    rofi = next(c for c in calls if c["cmd"] == "rofi")
    assert rofi["stdin"] == "12\tciao\n7\tvecchio\n"
    joined = " ".join(rofi["args"])
    assert "-display-columns 2" in joined and "-kb-custom-1 Shift+Delete" in joined
    assert rofi["args"][rofi["args"].index("-kb-delete-entry") + 1] == ""
    decode = next(c for c in calls if c["args"][:1] == ["decode"])
    assert decode["stdin"] == "12\tciao\n"
    assert cmds(calls)[-1] == ["wl-copy"] and calls[-1]["stdin"] == "ciao"

    # Shift+Canc (uscita 10) cancella e riapre; poi Esc.
    rules = history + [{"cmd": "rofi", "stdout": "7\tvecchio\n", "status": 10, "once": True},
                       {"cmd": "rofi", "status": 1}]
    calls, _ = h.run("clipboard.sh", rules=rules)
    assert [c["cmd"] + " " + c["args"][0] if c["args"] else c["cmd"] for c in calls] == [
        "cliphist list", "rofi -dmenu", "cliphist delete", "cliphist list", "rofi -dmenu"]
    assert calls[2]["stdin"] == "7\tvecchio\n"

    calls, _ = h.run("clipboard.sh", rules=history + [{"cmd": "rofi", "status": 1}])
    assert "wl-copy" not in [c["cmd"] for c in calls]


def test_screenshot(h: Harness):
    shots = h.root / "Screen shots"
    env = {"SCREENSHOT_DIR": str(shots)}
    name = re.compile(r"/screenshot from \d{4}-\d\d-\d\d \d\d-\d\d-\d\d\.png$")
    region = [{"cmd": "slurp", "stdout": "10,20 300x200\n"}, {"cmd": "grim", "grim": True}]

    calls, _ = h.run("screenshot.sh", "region", rules=region, env=env)
    grim = next(c for c in calls if c["cmd"] == "grim")
    assert grim["args"][:2] == ["-g", "10,20 300x200"] and name.search(grim["args"][2]), grim
    copy = next(c for c in calls if c["cmd"] == "wl-copy")
    assert copy["args"] == ["--type", "image/png"] and copy["stdin"] == "PNG"
    notify = next(c for c in calls if c["cmd"] == "notify-send")
    assert notify["args"][notify["args"].index("-i") + 1] == grim["args"][2]

    calls, _ = h.run("screenshot.sh", "region", rules=[{"cmd": "slurp", "status": 1}], env=env)
    assert [c["cmd"] for c in calls] == ["slurp"], "Esc durante la selezione"

    monitors = json.dumps({"monitors": [{"name": "DP-1", "active": False},
                                        {"name": "eDP-1", "active": True}]})
    calls, _ = h.run("screenshot.sh", "screen", env=env, rules=[
        {"cmd": "mmsg", "args": "get all-monitors", "stdout": monitors}, {"cmd": "grim", "grim": True}])
    grim = next(c for c in calls if c["cmd"] == "grim")
    assert grim["args"][:2] == ["-o", "eDP-1"] and name.search(grim["args"][2])

    calls, _ = h.run("screenshot.sh", "edit", rules=region, env=env)
    assert cmds(calls)[1:] == [["grim", "-g", "10,20 300x200", "-"], ["swappy", "-f", "-"]]
    assert calls[-1]["stdin"] == "PNG"

    h.run("screenshot.sh", "region", rules=region + [{"cmd": "notify-send", "status": 1}], env=env)
    h.run("screenshot.sh", "boh", env=env, status=2)
    assert list(shots.glob("*.png")), "la cartella si crea da sola"


def test_wallpaper(h: Harness):
    walls = h.root / "Wall papers"
    walls.mkdir()
    names = ["c d.webp", "a.png", "b.JPG", "-trattino.png", "note.txt", "a capo\n.png"]
    for name in names:
        (walls / name).write_text("img")
    images = [str(walls / n) for n in sorted(["c d.webp", "a.png", "b.JPG", "-trattino.png"])]
    state_home = h.root / "state"
    state = state_home / "wallpaper" / "current"
    default = h.root / "default.png"
    default.write_text("img")
    env = {"WALLPAPER_DIR": str(walls), "XDG_STATE_HOME": str(state_home),
           "WALLPAPER_DEFAULT": str(default)}

    def shown(*args, rules=(), status=0):
        calls, _ = h.run("wallpaper.sh", *args, rules=rules, env=env, status=status)
        imgs = [c["args"] for c in calls if c["cmd"] == "awww" and c["args"][0] == "img"]
        return imgs[-1] if imgs else None

    def current():
        return state.read_text().rstrip("\n") if state.exists() else None

    args = shown("next")
    assert args[-1] == images[0] and args[1:3] == ["--transition-type", "grow"], args
    assert current() == images[0]
    for step, index in (("next", 1), ("prev", 0), ("prev", 3), ("next", 0)):
        assert shown(step)[-1] == images[index], (step, index)
        assert current() == images[index]

    # Lo sfondo attuale non è (più) nella cartella.
    state.write_text("/altrove.png\n")
    assert shown("next")[-1] == images[0]
    state.write_text("/altrove.png\n")
    assert shown("prev")[-1] == images[-1]

    # awww fallisce: lo stato non cambia.
    before = current()
    shown("next", rules=[{"cmd": "awww", "args": "img *", "status": 1}], status=1)
    assert current() == before

    calls, _ = h.run("wallpaper.sh", "pick", env=env, rules=[{"cmd": "rofi", "stdout": "2\n"}])
    rofi = next(c for c in calls if c["cmd"] == "rofi")
    assert {"-show-icons", "-no-custom"} <= set(rofi["args"]) and "-format" in rofi["args"]
    entries = rofi["stdin"].splitlines()
    assert entries[2] == f"{Path(images[2]).name}\0icon\x1f{images[2]}", entries
    assert len(entries) == 4, "note.txt e il nome con a capo restano fuori"
    assert current() == images[2]
    for rules in ([{"cmd": "rofi", "status": 1}], [{"cmd": "rofi", "stdout": "x\n"}],
                  [{"cmd": "rofi", "stdout": "99\n"}]):
        assert shown("pick", rules=rules) is None
        assert current() == images[2]

    assert shown("restore") == ["img", "--transition-type", "none", images[2]]
    state.unlink()
    assert shown("restore") == ["img", "--transition-type", "none", str(default)]
    assert current() is None, "lo sfondo di serie non diventa una scelta"
    state.parent.mkdir(parents=True, exist_ok=True)
    state.write_text(str(walls / "cancellato.png") + "\n")
    assert shown("restore")[-1] == str(default)

    shutil.rmtree(walls)
    walls.mkdir()
    calls, _ = h.run("wallpaper.sh", "next", env=env, status=1)
    assert [c["cmd"] for c in calls] == ["notify-send"]
    h.run("wallpaper.sh", "boh", env=env, status=2)


def test_cheatsheet(h: Harness, binds: Path):
    env = {"CHEATSHEET_BINDS": str(binds)}
    _, result = h.run("cheatsheet.sh", "--list", env=env)
    lines = result.stdout.splitlines()
    rows = dict(re.split(r" {3,}", line, maxsplit=1) for line in lines)
    expected = {
        "Mod+Q / Alt+F4": "Chiudi finestra (Steam va in tray)",
        "Mod+Shift+/": "Cheatsheet di questi tasti",
        "Mod+Space / A / Tab / Shift+A": "Avvia app (rofi)",
        "Mod+1..0": "Vai al tag",
        "Mod+.": "Impila nella colonna a destra / esci",
        "Mod+Alt+P / Stamp": "Screenshot dello schermo",
        "Mod+Alt+→": "Sfondo successivo",
        "Mod+Backspace": "Menu di spegnimento",
        "Mod+Shift+M / Alt+Invio": "Schermo intero",
    }
    for keys, desc in expected.items():
        assert rows.get(keys) == desc, (keys, rows.get(keys))
    # Una riga per descrizione, tutte le descrizioni nella stessa colonna
    # (le frecce contano un carattere: gawk gira in C.UTF-8).
    descs = []
    for line in binds.read_text().splitlines():
        if line.startswith("#:"):
            text = line[2:].strip()
            desc = text.split(" | ", 1)[1] if " | " in text else text
            if desc not in descs:
                descs.append(desc)
    assert list(rows.values()) == descs
    assert len({line.index(desc) for line, desc in zip(lines, rows.values())}) == 1
    assert not re.search(r"SUPER|SHIFT|CTRL|NONE|code:", "".join(rows)), rows

    calls, _ = h.run("cheatsheet.sh", env=env, rules=[{"cmd": "rofi", "status": 1}])
    assert calls[0]["cmd"] == "rofi" and calls[0]["stdin"] == result.stdout


def main(scripts: Path, binds: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="mango-scripts-") as temporary:
        h = Harness(Path(temporary), scripts)
        for test in (test_dontkillsteam, test_windowpin, test_keyboardswitch, test_nightlight,
                     test_powermenu, test_clipboard, test_screenshot, test_wallpaper):
            test(h)
            print(f"ok {test.__name__}")
        test_cheatsheet(h, binds)
        print("ok test_cheatsheet")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())

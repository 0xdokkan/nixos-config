#!/usr/bin/env python3
"""Three games, one small Rofi menu. Game files remain where the user put them."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


GAMES = {
    "zero-mission": {
        "title": "Metroid: Zero Mission",
        "platform": "Game Boy Advance",
        "extensions": (".gba",),
        "core": "MGBA",
    },
    "symphony": {
        "title": "Castlevania: Symphony of the Night",
        "platform": "PlayStation",
        "extensions": (".cue", ".chd"),
        "core": "PSX",
    },
    "super-metroid": {
        "title": "Super Metroid",
        "platform": "Super Nintendo",
        "extensions": (".sfc", ".smc"),
        "core": "SNES",
    },
}

BIOS = {
    "8dd7d5296a650fac7319bce665a6a53c": "scph5500.bin",
    "490f666e1afb15b7362b406ed1cea246": "scph5501.bin",
    "32736f17079d0b2b7024407c39bd3050": "scph5502.bin",
}

DEFAULT_CONFIG = {
    "menu_driver": "ozone",
    "video_fullscreen": "true",
    "video_windowed_fullscreen": "true",
    "config_save_on_exit": "true",
    "autosave_interval": "10",
    "savestate_auto_load": "false",
    "input_menu_toggle": "f1",
    "input_save_state": "f2",
    "input_load_state": "f4",
    "input_exit_emulator": "escape",
}


class SuiteError(Exception):
    """A problem that can be explained directly in the launcher."""


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, delete=False
        ) as stream:
            temporary = Path(stream.name)
            stream.write(text)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def config_values(text, values):
    """Replace suite-owned keys, preserving the player's other settings."""
    keys = re.compile(r"^\s*(" + "|".join(map(re.escape, values)) + r")\s*=")
    lines = [line for line in text.splitlines() if not keys.match(line)]
    for key, value in values.items():
        value = str(value)
        # RetroArch's config format has no reliable escaping for these paths.
        if any(char in value for char in ('"', "\n", "\r")):
            raise SuiteError("Il percorso delle impostazioni contiene virgolette o a capo.")
        lines.append(f'{key} = "{value}"')
    return "\n".join(lines) + "\n"


def validate_game_path(game_id, path):
    path = Path(path).expanduser().absolute()
    if not path.is_file():
        raise SuiteError(f"File non trovato:\n{path}")
    if path.suffix.lower() not in GAMES[game_id]["extensions"]:
        formats = ", ".join(GAMES[game_id]["extensions"])
        raise SuiteError(f"Per questo gioco scegli un file {formats}.")
    if path.suffix.lower() == ".cue":
        if path.stat().st_size > 1024 * 1024:
            raise SuiteError("Il file CUE è troppo grande: scegli l'indice del disco.")
        raw = path.read_bytes()
        try:
            cue = raw.decode("utf-8-sig")
        except UnicodeDecodeError:
            try:
                cue = raw.decode("cp1252")
            except UnicodeDecodeError as exc:
                raise SuiteError("La codifica del CUE non è leggibile. Scegli un CUE valido o un CHD.") from exc
        tracks = re.findall(
            r'^\s*FILE\s+(?:"([^"\r\n]+)"|(\S+))\s+\S+', cue, re.I | re.M
        )
        if not tracks:
            raise SuiteError("Il CUE non contiene tracce FILE. Scegli un CUE completo o un CHD.")
        for quoted, plain in tracks:
            track = quoted or plain
            if not (path.parent / track).is_file():
                raise SuiteError(
                    f"Manca una traccia indicata dal CUE:\n{track}\n\n"
                    "Mantieni il CUE e tutti i BIN nelle loro cartelle originali."
                )
    return path


class Suite:
    def __init__(self, env=None):
        self.env = dict(os.environ if env is None else env)
        home = Path(self.env.get("HOME", str(Path.home())))
        self.config = Path(self.env.get("XDG_CONFIG_HOME") or home / ".config") / "retro-suite"
        self.data = Path(self.env.get("XDG_DATA_HOME") or home / ".local/share") / "retro-suite"
        self.state = Path(self.env.get("XDG_STATE_HOME") or home / ".local/state") / "retro-suite"
        for path in (self.config, self.data / "bios", self.state):
            path.mkdir(parents=True, exist_ok=True)
        self.library_path = self.config / "library.json"

    def tool(self, name):
        value = self.env.get("RETRO_SUITE_" + name)
        if not value:
            raise SuiteError(f"Dipendenza non configurata: {name}. Avvia il comando retro-suite.")
        return value

    def dialog(self, text, error=False):
        print(text, file=sys.stderr if error else sys.stdout)
        subprocess.run(
            [self.tool("ZENITY"), "--error" if error else "--info", "--no-markup",
             "--title=Retro Suite", "--width=520", "--text=" + text], check=False
        )

    def menu(self, title, items, message=None):
        command = [self.tool("ROFI"), "-dmenu", "-i", "-no-custom", "-format", "i", "-p", title,
                   "-theme-str", "window { width: 680px; } listview { lines: 7; }"]
        if message:
            command += ["-mesg", message]
        result = subprocess.run(command, input="\n".join(items) + "\n",
                                text=True, capture_output=True, check=False)
        if result.returncode == 1:
            return None
        if result.returncode != 0:
            raise SuiteError("Impossibile aprire il menu Rofi. Avvia Retro Suite dalla sessione desktop.")
        try:
            index = int(result.stdout.strip())
            if 0 <= index < len(items):
                return index
        except ValueError:
            pass
        raise SuiteError("Il menu ha restituito una selezione non valida.")

    def choose_file(self, title, extensions):
        patterns = " ".join("*" + ext + " *" + ext.upper() for ext in extensions)
        result = subprocess.run(
            [self.tool("ZENITY"), "--file-selection", "--title=" + title,
             "--file-filter=File compatibili | " + patterns],
            text=True, capture_output=True, check=False,
        )
        if result.returncode == 1:
            return None
        if result.returncode != 0:
            raise SuiteError("Impossibile aprire la finestra di scelta del file.")
        value = result.stdout.removesuffix("\n")
        return Path(value) if value else None

    def library(self):
        if not self.library_path.exists():
            return {"version": 1, "games": {}}
        try:
            data = json.loads(self.library_path.read_text(encoding="utf-8"))
            if (not isinstance(data, dict) or data.get("version") != 1
                    or not isinstance(data.get("games"), dict)):
                raise ValueError("formato sconosciuto")
            for value in data["games"].values():
                if not isinstance(value, str) or not Path(value).is_absolute():
                    raise ValueError("percorso non valido")
            return data
        except (ValueError, OSError) as exc:
            raise SuiteError(f"Non riesco a leggere {self.library_path}.\nIl file è stato conservato.\n{exc}") from exc

    def associate(self, game_id):
        game = GAMES[game_id]
        selected = self.choose_file("Scegli " + game["title"], game["extensions"])
        if selected is None:
            return None
        selected = validate_game_path(game_id, selected)
        # Lock only the read/modify/write; never keep it while a dialog is open.
        with (self.state / "library.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            data = self.library()
            data["games"][game_id] = str(selected)
            atomic_write(self.library_path, json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        return selected

    def import_bios(self):
        selected = self.choose_file("Importa un BIOS PlayStation (SCPH-5500, 5501 o 5502)", (".bin", ".rom"))
        if selected is None:
            return
        # Known BIOS dumps are exactly 512 KiB; reject a game image before reading it.
        if selected.stat().st_size != 524288:
            raise SuiteError("Questo file non è un BIOS PlayStation SCPH-5500/5501/5502 da 512 KiB.")
        content = selected.read_bytes()
        name = BIOS.get(hashlib.md5(content).hexdigest())
        if name is None:
            raise SuiteError("BIOS non riconosciuto. Nessun file è stato copiato.\nSono supportati SCPH-5500, 5501 e 5502.")
        destination = self.data / "bios" / name
        if destination.exists():
            if destination.read_bytes() != content:
                raise SuiteError(f"Esiste già un file diverso: {destination}\nControllalo prima di importare il BIOS.")
        else:
            # Exclusive creation protects an existing BIOS, even across two launchers.
            with destination.open("xb") as stream:
                stream.write(content)
        self.dialog(f"BIOS importato: {name}\nL'originale resta nella sua cartella.")

    def game_config(self, game_id):
        filename = self.config / (game_id + ".cfg")
        text = filename.read_text(encoding="utf-8") if filename.exists() else config_values("", DEFAULT_CONFIG)
        paths = {
            "system_directory": self.data / "bios",
            "savefile_directory": self.data / "saves" / game_id,
            "savestate_directory": self.data / "states" / game_id,
            "screenshot_directory": self.data / "screenshots" / game_id,
            "input_remapping_directory": self.config / "remaps",
        }
        for path in paths.values():
            path.mkdir(parents=True, exist_ok=True)
        paths["core_options_path"] = self.config / (game_id + "-options.cfg")
        atomic_write(filename, config_values(text, paths))
        return filename

    def launch(self, game_id):
        with (self.state / (game_id + ".lock")).open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise SuiteError("Questo gioco è già aperto. Chiudilo prima di avviarlo di nuovo.") from exc
            source = self.library()["games"].get(game_id)
            if source and not Path(source).is_file():
                self.dialog("Il file associato è stato spostato. Seleziona nuovamente il gioco.")
                source = None
            if source is None:
                source = self.associate(game_id)
                if source is None:
                    return
            source = validate_game_path(game_id, source)
            core = self.tool("CORE_" + GAMES[game_id]["core"])
            if not Path(core).is_file():
                raise SuiteError(f"Core non trovato: {core}\nRicostruisci la suite con nixup apply.")
            logfile = self.state / (game_id + ".log")
            with logfile.open("w", encoding="utf-8") as output:
                result = subprocess.run(
                    [self.tool("RETROARCH"), "--config", str(self.game_config(game_id)),
                     "-L", core, str(source)],
                    stdout=output, stderr=subprocess.STDOUT, check=False,
                )
            if result.returncode:
                raise SuiteError(f"Il gioco non è partito o si è chiuso con un errore.\nDettagli: {logfile}")

    def help(self):
        self.dialog(
            "Scegli un gioco: al primo avvio ti viene chiesto il suo file.\n\n"
            "Zero Mission: .gba\nSuper Metroid: .sfc / .smc\n"
            "Symphony of the Night: .chd oppure .cue con tutti i suoi BIN.\n\n"
            "Tasti iniziali: F1 menu, F2 salva stato, F4 carica stato, Esc esci.\n"
            "I controller riconosciuti da RetroArch si configurano automaticamente.\n\n"
            "Puoi importare un BIOS PlayStation originale dal menu. Il core include "
            "anche OpenBIOS per l'avvio senza BIOS esterno.\n\n"
            f"Salvataggi e BIOS: {self.data}\nImpostazioni: {self.config}\n"
            "Le ROM restano dove le hai scelte. Evita di rinominarle dopo aver iniziato: "
            "i nomi dei salvataggi dipendono dal nome del file."
        )

    def run_menu(self):
        game_ids = list(GAMES)
        while True:
            library = self.library()["games"]
            entries = []
            for game_id, game in GAMES.items():
                source = library.get(game_id)
                status = game["platform"] if source and Path(source).is_file() else "scegli il file"
                entries.append(game["title"] + "  ·  " + status)
            entries += ["Associa o cambia un gioco", "Importa BIOS PlayStation (opzionale)",
                        "Apri salvataggi e BIOS", "Guida e comandi"]
            chosen = self.menu("Retro Suite", entries, "Tre classici · Invio per giocare · Esc per chiudere")
            if chosen is None:
                return
            try:
                if chosen < len(game_ids):
                    self.launch(game_ids[chosen])
                    return
                if chosen == 3:
                    game = self.menu("Associa gioco", [item["title"] for item in GAMES.values()])
                    if game is not None:
                        self.associate(game_ids[game])
                elif chosen == 4:
                    self.import_bios()
                elif chosen == 5:
                    subprocess.run([self.tool("XDG_OPEN"), str(self.data)], check=True)
                elif chosen == 6:
                    self.help()
            except SuiteError as exc:
                self.dialog(str(exc), error=True)


def main():
    parser = argparse.ArgumentParser(prog="retro-suite", description="Retro Suite: tre classici dal tuo desktop")
    parser.add_argument("--game", choices=GAMES, help="avvia direttamente un gioco")
    args = parser.parse_args()
    suite = None
    try:
        suite = Suite()
        if args.game:
            suite.launch(args.game)
        else:
            suite.run_menu()
    except (SuiteError, OSError, UnicodeError, subprocess.SubprocessError) as exc:
        if suite is not None:
            try:
                suite.dialog(str(exc), error=True)
            except (SuiteError, OSError):
                print(str(exc), file=sys.stderr)
        else:
            print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

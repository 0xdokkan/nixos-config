"""Exercise launcher persistence and invocation without ROMs or desktop apps."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parents[1] / "home/retro-suite.py"
spec = importlib.util.spec_from_file_location("retro_suite", source)
suite_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(suite_module)


class RetroSuiteTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="retro-suite-test-")
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name) / "home with spaces"
        self.home.mkdir()
        self.env = {
            "HOME": str(self.home),
            "RETRO_SUITE_RETROARCH": "/test tools/retroarch",
            "RETRO_SUITE_ZENITY": "/test tools/zenity",
            "RETRO_SUITE_ROFI": "/test tools/rofi",
        }
        for core in ("MGBA", "PSX", "SNES"):
            path = self.home / (core + "_libretro.so")
            path.touch()
            self.env["RETRO_SUITE_CORE_" + core] = str(path)
        self.environ = patch.dict(os.environ, self.env, clear=True)
        self.environ.start()
        self.addCleanup(self.environ.stop)
        self.suite = suite_module.Suite()

    def file(self, name, content=b"synthetic test data"):
        path = self.home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def associate(self, game, path):
        with patch.object(self.suite, "choose_file", return_value=path):
            self.suite.associate(game)

    def test_cancel_keeps_library_and_does_not_start_emulator(self):
        original = self.file("original.gba")
        self.associate("zero-mission", original)
        before = self.suite.library_path.read_bytes()
        with patch.object(suite_module.subprocess, "run", return_value=
                          subprocess.CompletedProcess([], 1, "", "")) as runner:
            self.assertIsNone(self.suite.associate("zero-mission"))
            self.assertEqual(runner.call_args.args[0][0], self.env["RETRO_SUITE_ZENITY"])
        self.assertEqual(self.suite.library_path.read_bytes(), before)
        with patch.object(self.suite, "choose_file", return_value=None), \
                patch.object(suite_module.subprocess, "run") as runner:
            self.suite.launch("super-metroid")
            runner.assert_not_called()
        self.assertEqual(self.suite.library_path.read_bytes(), before)

    def test_launch_keeps_special_filename_as_one_argument_without_bios(self):
        game = self.file("-Étrange 'game' $(touch SHOULD_NOT_EXIST).chd")
        self.associate("symphony", game)
        self.assertEqual(list((self.suite.data / "bios").iterdir()), [])
        with patch.object(suite_module.subprocess, "run", return_value=
                          subprocess.CompletedProcess([], 0)) as runner:
            self.suite.launch("symphony")
        command = runner.call_args.args[0]
        self.assertEqual(command[-1], str(game))
        self.assertEqual(command[0], self.env["RETRO_SUITE_RETROARCH"])
        self.assertEqual(command[command.index("-L") + 1], self.env["RETRO_SUITE_CORE_PSX"])
        self.assertNotIn("shell", runner.call_args.kwargs)
        self.assertEqual(game.read_bytes(), b"synthetic test data")
        self.assertFalse((self.home / "SHOULD_NOT_EXIST").exists())

    def test_cue_tracks_with_spaces_cp1252_and_uppercase_extension(self):
        self.file("disc/Track 01.bin")
        self.file("disc/Entrée 02.bin")
        cue = self.file("disc/Game.CUE", (
            'FILE "Track 01.bin" BINARY\r\n TRACK 01 MODE2/2352\r\n'
            'FILE "Entrée 02.bin" BINARY\r\n TRACK 02 AUDIO\r\n'
        ).encode("cp1252"))
        self.assertEqual(suite_module.validate_game_path("symphony", cue), cue)
        (cue.parent / "Entrée 02.bin").unlink()
        with self.assertRaisesRegex(suite_module.SuiteError, "Entrée 02.bin"):
            suite_module.validate_game_path("symphony", cue)

    def test_missing_cue_track_never_replaces_existing_association(self):
        previous = self.file("previous.chd")
        self.associate("symphony", previous)
        before = self.suite.library_path.read_bytes()
        cue = self.file("incomplete.cue", b'FILE "missing.bin" BINARY\n')
        with patch.object(self.suite, "choose_file", return_value=cue):
            with self.assertRaises(suite_module.SuiteError):
                self.suite.associate("symphony")
        self.assertEqual(self.suite.library_path.read_bytes(), before)

    def test_malformed_cue_encoding_is_reported_without_changing_file(self):
        cue = self.file("bad.cue", b'FILE "track\x81.bin" BINARY\n')
        before = cue.read_bytes()
        with self.assertRaisesRegex(suite_module.SuiteError, "codifica"):
            suite_module.validate_game_path("symphony", cue)
        self.assertEqual(cue.read_bytes(), before)

    def test_corrupt_library_is_retained_when_associating(self):
        candidate = self.file("candidate.gba")
        for broken in (b"{bad json", b"\xff", b'{"version":1,"games":{"zero-mission":"relative.gba"}}'):
            with self.subTest(broken=broken):
                self.suite.library_path.write_bytes(broken)
                with patch.object(self.suite, "choose_file", return_value=candidate):
                    with self.assertRaises(suite_module.SuiteError):
                        self.suite.associate("zero-mission")
                self.assertEqual(self.suite.library_path.read_bytes(), broken)

    def test_unknown_bios_does_not_write_or_replace_files(self):
        existing = self.suite.data / "bios/scph5501.bin"
        existing.write_bytes(b"existing BIOS sentinel")
        for content in (b"too small", b"x" * 524288):
            with self.subTest(size=len(content)):
                candidate = self.file("unknown.bin", content)
                with patch.object(self.suite, "choose_file", return_value=candidate):
                    with self.assertRaises(suite_module.SuiteError):
                        self.suite.import_bios()
                self.assertEqual(existing.read_bytes(), b"existing BIOS sentinel")
                self.assertEqual(list(existing.parent.iterdir()), [existing])

    def test_recognized_bios_is_copied_under_canonical_name(self):
        content = b"synthetic BIOS fixture".ljust(524288, b"\0")
        candidate = self.file("my personal dump.rom", content)
        fake_bios = {hashlib.md5(content).hexdigest(): "scph5501.bin"}
        with patch.dict(suite_module.BIOS, fake_bios, clear=True), \
                patch.object(self.suite, "choose_file", return_value=candidate), \
                patch.object(self.suite, "dialog"):
            self.suite.import_bios()
            self.suite.import_bios()  # Reimport of identical data is harmless.
            destination = self.suite.data / "bios/scph5501.bin"
            self.assertEqual(destination.read_bytes(), content)
            self.assertEqual(candidate.read_bytes(), content)
            destination.write_bytes(b"different existing contents")
            with self.assertRaises(suite_module.SuiteError):
                self.suite.import_bios()
            self.assertEqual(destination.read_bytes(), b"different existing contents")

    def test_managed_paths_preserve_player_settings_and_remain_writable(self):
        config = self.suite.game_config("zero-mission")
        config.write_text('# Player settings\nvideo_fullscreen = "false"\n'
                          'input_save_state = "f6"\nsavefile_directory = "/wrong"\n'
                          'savefile_directory = "/also wrong"\n', encoding="utf-8")
        self.suite.game_config("zero-mission")
        updated = config.read_text(encoding="utf-8")
        self.assertIn('# Player settings\nvideo_fullscreen = "false"\n', updated)
        self.assertIn('input_save_state = "f6"', updated)
        self.assertNotIn("/wrong", updated)
        self.assertEqual(updated.count("savefile_directory ="), 1)
        self.assertIn(str(self.suite.data / "saves/zero-mission"), updated)
        self.assertTrue((self.suite.data / "saves/zero-mission").is_dir())

    def test_running_game_lock_rejects_a_second_launcher_then_releases(self):
        game = self.file("Super Metroid.sfc")
        self.associate("super-metroid", game)
        competing = suite_module.Suite()

        def while_running(*args, **kwargs):
            with self.assertRaisesRegex(suite_module.SuiteError, "già aperto"):
                competing.launch("super-metroid")
            return subprocess.CompletedProcess(args[0], 0)

        with patch.object(suite_module.subprocess, "run", side_effect=while_running) as runner:
            self.suite.launch("super-metroid")
            self.assertEqual(runner.call_count, 1)
        with patch.object(suite_module.subprocess, "run", return_value=
                          subprocess.CompletedProcess([], 0)) as runner:
            competing.launch("super-metroid")
            runner.assert_called_once()

    def test_different_games_do_not_share_writable_core_options(self):
        option_paths = []
        for game in suite_module.GAMES:
            config = self.suite.game_config(game).read_text()
            option_paths.append(next(line for line in config.splitlines()
                                     if line.startswith("core_options_path =")))
        self.assertEqual(len(set(option_paths)), len(suite_module.GAMES))

    def test_moved_game_can_be_reassociated_without_touching_saves(self):
        original = self.file("before.gba")
        self.associate("zero-mission", original)
        replacement = self.home / "after.gba"
        original.rename(replacement)
        self.suite.game_config("zero-mission")
        save = self.suite.data / "saves/zero-mission/before.srm"
        save.write_bytes(b"saved progress")
        with patch.object(self.suite, "choose_file", return_value=replacement), \
                patch.object(self.suite, "dialog"), \
                patch.object(suite_module.subprocess, "run", return_value=
                             subprocess.CompletedProcess([], 0)) as runner:
            self.suite.launch("zero-mission")
        self.assertEqual(runner.call_args.args[0][-1], str(replacement))
        self.assertEqual(save.read_bytes(), b"saved progress")
        self.assertEqual(json.loads(self.suite.library_path.read_text())["games"]["zero-mission"],
                         str(replacement))


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])

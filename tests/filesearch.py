"""Exercise file selection without a running rofi or opening user files."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


STUB = """import json, os, sys
from pathlib import Path
root = Path(os.environ['FILESEARCH_TEST_ROOT'])
name = Path(sys.argv[0]).name
if name == 'fd':
    assert sys.argv[1:] == ['--type', 'f', '--type', 'd', '--absolute-path', '--print0', '.', str(root / 'home')]
    sys.stdout.buffer.write(bytes.fromhex(os.environ['FILESEARCH_TEST_CANDIDATES']))
    sys.exit(int(os.environ.get('FILESEARCH_TEST_FD_STATUS', '0')))
elif name == 'rofi':
    assert sys.argv[1:] == ['-dmenu', '-i', '-no-custom', '-p', 'file'], sys.argv
    (root / 'choices').write_text(sys.stdin.read())
    print(os.environ.get('FILESEARCH_TEST_SELECTION', ''))
    sys.exit(int(os.environ.get('FILESEARCH_TEST_PICKER_STATUS', '0')))
elif name == 'xdg-open':
    (root / 'opened').write_text(json.dumps(sys.argv[1:]))
else:
    raise AssertionError(name)
"""


def main(script: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="filesearch-test-") as temporary:
        root = Path(temporary)
        task_home = root / "home"
        task_home.mkdir()
        bindir = root / "bin"
        bindir.mkdir()
        for name in ("fd", "rofi", "xdg-open"):
            stub = bindir / name
            stub.write_text(f"#!{sys.executable}\n{STUB}")
            stub.chmod(0o755)

        names = ["ordinary.txt", "spazi e 'virgolette'.txt", "$(touch SHOULD_NOT_EXIST).txt",
                 "-option.txt", "a\tb.txt", "new\nline.txt", "return\rname.txt"]
        candidates = [task_home / name for name in names]
        for candidate in candidates:
            candidate.touch()
        directory = task_home / "directory with spaces"
        directory.mkdir()
        candidates.append(directory)
        not_listed = task_home / "not listed.txt"
        not_listed.touch()
        payload = b"\0".join(os.fsencode(path) for path in candidates) + b"\0"

        env = dict(os.environ, HOME=str(task_home), TMPDIR=str(root),
                   PATH=f"{bindir}:{os.environ['PATH']}", FILESEARCH_TEST_ROOT=str(root),
                   FILESEARCH_TEST_CANDIDATES=payload.hex())

        def run(selection: str, *, picker_status: int = 0, fd_status: int = 0,
                expected_status: int = 0, opened: bool = False) -> None:
            for output in ("opened", "choices"):
                (root / output).unlink(missing_ok=True)
            result = subprocess.run(
                ["bash", str(script)], cwd=root,
                env=dict(env, FILESEARCH_TEST_SELECTION=selection,
                         FILESEARCH_TEST_PICKER_STATUS=str(picker_status),
                         FILESEARCH_TEST_FD_STATUS=str(fd_status)),
                capture_output=True, text=True,
            )
            assert result.returncode == expected_status, result.stderr
            assert (root / "opened").exists() == opened, selection
            if opened:
                assert json.loads((root / "opened").read_text()) == [selection]
            assert not list(root.glob("filesearch.*")), "candidate list was not cleaned up"
            assert not (root / "SHOULD_NOT_EXIST").exists(), "filename was executed"

        for candidate in candidates:
            safe = "\n" not in str(candidate) and "\r" not in str(candidate)
            run(str(candidate), opened=safe)
        run("")
        run(str(not_listed))
        run(str(candidates[0]), picker_status=1)
        run(str(candidates[0]), picker_status=2, expected_status=2)
        run(str(candidates[0]), fd_status=2, expected_status=2)
        assert not (root / "choices").exists(), "picker started after failed enumeration"
        missing = task_home / "missing.txt"
        env["FILESEARCH_TEST_CANDIDATES"] = (os.fsencode(missing) + b"\0").hex()
        run(str(missing))
        print("filesearch: spaces, metacharacters, cancellation, unlisted/newline paths and failures passed")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())

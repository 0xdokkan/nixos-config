"""Isolated runtime tests for nixup; never execute Nix or activate a system."""

import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def stub(tool, args):
    """Implement only the external operations explicitly allowed in tests."""
    root = Path(os.environ["NIXUP_TEST_ROOT"])
    stage = tool
    if tool == "uname":
        if args not in (["-n"], ["--nodename"]):
            raise AssertionError(f"Unexpected uname invocation: {args}")
        print(os.environ.get("NIXUP_TEST_HOST", "armoredcoreVIP"))
        return 0
    if tool == "nix":
        # Accept global feature flags, without obscuring the recorded argv.
        command = list(args)
        while command and command[0] in (
            "--extra-experimental-features", "--experimental-features"
        ):
            command = command[2:]
        if command[:2] == ["flake", "update"]:
            stage = "update"
        elif command[:2] == ["flake", "metadata"]:
            stage = "metadata"
        elif command[:2] == ["flake", "check"]:
            stage = "check"
        elif command[:1] == ["build"]:
            stage = "build"
        else:
            raise AssertionError(f"Unexpected nix invocation: {args}")
    elif tool == "nvd":
        if len(args) != 3 or args[0] != "diff":
            raise AssertionError(f"Unexpected nvd invocation: {args}")
        stage = "diff"
    elif tool != "sudo":
        raise AssertionError(f"Unexpected tool: {tool}")

    with (root / "events.jsonl").open("a") as stream:
        stream.write(json.dumps({"stage": stage, "args": args, "cwd": os.getcwd()}) + "\n")

    if os.environ.get("NIXUP_TEST_FAIL") == stage:
        print(f"Simulated {stage} failure", file=sys.stderr)
        return 42
    if stage == "update":
        (root / "repository with spaces" / "flake.lock").write_text('{"updated": true}\n')
    elif stage == "metadata":
        # An actual immutable store directory, supplied by the Nix test.
        # The stub never writes to it or evaluates its contents.
        print(json.dumps({"path": os.environ["NIXUP_TEST_SNAPSHOT"]}))
    elif stage == "build":
        if "--out-link" not in args:
            raise AssertionError(f"Build must expose an explicit output link: {args}")
        link = Path(args[args.index("--out-link") + 1])
        link.symlink_to(root / "new system with spaces", target_is_directory=True)
    elif stage == "diff" and os.environ.get("NIXUP_TEST_EDIT_DURING_DIFF") == "1":
        (root / "repository with spaces" / "tracked-config.nix").write_text("{ editedAfterBuild = true; }\n")
    elif stage == "sudo":
        if not args or args[0] != os.environ["NIXUP_REBUILD"]:
            raise AssertionError(f"Unexpected privileged command: {args}")
    return 0


class Case:
    def __init__(self, script, snapshot, name):
        self.temp = tempfile.TemporaryDirectory(prefix=f"nixup {name} ")
        self.root = Path(self.temp.name)
        self.repo = self.root / "repository with spaces"
        self.repo.mkdir()
        self.snapshot = snapshot
        self.current = self.root / "current system with spaces"
        self.built = self.root / "new system with spaces"
        for system in (self.current, self.built):
            (system / "bin").mkdir(parents=True)
            switch = system / "bin" / "switch-to-configuration"
            switch.write_text("#!/bin/sh\nexit 99\n")
            switch.chmod(0o755)
            (system / "unchanged-marker").write_text("This system must not be mutated.\n")
        self.script = script
        self.env = os.environ.copy()
        # Avoid caller Git settings, hooks or identity affecting the fixture.
        for key in list(self.env):
            if key.startswith("GIT_") or key.startswith("NIXUP_"):
                del self.env[key]
        self.env.update({
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_TERMINAL_PROMPT": "0",
            "NIXUP_REPO": str(self.repo),
            "NIXUP_HOST": "armoredcoreVIP",
            "NIXUP_SYSTEM": str(self.current),
            "NIXUP_REBUILD": str(self.root / "never execute nixos-rebuild"),
            "NIXUP_TEST_ROOT": str(self.root),
            "NIXUP_TEST_SNAPSHOT": str(self.snapshot),
            "TMPDIR": str(self.root),
        })
        self.git("init", "-q")
        self.git("config", "user.name", "Nixup test")
        self.git("config", "user.email", "nixup@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        (self.repo / "flake.nix").write_text("{ outputs = _: {}; }\n")
        (self.repo / "flake.lock").write_text("{}\n")
        (self.repo / "tracked-config.nix").write_text("{}\n")
        self.git("add", "flake.nix", "flake.lock", "tracked-config.nix")
        self.git("commit", "-qm", "test fixture")
        self.head = self.git("rev-parse", "HEAD").stdout.strip()
        stub_dir = self.root / "stub commands"
        stub_dir.mkdir()
        test_script = str(Path(__file__).resolve())
        for name in ("nix", "nvd", "sudo", "uname"):
            executable = stub_dir / name
            executable.write_text(
                f"#!{sys.executable}\n"
                "import runpy, sys\n"
                f"sys.argv = [{test_script!r}, '--stub', {name!r}, *sys.argv[1:]]\n"
                f"runpy.run_path({test_script!r}, run_name='__main__')\n"
            )
            executable.chmod(0o755)
        self.env["PATH"] = str(stub_dir) + os.pathsep + self.env["PATH"]

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.run(
            ["git", "-C", str(self.repo), *args], env=self.env,
            text=True, capture_output=True, check=True,
        )

    def run(self, *args, response="yes\n", fail=None, overrides=None):
        env = self.env.copy()
        if fail:
            env["NIXUP_TEST_FAIL"] = fail
        if overrides:
            env.update(overrides)
        result = subprocess.run(
            ["bash", str(self.script), *args], input=response,
            env=env, cwd=self.root, text=True, capture_output=True, timeout=20,
        )
        # Neither the helper nor stub may silently commit or mutate a system.
        assert self.git("rev-parse", "HEAD").stdout.strip() == self.head
        for system in (self.current, self.built):
            assert (system / "unchanged-marker").read_text() == "This system must not be mutated.\n"
            assert (system / "bin" / "switch-to-configuration").read_text() == "#!/bin/sh\nexit 99\n"
        assert not list(self.root.glob("nixup.*")), "Temporary result link was not cleaned up"
        return result

    def events(self):
        file = self.root / "events.jsonl"
        return [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []

    def stages(self):
        return [event["stage"] for event in self.events()]

    def assert_success(self, result):
        assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)

    def assert_failure(self, result):
        assert result.returncode != 0, (result.stdout, result.stderr)

    def assert_snapshot(self):
        events = {event["stage"]: event for event in self.events()}
        snapshot = str(self.snapshot)
        metadata_args = events["metadata"]["args"]
        assert "--no-write-lock-file" in metadata_args
        assert "--no-update-lock-file" in metadata_args
        check_args = events["check"]["args"]
        assert snapshot in check_args, check_args
        assert "--no-write-lock-file" in check_args
        assert "--no-update-lock-file" in check_args
        build_args = events["build"]["args"]
        assert snapshot + "#nixosConfigurations.armoredcoreVIP.config.system.build.toplevel" in build_args
        assert "--no-write-lock-file" in build_args
        assert "--no-update-lock-file" in build_args
        assert events["diff"]["args"] == ["diff", str(self.current), str(self.built)]
        if "sudo" in events:
            assert events["sudo"]["args"] == [
                self.env["NIXUP_REBUILD"], "switch", "--store-path", str(self.built),
            ], events["sudo"]


def tests(script, snapshot):
    def fixture(name):
        return Case(script, snapshot, name)

    for mode in (None, "all", "ai", "apply"):
        with fixture(mode or "default") as case:
            result = case.run(*([mode] if mode else []))
            case.assert_success(result)
            expected = ["metadata", "check", "build", "diff", "sudo"]
            if mode != "apply":
                expected.insert(0, "update")
            assert case.stages() == expected, (case.stages(), result.stdout, result.stderr)
            if mode != "apply":
                args = case.events()[0]["args"]
                update_args = args[args.index("update") + 1:]
                assert update_args == (["llm-agents"] if mode == "ai" else []), args
            case.assert_snapshot()

    for response in ("no\n", "\n", "", "maybe\n"):
        with fixture("decline") as case:
            result = case.run("all", response=response)
            case.assert_success(result)
            assert case.stages() == ["update", "metadata", "check", "build", "diff"], (
                case.stages(), result.stdout, result.stderr
            )
            assert (case.repo / "flake.lock").read_text() == '{"updated": true}\n'
            case.assert_snapshot()

    for response in ("y\n", "s\n", "si\n", "sì\n", "YES\n"):
        with fixture("confirm") as case:
            case.assert_success(case.run("apply", response=response))
            assert case.stages()[-1] == "sudo"

    order = ["update", "metadata", "check", "build", "diff", "sudo"]
    for stage in order:
        with fixture("failure " + stage) as case:
            result = case.run("all", fail=stage)
            case.assert_failure(result)
            assert case.stages() == order[:order.index(stage) + 1], case.stages()
            if stage != "update":
                assert (case.repo / "flake.lock").read_text() == '{"updated": true}\n'

    for mode in ("all", "ai"):
        for staged in (False, True):
            with fixture("dirty " + mode) as case:
                (case.repo / "tracked-config.nix").write_text("{ changed = true; }\n")
                if staged:
                    case.git("add", "tracked-config.nix")
                case.assert_failure(case.run(mode))
                assert case.stages() == [], case.stages()
                assert (case.repo / "tracked-config.nix").read_text() == "{ changed = true; }\n"

    with fixture("apply dirty") as case:
        (case.repo / "flake.lock").write_text('{"updated": true}\n')
        (case.repo / "tracked-config.nix").write_text("{ changed = true; }\n")
        case.assert_success(case.run("apply"))
        assert "update" not in case.stages()
        case.assert_snapshot()

    with fixture("edited after build") as case:
        case.assert_success(case.run("all", overrides={"NIXUP_TEST_EDIT_DURING_DIFF": "1"}))
        case.assert_snapshot()
        assert (case.repo / "tracked-config.nix").read_text() == "{ editedAfterBuild = true; }\n"

    for mode in ("all", "ai", "apply"):
        with fixture("untracked " + mode) as case:
            (case.repo / "untracked config.nix").write_text("{ important = true; }\n")
            case.assert_failure(case.run(mode))
            assert case.stages() == [], case.stages()
            assert (case.repo / "untracked config.nix").exists()

    with fixture("wrong host") as case:
        case.assert_failure(case.run("all", overrides={"NIXUP_TEST_HOST": "another-machine"}))
        assert case.stages() == []

    with fixture("missing system") as case:
        case.assert_failure(case.run("all", overrides={"NIXUP_SYSTEM": str(case.root / "missing system")}))
        assert case.stages() == []

    with fixture("not repository root") as case:
        nested = case.repo / "nested"
        nested.mkdir()
        case.assert_failure(case.run("all", overrides={"NIXUP_REPO": str(nested)}))
        assert case.stages() == []

    with fixture("concurrent command") as case:
        with (case.repo / ".git" / "nixup.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            case.assert_failure(case.run("all"))
            assert case.stages() == []

    with fixture("invalid snapshot") as case:
        case.assert_failure(case.run("apply", overrides={"NIXUP_TEST_SNAPSHOT": str(case.repo)}))
        assert case.stages() == ["metadata"]

    with fixture("invalid mode") as case:
        case.assert_failure(case.run("not-a-mode"))
        assert case.stages() == []
        case.assert_failure(case.run("all", "unexpected"))
        assert case.stages() == []
        case.assert_success(case.run("--help"))
        assert case.stages() == []

    print("nixup runtime tests passed (isolated stubs, no real rebuild)")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--stub"]:
        sys.exit(stub(sys.argv[2], sys.argv[3:]))
    if len(sys.argv) != 3:
        raise SystemExit("Usage: nixup.py /path/to/nixup.sh /nix/store/SNAPSHOT")
    tests(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())

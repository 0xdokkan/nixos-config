"""codex-alpha-update.sh con GitHub (curl) e Nix finti: niente rete né store."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ASSET = "codex-package-x86_64-unknown-linux-musl.tar.gz"
API = "https://api.github.invalid/repos/openai/codex/releases"
FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


def stub(tool, args):
    """curl restituisce le release finte, nix un hash finto; tutto registrato."""
    root = Path(os.environ["CODEX_TEST_ROOT"])
    with (root / "events.jsonl").open("a") as stream:
        stream.write(json.dumps({"tool": tool, "args": args}) + "\n")
    if os.environ.get("CODEX_TEST_FAIL") == tool:
        print(f"Simulated {tool} failure", file=sys.stderr)
        return 22
    if tool == "curl":
        if args[-1] != API:
            raise AssertionError(f"Unexpected curl URL: {args}")
        sys.stdout.write((root / "releases.json").read_text())
    elif tool == "nix":
        if args[:5] != ["store", "prefetch-file", "--json", "--hash-type", "sha256"] or len(args) != 6:
            raise AssertionError(f"Unexpected nix invocation: {args}")
        print(json.dumps({"hash": FAKE_HASH, "storePath": "/nix/store/fake-codex-package"}))
    else:
        raise AssertionError(f"Unexpected tool: {tool}")
    return 0


def release(tag, published, *, assets=(ASSET,), draft=False, prerelease=True, state="uploaded"):
    return {
        "tag_name": tag,
        "draft": draft,
        "prerelease": prerelease,
        "published_at": published,
        "assets": [
            {
                "name": name,
                "state": state,
                "browser_download_url": f"https://github.invalid/openai/codex/releases/download/{tag}/{name}",
            }
            for name in assets
        ],
    }


def pin(version):
    return {
        "version": version,
        "url": f"https://github.invalid/openai/codex/releases/download/rust-v{version}/{ASSET}",
        "hash": "sha256-OLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDOLDO=",
    }


class Case:
    def __init__(self, script, releases, current="0.166.0"):
        self.temp = tempfile.TemporaryDirectory(prefix="codex alpha ")
        self.root = Path(self.temp.name)
        self.repo = self.root / "repository with spaces"
        (self.repo / "home").mkdir(parents=True)
        self.pin = self.repo / "home" / "codex-alpha.json"
        if current is not None:
            self.pin.write_text(json.dumps(pin(current), indent=2) + "\n")
        self.original = self.pin.read_bytes() if self.pin.exists() else None
        (self.root / "releases.json").write_text(json.dumps(releases))
        self.script = script
        stubs = self.root / "stub commands"
        stubs.mkdir()
        test_script = str(Path(__file__).resolve())
        for name in ("curl", "nix"):
            executable = stubs / name
            executable.write_text(
                f"#!{sys.executable}\n"
                "import runpy, sys\n"
                f"sys.argv = [{test_script!r}, '--stub', {name!r}, *sys.argv[1:]]\n"
                f"runpy.run_path({test_script!r}, run_name='__main__')\n"
            )
            executable.chmod(0o755)
        self.env = {
            key: value for key, value in os.environ.items() if not key.startswith("CODEX_")
        }
        self.env.update({
            "PATH": str(stubs) + os.pathsep + os.environ["PATH"],
            "CODEX_TEST_ROOT": str(self.root),
            "CODEX_ALPHA_API": API,
        })

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        self.temp.cleanup()

    def run(self, fail=None):
        env = self.env.copy()
        if fail:
            env["CODEX_TEST_FAIL"] = fail
        result = subprocess.run(
            ["bash", str(self.script)], env=env, cwd=self.repo,
            text=True, capture_output=True, timeout=20,
        )
        leftovers = [p.name for p in (self.repo / "home").iterdir() if p.name != "codex-alpha.json"]
        assert not leftovers, f"Temporary files left behind: {leftovers}"
        return result

    def tools(self):
        file = self.root / "events.jsonl"
        if not file.exists():
            return []
        return [json.loads(line)["tool"] for line in file.read_text().splitlines()]

    def assert_unchanged(self):
        assert self.pin.read_bytes() == self.original, self.pin.read_text()

    def pinned(self):
        return json.loads(self.pin.read_text())


def tests(script):
    # La più recente con il pacchetto caricato, anche se stabile; non
    # rusty-v8, non bozze, non alpha senza pacchetto o con upload a metà.
    noisy = [
        release("rust-v0.167.0-alpha.3", "2026-11-01T22:26:17Z"),
        release("rust-v0.168.0-alpha.1", "2026-11-03T10:00:00Z", assets=()),
        release("rusty-v8-v153.0.0", "2026-11-03T09:00:00Z"),
        release("rust-v0.168.0-alpha.0", "2026-11-03T08:00:00Z", draft=True),
        release("rust-v0.167.0-alpha.4", "2026-11-02T13:00:00Z", state="starter"),
        release("rust-v0.167.0", "2026-11-02T12:00:00Z", prerelease=False),
        release("rust-v0.166.0", "2026-10-29T19:47:53Z", prerelease=False),
    ]
    with Case(script, noisy) as case:
        result = case.run()
        assert result.returncode == 0, (result.stdout, result.stderr)
        assert case.pinned() == {
            "version": "0.167.0",
            "url": f"https://github.invalid/openai/codex/releases/download/rust-v0.167.0/{ASSET}",
            "hash": FAKE_HASH,
        }, case.pinned()
        assert case.tools() == ["curl", "nix"], case.tools()
        assert case.pin.stat().st_mode & 0o777 == 0o644, oct(case.pin.stat().st_mode)

    # Un'alpha più nuova della stabile vince.
    fresh = [
        release("rust-v0.166.0", "2026-10-29T19:47:53Z", prerelease=False),
        release("rust-v0.167.0-alpha.3", "2026-11-01T22:26:17Z"),
    ]
    with Case(script, fresh) as case:
        assert case.run().returncode == 0
        assert case.pinned()["version"] == "0.167.0-alpha.3", case.pinned()

    # Già aggiornato: nessun download e il file resta identico.
    with Case(script, fresh, current="0.167.0-alpha.3") as case:
        result = case.run()
        assert result.returncode == 0, (result.stdout, result.stderr)
        assert "già" in result.stdout, result.stdout
        assert case.tools() == ["curl"], case.tools()
        case.assert_unchanged()

    # Ogni errore lascia il pin com'era.
    for fail, tools in (("curl", ["curl"]), ("nix", ["curl", "nix"])):
        with Case(script, fresh) as case:
            assert case.run(fail=fail).returncode != 0
            assert case.tools() == tools, case.tools()
            case.assert_unchanged()

    with Case(script, [release("rust-v0.167.0-alpha.9", "2026-11-02T00:00:00Z", assets=())]) as case:
        assert case.run().returncode != 0
        assert case.tools() == ["curl"], case.tools()
        case.assert_unchanged()

    with Case(script, fresh, current=None) as case:
        assert case.run().returncode != 0
        assert case.tools() == [], case.tools()

    print("codex-alpha-update tests passed (no network, no store writes)")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--stub"]:
        sys.exit(stub(sys.argv[2], sys.argv[3:]))
    if len(sys.argv) != 2:
        raise SystemExit("Usage: codex-alpha.py /path/to/codex-alpha-update.sh")
    tests(Path(sys.argv[1]).resolve())

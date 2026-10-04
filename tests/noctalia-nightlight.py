"""Compile the pinned GammaService state/IPC methods with inert display stubs.

The methods below are extracted from the actual patched C++ source, not copied
into a Python model. No Wayland connection, display change or shell is started.
"""

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def extract(source: str, name: str) -> str:
    match = re.search(rf"^(?:void|bool) GammaService::{name}\([^)]*\)(?: const)?\s*\{{", source, re.M)
    assert match, f"GammaService::{name} changed; review the state test"
    depth = 1
    end = match.end()
    while depth:
        assert end < len(source), name
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[match.start():end]


PRELUDE = r"""
#include <cassert>
#include <functional>
#include <optional>
#include <string>
#include <unordered_map>

class IpcService {
public:
  std::unordered_map<std::string, std::function<std::string(const std::string&)>> handlers;
  void bind(const char* command, std::function<std::string(const std::string&)> handler) {
    assert(handlers.emplace(command, handler).second);
  }
  void call(const char* command) { assert(handlers.at(command)("") == "ok\n"); }
};

class GammaService {
public:
  struct Config { bool enabled = false; bool force = false; } m_config;
  std::optional<bool> m_enabledOverride;
  std::optional<bool> m_forceOverride;
  bool night = false;
  void apply() {} // No graphics or output IO in this unit test.
  void notifyStateFeedback() {}
  bool isNightPhase() const { return night; }
  void setEnabled(bool enabled);
  void toggleEnabled();
  void setForceEnabled(bool enabled);
  void toggleForceEnabled();
  void clearForceOverride();
  bool enabled() const;
  bool forceEnabled() const;
  bool effectiveConfiguredEnabled() const;
  bool effectiveEnabled() const;
  bool effectiveForce() const;
  bool active() const;
  void registerIpc(IpcService& ipc);
};
"""

MAIN = r"""
int main() {
  const std::optional<bool> overrides[] = {std::nullopt, false, true};
  int cases = 0;
  for (bool configuredEnabled : {false, true})
    for (bool configuredForce : {false, true})
      for (auto enabledOverride : overrides)
        for (auto forceOverride : overrides)
          for (bool night : {false, true}) {
            GammaService service;
            service.m_config = {configuredEnabled, configuredForce};
            service.m_enabledOverride = enabledOverride;
            service.m_forceOverride = forceOverride;
            service.night = night;
            IpcService ipc;
            service.registerIpc(ipc);
            for (int repeat = 0; repeat < 2; ++repeat) {
              ipc.call("nightlight-force-on");
              assert(service.forceEnabled() && service.effectiveEnabled() && service.active());
            }
            for (int repeat = 0; repeat < 2; ++repeat) {
              ipc.call("nightlight-force-off");
              assert(!service.forceEnabled() && !service.enabled());
              assert(!service.effectiveEnabled() && !service.active());
            }
            ipc.call("nightlight-force-on");
            assert(service.active());
            assert(service.m_config.enabled == configuredEnabled);
            assert(service.m_config.force == configuredForce);
            ++cases;
          }
  assert(cases == 72);

  // Normal widget left/right toggles remain usable with our force=false default.
  GammaService service;
  IpcService ipc;
  service.registerIpc(ipc);
  ipc.call("nightlight-force-on");
  service.toggleEnabled(); // Forced -> scheduled; daytime means no filter.
  assert(!service.forceEnabled() && service.enabled() && !service.active());
  service.toggleEnabled(); // Scheduled -> disabled.
  assert(!service.enabled() && !service.active());
  ipc.call("nightlight-force-on");
  service.toggleForceEnabled(); // Widget right-click leaves forced mode.
  assert(!service.forceEnabled() && !service.active());
}
"""


def main(root: Path) -> None:
    source = (root / "src/system/gamma_service.cpp").read_text()
    schema = (root / "src/cli/schema_msg.h").read_text()
    names = ("nightlightEnable", "nightlightDisable", "nightlightToggle",
             "nightlightForceToggle", "nightlightForceOn", "nightlightForceOff")
    declarations = []
    for name in names:
        match = re.search(rf'inline constexpr Command {name}\s*\{{\s*"([^"]+)"', schema)
        assert match, f"CLI schema missing {name}"
        assert f"msg::{name}," in schema, f"CLI command {name} is not registered"
        declarations.append(f'inline constexpr const char* {name} = "{match[1]}";')
    functions = [extract(source, name) for name in (
        "setEnabled", "toggleEnabled", "setForceEnabled", "toggleForceEnabled",
        "clearForceOverride", "enabled", "forceEnabled", "effectiveConfiguredEnabled",
        "effectiveEnabled", "effectiveForce", "active", "registerIpc",
    )]
    harness = PRELUDE + "\nnamespace noctalia::cli::msg {\n" + "\n".join(declarations) + "\n}\n"
    harness += "\n".join(functions) + MAIN
    with tempfile.TemporaryDirectory(prefix="noctalia-nightlight-test-") as temporary:
        fixture = Path(temporary)
        cpp = fixture / "nightlight.cpp"
        cpp.write_text(harness)
        executable = fixture / "nightlight-test"
        subprocess.run([os.environ.get("CXX", "c++"), "-std=c++17", "-Wall", "-Wextra", "-Werror",
                        str(cpp), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
    print("Noctalia night light: actual C++ IPC/state methods passed 72 initial states + GUI/idempotence checks")


if __name__ == "__main__":
    main(Path(sys.argv[1]))

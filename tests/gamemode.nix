{ pkgs }:

let
  script = ../dotfiles/niri/scripts/gamemode.sh;
  # Non usare mai il compositor o il notification bus della macchina host.
  niriStub = pkgs.writeShellScriptBin "niri" ''
    set -eu
    test "$#" -eq 5
    test "$1" = msg
    test "$2" = action
    test "$3" = load-config-file
    test "$4" = --path
    printf '%s\n' "$5" >> "$TEST_NIRI_CALLS"
    test "''${TEST_NIRI_FAIL:-0}" = 0 || exit 42
    if [ "''${TEST_NIRI_DELAY:-0}" = 1 ]; then
      sleep 0.1
    fi
  '';
  notifyStub = pkgs.writeShellScriptBin "notify-send" ''
    printf '%s\n' "$@" >> "$TEST_NOTIFICATIONS"
    test "''${TEST_NOTIFY_FAIL:-0}" = 0
  '';
in
pkgs.runCommand "niri-gamemode-checked" {
  nativeBuildInputs = [ pkgs.coreutils pkgs.util-linux pkgs.gnugrep niriStub notifyStub ];
} ''
  set -eu
  testRoot="$TMPDIR/gamemode tests"
  export XDG_CONFIG_HOME="$testRoot/config files"
  export XDG_RUNTIME_DIR="$testRoot/runtime"
  export XDG_CACHE_HOME="$testRoot/legacy cache"
  export NIRI_SOCKET="$XDG_RUNTIME_DIR/niri.session 1.sock"
  export TEST_NIRI_CALLS="$testRoot/niri calls"
  export TEST_NOTIFICATIONS="$testRoot/notifications"
  mkdir -p "$XDG_CONFIG_HOME/niri" "$XDG_RUNTIME_DIR" "$XDG_CACHE_HOME"
  touch "$TEST_NIRI_CALLS" "$TEST_NOTIFICATIONS"
  touch "$XDG_CONFIG_HOME/niri/config.kdl" "$XDG_CONFIG_HOME/niri/config-gaming.kdl"
  printf 'gaming\n' > "$XDG_CACHE_HOME/niri-gamemode.state"

  run_toggle() {
    ${pkgs.bashNonInteractive}/bin/sh ${script}
  }
  state_file() {
    local sessionId
    sessionId=$(printf '%s' "$NIRI_SOCKET" | sha256sum | cut -d ' ' -f 1)
    printf '%s/niri-gamemode/%s.state\n' "$XDG_RUNTIME_DIR" "$sessionId"
  }
  assert_state() {
    test "$(cat "$(state_file)")" = "$1"
  }
  assert_target() {
    test "$(tail -n 1 "$TEST_NIRI_CALLS")" = "$XDG_CONFIG_HOME/niri/$1"
  }

  # Il primo toggle è ON anche se la vecchia cache dice gaming; tutti i
  # percorsi contengono spazi per verificare che gli argomenti restino interi.
  run_toggle
  assert_state gaming
  assert_target config-gaming.kdl
  test "$(cat "$XDG_CACHE_HOME/niri-gamemode.state")" = gaming
  grep -q '^ON ' "$TEST_NOTIFICATIONS"
  run_toggle
  assert_state normal
  assert_target config.kdl
  grep -q '^OFF ' "$TEST_NOTIFICATIONS"

  # Nuova istanza niri nello stesso runtime: deve cominciare da normal,
  # senza sovrascrivere lo stato della prima istanza ancora in gaming.
  run_toggle
  assert_state gaming
  firstSocket="$NIRI_SOCKET"
  firstState=$(state_file)
  export NIRI_SOCKET="$XDG_RUNTIME_DIR/niri.session 2.sock"
  run_toggle
  assert_state gaming
  assert_target config-gaming.kdl
  test "$(cat "$firstState")" = gaming
  run_toggle
  assert_state normal
  export NIRI_SOCKET="$firstSocket"
  run_toggle
  assert_state normal
  assert_target config.kdl

  # Un errore IPC mantiene normal oppure gaming: il toggle successivo deve
  # riprovare lo stesso cambio, non fingere che quello fallito sia riuscito.
  export TEST_NIRI_FAIL=1
  if run_toggle > "$testRoot/error" 2>&1; then
    echo 'Un errore niri è stato ignorato' >&2
    exit 1
  fi
  assert_state normal
  grep -q 'stato precedente conservato' "$testRoot/error"
  unset TEST_NIRI_FAIL
  run_toggle
  assert_state gaming
  export TEST_NIRI_FAIL=1
  if run_toggle > "$testRoot/error" 2>&1; then
    exit 1
  fi
  assert_state gaming
  unset TEST_NIRI_FAIL
  run_toggle
  assert_state normal

  # Il cambio rimane riuscito anche se il servizio notifiche è assente.
  export TEST_NOTIFY_FAIL=1
  run_toggle
  assert_state gaming
  unset TEST_NOTIFY_FAIL

  # Ambiente non disponibile: errore esplicito, nessun tentativo IPC.
  callsBefore=$(wc -l < "$TEST_NIRI_CALLS")
  if (unset NIRI_SOCKET; run_toggle) > "$testRoot/error" 2>&1; then
    exit 1
  fi
  grep -q 'servono XDG_RUNTIME_DIR e NIRI_SOCKET' "$testRoot/error"
  if (unset XDG_RUNTIME_DIR; run_toggle) > "$testRoot/error" 2>&1; then
    exit 1
  fi
  grep -q 'servono XDG_RUNTIME_DIR e NIRI_SOCKET' "$testRoot/error"
  if (export XDG_RUNTIME_DIR="$testRoot/absent"; run_toggle) > "$testRoot/error" 2>&1; then
    exit 1
  fi
  grep -q 'non è una directory scrivibile' "$testRoot/error"
  test "$(wc -l < "$TEST_NIRI_CALLS")" -eq "$callsBefore"

  # Uno stato inatteso non autorizza a invertire alla cieca la modalità.
  printf 'broken\n' > "$(state_file)"
  if run_toggle > "$testRoot/error" 2>&1; then
    exit 1
  fi
  grep -q 'stato non valido' "$testRoot/error"
  test "$(wc -l < "$TEST_NIRI_CALLS")" -eq "$callsBefore"

  # Due toggle concorrenti vengono serializzati e tornano in normal.
  export NIRI_SOCKET="$XDG_RUNTIME_DIR/niri.concurrent.sock"
  export TEST_NIRI_DELAY=1
  run_toggle &
  firstPid=$!
  run_toggle &
  secondPid=$!
  wait "$firstPid"
  wait "$secondPid"
  assert_state normal
  assert_target config.kdl
  test "$(wc -l < "$TEST_NIRI_CALLS")" -eq "$((callsBefore + 2))"

  echo 'gamemode: on/off, sessioni, cache, errori e concorrenza verificati'
  touch "$out"
''

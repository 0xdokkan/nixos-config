{ pkgs }:

let
  script = ../dotfiles/mango/scripts/gamemode.sh;
  # Non usare mai il compositor o il notification bus della macchina host.
  mmsgStub = pkgs.writeShellScriptBin "mmsg" ''
    set -eu
    test "$#" -eq 2
    test "$1" = dispatch
    case $2 in
      load_config_file,*) ;;
      *) exit 3 ;;
    esac
    printf '%s\n' "''${2#load_config_file,}" >> "$TEST_MMSG_CALLS"
    if [ "''${TEST_MMSG_DELAY:-0}" = 1 ]; then
      sleep 0.1
    fi
    case ''${TEST_MMSG_FAIL:-0} in
      0) echo '{"success":true}' ;;
      exit) exit 42 ;;
      *) echo '{"error":"unknown function"}' ;;
    esac
  '';
  notifyStub = pkgs.writeShellScriptBin "notify-send" ''
    printf '%s\n' "$@" >> "$TEST_NOTIFICATIONS"
    test "''${TEST_NOTIFY_FAIL:-0}" = 0
  '';
in
pkgs.runCommand "mango-gamemode-checked" {
  nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.util-linux pkgs.gnugrep mmsgStub notifyStub ];
} ''
  set -eu
  testRoot="$TMPDIR/gamemode tests"
  export XDG_CONFIG_HOME="$testRoot/config files"
  export XDG_RUNTIME_DIR="$testRoot/runtime"
  export MANGO_INSTANCE_SIGNATURE="$XDG_RUNTIME_DIR/mango-session 1.sock"
  export TEST_MMSG_CALLS="$testRoot/mmsg calls"
  export TEST_NOTIFICATIONS="$testRoot/notifications"
  mkdir -p "$XDG_CONFIG_HOME/mango" "$XDG_RUNTIME_DIR"
  touch "$TEST_MMSG_CALLS" "$TEST_NOTIFICATIONS"
  touch "$XDG_CONFIG_HOME/mango/config.conf" "$XDG_CONFIG_HOME/mango/gaming.conf"

  run_toggle() {
    bash ${script}
  }
  state_file() {
    local sessionId
    sessionId=$(printf '%s' "$MANGO_INSTANCE_SIGNATURE" | sha256sum | cut -d ' ' -f 1)
    printf '%s/mango-gamemode/%s.state\n' "$XDG_RUNTIME_DIR" "$sessionId"
  }
  assert_state() {
    test "$(cat "$(state_file)")" = "$1"
  }
  assert_target() {
    test "$(tail -n 1 "$TEST_MMSG_CALLS")" = "$XDG_CONFIG_HOME/mango/$1"
  }

  # ON poi OFF; tutti i percorsi contengono spazi per verificare che gli
  # argomenti restino interi.
  run_toggle
  assert_state gaming
  assert_target gaming.conf
  grep -q '^ON ' "$TEST_NOTIFICATIONS"
  run_toggle
  assert_state normal
  assert_target config.conf
  grep -q '^OFF ' "$TEST_NOTIFICATIONS"

  # Nuova istanza di mango nello stesso runtime: deve cominciare da normal,
  # senza sovrascrivere lo stato della prima istanza ancora in gaming.
  run_toggle
  assert_state gaming
  firstSocket="$MANGO_INSTANCE_SIGNATURE"
  firstState=$(state_file)
  export MANGO_INSTANCE_SIGNATURE="$XDG_RUNTIME_DIR/mango-session 2.sock"
  run_toggle
  assert_state gaming
  assert_target gaming.conf
  test "$(cat "$firstState")" = gaming
  run_toggle
  assert_state normal
  export MANGO_INSTANCE_SIGNATURE="$firstSocket"
  run_toggle
  assert_state normal
  assert_target config.conf

  # mmsg esce con errore, oppure mango risponde {"error":...} (mmsg esce
  # comunque con 0): lo stato resta, il toggle successivo riprova lo
  # stesso cambio invece di fingere che quello fallito sia riuscito.
  for failure in exit reply; do
    export TEST_MMSG_FAIL=$failure
    if run_toggle > "$testRoot/error" 2>&1; then
      echo "Un errore di mango ($failure) è stato ignorato" >&2
      exit 1
    fi
    assert_state normal
    grep -q 'stato precedente conservato' "$testRoot/error"
    unset TEST_MMSG_FAIL
  done
  run_toggle
  assert_state gaming
  export TEST_MMSG_FAIL=reply
  if run_toggle > "$testRoot/error" 2>&1; then
    exit 1
  fi
  assert_state gaming
  unset TEST_MMSG_FAIL
  run_toggle
  assert_state normal

  # Il cambio rimane riuscito anche se il servizio notifiche è assente.
  export TEST_NOTIFY_FAIL=1
  run_toggle
  assert_state gaming
  unset TEST_NOTIFY_FAIL
  run_toggle
  assert_state normal

  # Ambiente non disponibile: errore esplicito, nessun tentativo IPC.
  callsBefore=$(wc -l < "$TEST_MMSG_CALLS")
  if (unset MANGO_INSTANCE_SIGNATURE; run_toggle) > "$testRoot/error" 2>&1; then
    exit 1
  fi
  grep -q 'servono XDG_RUNTIME_DIR e MANGO_INSTANCE_SIGNATURE' "$testRoot/error"
  if (unset XDG_RUNTIME_DIR; run_toggle) > "$testRoot/error" 2>&1; then
    exit 1
  fi
  grep -q 'servono XDG_RUNTIME_DIR e MANGO_INSTANCE_SIGNATURE' "$testRoot/error"
  if (export XDG_RUNTIME_DIR="$testRoot/absent"; run_toggle) > "$testRoot/error" 2>&1; then
    exit 1
  fi
  grep -q 'non è una directory scrivibile' "$testRoot/error"

  # Senza gaming.conf mango ripartirebbe dai suoi default (nessun bind):
  # meglio non mandargli niente. Idem con una virgola nel percorso, che
  # mango userebbe per dividere gli argomenti.
  mv "$XDG_CONFIG_HOME/mango/gaming.conf" "$testRoot/gaming.conf"
  if run_toggle > "$testRoot/error" 2>&1; then
    exit 1
  fi
  grep -q 'config non utilizzabile' "$testRoot/error"
  assert_state normal
  mv "$testRoot/gaming.conf" "$XDG_CONFIG_HOME/mango/gaming.conf"
  if (export XDG_CONFIG_HOME="$testRoot/a,b"; mkdir -p "$XDG_CONFIG_HOME/mango"
      touch "$XDG_CONFIG_HOME/mango/gaming.conf"; run_toggle) > "$testRoot/error" 2>&1; then
    exit 1
  fi
  grep -q 'config non utilizzabile' "$testRoot/error"
  test "$(wc -l < "$TEST_MMSG_CALLS")" -eq "$callsBefore"

  # Uno stato inatteso non autorizza a invertire alla cieca la modalità.
  printf 'broken\n' > "$(state_file)"
  if run_toggle > "$testRoot/error" 2>&1; then
    exit 1
  fi
  grep -q 'stato non valido' "$testRoot/error"
  test "$(wc -l < "$TEST_MMSG_CALLS")" -eq "$callsBefore"

  # Due toggle concorrenti vengono serializzati e tornano in normal.
  export MANGO_INSTANCE_SIGNATURE="$XDG_RUNTIME_DIR/mango.concurrent.sock"
  export TEST_MMSG_DELAY=1
  run_toggle &
  firstPid=$!
  run_toggle &
  secondPid=$!
  wait "$firstPid"
  wait "$secondPid"
  assert_state normal
  assert_target config.conf
  test "$(wc -l < "$TEST_MMSG_CALLS")" -eq "$((callsBefore + 2))"

  echo 'gamemode: on/off, sessioni, errori di mango, config mancante e concorrenza verificati'
  touch "$out"
''

{ pkgs, noctaliaSource }:

pkgs.runCommand "noctalia-idle-checked" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  # Tutti i processi e le letture D-Bus sono simulati: nessun lock/suspend.
  python ${./noctalia-idle.py} ${../home/noctalia-idle.py} ${noctaliaSource}
  touch "$out"
''

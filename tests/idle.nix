{ pkgs }:

pkgs.runCommand "idle-checked" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  # Tutti i processi e le letture D-Bus sono simulati: nessun lock/suspend.
  # Il sorgente di hyprlock serve al controllo sulla riga di conferma.
  python ${./idle.py} ${../home/idle.py} ${pkgs.hyprlock.src}
  touch "$out"
''

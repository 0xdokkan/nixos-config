{ pkgs, noctaliaPackage, ... }:

let
  idle = pkgs.writeShellApplication {
    name = "noctalia-idle";
    runtimeInputs = [ pkgs.python3 pkgs.swayidle pkgs.systemd noctaliaPackage ];
    text = ''
      exec ${pkgs.python3}/bin/python ${./noctalia-idle.py} "$@"
    '';
  };
in
{
  # Noctalia 5.2.1 ha un solo profilo idle. Un unico swayidle applica i
  # timeout originali AC/batteria, mentre Noctalia resta l'unico locker.
  # Non aggiungere before-sleep: Noctalia gestisce già PrepareForSleep e
  # trattiene il delay inhibitor finché il compositor conferma il lock.
  programs.noctalia.settings = {
    idle.behavior = {
      lock.enabled = false;
      screen-off.enabled = false;
      lock-and-suspend.enabled = false;
      suspend.enabled = false;
    };

    # Nessun fallback a pm-suspend/sysfs se un lavoro CLI vieta lo sleep.
    # Il controllo finale chiude anche la corsa tra verifica e richiesta.
    shell.session.power.suspend =
      "${pkgs.systemd}/bin/systemctl --check-inhibitors=yes --no-ask-password suspend";
  };

  systemd.user.services.noctalia-idle = {
    Unit = {
      Description = "Noctalia idle profiles (AC / battery)";
      After = [ "graphical-session.target" "noctalia.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${idle}/bin/noctalia-idle";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 10;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}

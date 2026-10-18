{ config, lib, pkgs, ... }:

let
  p = import ./palette.nix;
  rgb = name: "rgb(${p.${name}})";
  font = "Monaspace Argon";

  # hyprlock scrive il log in un file: idle.py ci cerca la conferma del
  # compositor ("onLockLocked called") prima di spegnere lo schermo o
  # lasciar dormire il sistema. Un file e non una pipe: se chi legge se ne
  # va, hyprlock non deve morire di SIGPIPE con lo schermo bloccato.
  hyprlockLogged = pkgs.writeShellScript "hyprlock-logged" ''
    exec ${lib.getExe config.programs.hyprlock.package} > "$XDG_RUNTIME_DIR/hyprlock.log" 2>&1
  '';

  idle = pkgs.writeShellApplication {
    name = "idle";
    runtimeInputs = [ pkgs.python3 pkgs.swayidle pkgs.systemd pkgs.wlopm ];
    text = ''
      exec ${pkgs.python3}/bin/python ${./idle.py} "$@"
    '';
  };
in
{
  # ══ hyprlock: lo schermo di blocco (Mod+L, idle, prima dello sleep) ══
  # La password passa dallo stack PAM "hyprlock" (hosts/common.nix).
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        ignore_empty_input = true;
      };
      # Lo schermo com'era, sfocato e scurito.
      background = [{
        monitor = "";
        path = "screenshot";
        blur_passes = 3;
        blur_size = 7;
        brightness = 0.6;
        color = rgb "bgDarker";
      }];
      label = [
        {
          monitor = "";
          text = "$TIME";
          font_family = font;
          font_size = 72;
          color = rgb "fg";
          position = "0, 140";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = ''cmd[update:60000] date +"%A %d %B"'';
          font_family = font;
          font_size = 16;
          color = rgb "fgDark";
          position = "0, 60";
          halign = "center";
          valign = "center";
        }
      ];
      input-field = [{
        monitor = "";
        size = "300, 48";
        position = "0, -40";
        halign = "center";
        valign = "center";
        rounding = 10;
        outline_thickness = 2;
        outer_color = rgb "blue";
        inner_color = rgb "bg";
        font_color = rgb "fg";
        font_family = font;
        check_color = rgb "yellow";
        fail_color = rgb "red";
        capslock_color = rgb "orange";
        fade_on_empty = false;
        placeholder_text = "<i>password</i>";
        fail_text = "<i>$FAIL ($ATTEMPTS)</i>";
      }];
    };
  };

  # hyprlock gira come servizio a sé, non come figlio dell'idle: riavviare
  # o aggiornare l'idle non può uccidere uno schermo bloccato. Lo avvia
  # idle.py (Mod+L passa da `loginctl lock-session` → swayidle → idle.py).
  systemd.user.services.hyprlock = {
    Unit = {
      Description = "hyprlock, schermo bloccato";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      # Un rebuild mentre è bloccato non deve sbloccare.
      X-RestartIfChanged = false;
      StartLimitBurst = 5;
      StartLimitIntervalSec = 30;
    };
    Service = {
      ExecStart = "${hyprlockLogged}";
      # Se hyprlock crasha, uno nuovo riprende il lock (lo schermo resta
      # bloccato nel frattempo: è il protocollo ext-session-lock).
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  # Tempi diversi a corrente e a batteria (idle.py): blocco, schermo spento
  # e, solo a batteria, sospensione. Un unico swayidle, riarmato quando
  # cambia l'alimentazione. Rispetta gli inhibitor (video, lavori CLI).
  systemd.user.services.idle = {
    Unit = {
      Description = "Idle: lock, schermo spento e sospensione (AC / batteria)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${idle}/bin/idle";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 10;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}

{ lib, osConfig, pkgs, ... }:

let
  laptop = osConfig.networking.hostName == "armoredcoreVIP";
in
{
  # ══ I servizi del desktop: partono tutti con graphical-session.target ══
  # (lo avvia mango-session-start da exec_once, vedi home/mango.nix)

  # Finestra della password per le azioni da amministratore (polkit).
  services.polkit-gnome.enable = true;

  # Cronologia appunti (Mod+V): cliphist la registra, wl-clip-persist
  # tiene vivo l'ultimo copiato anche quando l'app che l'ha copiato si chiude.
  services.cliphist = {
    enable = true;
    allowImages = true;
    extraOptions = [ "-max-items" "500" ];
  };
  services.wl-clip-persist = {
    enable = true;
    clipboardType = "regular";
  };

  # Sfondo con transizioni (wallpaper.sh: Mod+Alt+←/→, Mod+Shift+W).
  # Al login lo rimette il servizio wallpaper (home/mango.nix).
  services.awww.enable = true;

  # Dischi removibili: notifica e voce per montarli, niente automount.
  services.udiskie = {
    enable = true;
    automount = false;
    notify = true;
    tray = "never";
  };

  # Luce notturna: Alt+F8 / Alt+F9 e il pulsante 󰖔 nel centro di controllo
  # (nightlight.sh) cambiano la temperatura via D-Bus.
  systemd.user.services.wl-gammarelay-rs = {
    Unit = {
      Description = "wl-gammarelay-rs: temperatura dello schermo via D-Bus";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "dbus";
      BusName = "rs.wl-gammarelay";
      ExecStart = "${lib.getExe pkgs.wl-gammarelay-rs} run";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Batteria bassa: avviso al 10%, critico al 5% (solo il portatile).
  services.batsignal = lib.mkIf laptop {
    enable = true;
    extraArgs = [ "-w" "10" "-c" "5" "-d" "0" ];
  };
}

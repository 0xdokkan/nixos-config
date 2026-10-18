{ config, lib, osConfig, pkgs, ... }:

let
  # ══ mango: config.conf & co. validati a BUILD-TIME ═══════════════════
  # (la derivazione è in mango-configs.nix: la usa anche `checks` nel flake)
  # osConfig = la config NixOS dell'host: da lì arriva il layout tastiera.
  # Sul portatile mango aggiunge "us" come secondo layout (Mod+K alterna);
  # SDDM e la console restano sul solo layout dichiarato dall'host.
  mangoConfigs = import ./mango-configs.nix {
    inherit pkgs;
    layout = osConfig.services.xserver.xkb.layout
      + lib.optionalString (osConfig.networking.hostName == "armoredcoreVIP") ",us";
    cursor = { inherit (config.home.pointerCursor) name size; };
  };

  # Gli script dei bind (dotfiles/mango/scripts), nel PATH per nome.
  scripts = import ./mango-scripts.nix {
    inherit pkgs;
    rofi = config.programs.rofi.finalPackage;
  };

  # exec_once della config: porta l'ambiente di mango (WAYLAND_DISPLAY,
  # DISPLAY, MANGO_INSTANCE_SIGNATURE e quello del login) a systemd e
  # dbus, POI avvia il target. Nell'ordine inverso i servizi partirebbero
  # senza sapere dov'è il display. Lo stop è nel wrapper mango-session
  # (hosts/common.nix).
  sessionStart = pkgs.writeShellApplication {
    name = "mango-session-start";
    runtimeInputs = [ pkgs.dbus pkgs.systemd ];
    text = ''
      dbus-update-activation-environment --systemd --all
      systemctl --user start mango-session.target
    '';
  };
in
{
  # Tutta la cartella: i file si includono a vicenda con path relativi.
  xdg.configFile."mango".source = mangoConfigs;

  home.packages = [ sessionStart ] ++ lib.attrValues scripts;

  # Sfondo al login: l'ultimo scelto con wallpaper.sh o, la prima volta,
  # quello di serie (dotfiles/sddm/bg.png). awww-daemon da solo ricorda
  # l'ultima immagine, ma solo se la sua cache c'è.
  systemd.user.services.wallpaper = {
    Unit = {
      Description = "Sfondo del desktop (wallpaper.sh restore)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "awww.service" ];
      Wants = [ "awww.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe scripts."wallpaper.sh"} restore";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Il target della sessione: tira su graphical-session.target, a cui sono
  # legati tutti i servizi del desktop (waybar, swaync, swayidle...).
  # Quando mango esce il wrapper lo ferma e graphical-session.target, non
  # più richiesto, si ferma con lui. Stesso schema del modulo Hyprland di HM.
  systemd.user.targets.mango-session = {
    Unit = {
      Description = "Sessione mango";
      Documentation = [ "man:systemd.special(7)" ];
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session-pre.target" ];
      After = [ "graphical-session-pre.target" ];
    };
  };
}

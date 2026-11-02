# ╔════════════════════════════════════════════════════════════════════╗
# ║  armoredcoreVIP — ThinkPad T470s: Intel Kaby Lake, HD 620, batteria   ║
# ║  Tutto il resto (desktop, audio, app, utente...) è in ../common.nix║
# ╚════════════════════════════════════════════════════════════════════╝
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../common.nix
  ];

  networking.hostName = "armoredcoreVIP";

  # ══ Tastiera italiana ═══════════════════════════════════════════════
  # Unica fonte di verità per il layout: la leggono SDDM, la console
  # (console.useXkbConfig in common.nix) e mango (home/mango.nix genera
  # host.conf da qui). Solo in mango si aggiunge "us" come secondo
  # layout: Mod+K alterna it/us.
  services.xserver.xkb.layout = "it";

  # ══ CPU ═════════════════════════════════════════════════════════════
  hardware.cpu.intel.updateMicrocode = true;   # Kaby Lake, i5/i7-7xxxU

  # ══ Grafica: Intel HD 620 integrata (niente nvidia qui!) ════════════
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver   # VAAPI (decodifica video hw) per Gen9.5/Kaby Lake
  ];
  # i915 già nell'initrd (early KMS): lo schermo prende subito la sua
  # risoluzione, senza il cambio di modalità prima di SDDM. È quello che
  # fa il profilo T470s di nixos-hardware; il resto di quel profilo
  # (microcode, VAAPI, fstrim) qui c'è già, quindi niente input in più.
  boot.initrd.kernelModules = [ "i915" ];
  # La config di mango è condivisa e senza env var nvidia: sul fisso
  # quelle variabili le mette hosts/armoredcoreVIF/configuration.nix a livello di
  # sessione, così la config resta una sola ✓

  # ══ Termiche e batteria ═════════════════════════════════════════════
  services.thermald.enable = true;
  # UPower è condiviso in common.nix: dice all'idle se sei a batteria (le
  # due batterie del T470s). power-profiles-daemon gestisce i profili
  # energetici; la percentuale nella barra la legge waybar.

  # Soglie di carica per la salute delle batterie: la carica riparte sotto
  # il 75% e si ferma all'80%, su BAT0 (interna) e BAT1 (removibile). A
  # novembre 2026 erano al 73% e al 68% della capacità originale, con le
  # soglie a 0/100. Le applica UPower (75/80 sono i suoi valori per
  # questo modello) e se le ricorda in /var/lib/upower: niente TLP, e
  # power-profiles-daemon resta com'è. Questo servizio le riaccende a
  # ogni boot, così restano dichiarate qui.
  # Carica piena una tantum (es. prima di un viaggio), fino al prossimo boot:
  #   for b in BAT0 BAT1; do busctl call org.freedesktop.UPower \
  #     /org/freedesktop/UPower/devices/battery_$b \
  #     org.freedesktop.UPower.Device EnableChargeThreshold b false; done
  systemd.services.battery-charge-threshold = {
    description = "Soglie di carica 75-80% via UPower";
    after = [ "upower.service" ];
    requires = [ "upower.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.systemd.package ];   # busctl
    # UPower può non aver ancora visto le batterie: qualche tentativo,
    # poi si arrende (e compare in `systemctl --failed`).
    startLimitBurst = 5;
    startLimitIntervalSec = 120;
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = 5;
    };
    script = ''
      for battery in /sys/class/power_supply/BAT*; do
        busctl call org.freedesktop.UPower \
          "/org/freedesktop/UPower/devices/battery_$(basename "$battery")" \
          org.freedesktop.UPower.Device EnableChargeThreshold b true
      done
    '';
  };
  # TLP resta un'alternativa, ma non convive con power-profiles-daemon
  # (common.nix) e scrive le stesse soglie: accenderlo vuol dire togliere
  # il servizio qui sopra.
  # services.tlp = {
  #   enable = true;
  #   settings = {
  #     START_CHARGE_THRESH_BAT0 = 75;
  #     STOP_CHARGE_THRESH_BAT0 = 80;
  #     START_CHARGE_THRESH_BAT1 = 75;
  #     STOP_CHARGE_THRESH_BAT1 = 80;
  #   };
  # };

  # ══ NON TOCCARE MAI ═════════════════════════════════════════════════
  # Marcatore di compatibilità per i dati stateful, NON una versione da
  # aggiornare: resta al valore della prima install per sempre.
  system.stateVersion = "26.05";
}

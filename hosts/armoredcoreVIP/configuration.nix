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
  # (console.useXkbConfig in common.nix) e niri (home/niri-configs.nix
  # genera host.kdl da qui). Con "it,us" Mod+K cicla tra i due.
  services.xserver.xkb.layout = "it";

  # ══ CPU ═════════════════════════════════════════════════════════════
  hardware.cpu.intel.updateMicrocode = true;   # Kaby Lake, i5/i7-7xxxU

  # ══ Grafica: Intel HD 620 integrata (niente nvidia qui!) ════════════
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver   # VAAPI (decodifica video hw) per Gen9.5/Kaby Lake
  ];
  # config.kdl è condiviso e già ripulito dalle env var nvidia: sul fisso
  # quelle variabili le mette hosts/armoredcoreVIF/configuration.nix a livello di
  # sessione, così il file niri resta uno solo ✓

  # ══ Termiche e batteria ═════════════════════════════════════════════
  services.thermald.enable = true;
  # UPower è condiviso in common.nix: espone anche le due batterie del T470s
  # a Noctalia. power-profiles-daemon gestisce invece i profili energetici.
  # TLP: opzionale ma sui ThinkPad dà il meglio — incluse le soglie di
  # carica per la salute della batteria. Ricorda: TLP e
  # power-profiles-daemon (in common.nix) non convivono, scegline uno.
  # services.tlp = {
  #   enable = true;
  #   settings = {
  #     START_CHARGE_THRESH_BAT0 = 75;
  #     STOP_CHARGE_THRESH_BAT0 = 90;
  #   };
  # };

  # ══ NON TOCCARE MAI ═════════════════════════════════════════════════
  # Marcatore di compatibilità per i dati stateful, NON una versione da
  # aggiornare: resta al valore della prima install per sempre.
  system.stateVersion = "26.05";
}

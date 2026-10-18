{ config, pkgs, ... }:

let
  p = import ./palette.nix;

  # Password e QR della rete Wi-Fi attiva. Solo su richiesta esplicita:
  # niente file, log, clipboard o shell history. La finestra ha l'app-id
  # dedicato alla regola privacy di mango (rules.conf: shield_when_capture),
  # quindi negli screencast è un rettangolo nero.
  wifiQr = pkgs.writeShellApplication {
    name = "wifi-qr";
    text = ''
      exec ${pkgs.kitty}/bin/kitty --class wifi-qr --title 'Wi-Fi QR' \
        --hold --env PAGER= ${pkgs.networkmanager}/bin/nmcli device wifi show-password
    '';
  };

  # Un box piccolo al centro: prompt ">" e lista con le icone (Tela).
  # Lo sfondo è un po' trasparente: mango ci mette il blur dietro.
  theme = pkgs.writeText "tokyonight-storm.rasi" ''
    * {
        bg:        #${p.bgDark}eb;
        bg-alt:    #${p.bg};
        fg:        #${p.fg};
        dim:       #${p.comment};
        accent:    #${p.blue};
        on-accent: #${p.bgDarker};
        urgent:    #${p.red};
        background-color: transparent;
        text-color: @fg;
        font: "Monaspace Argon 11";
    }
    window {
        location: center;
        anchor: center;
        width: 440px;
        padding: 12px;
        border: 2px;
        border-color: @accent;
        border-radius: 10px;
        background-color: @bg;
    }
    mainbox {
        spacing: 10px;
        children: [ inputbar, message, listview ];
    }
    inputbar {
        padding: 8px 12px;
        spacing: 8px;
        border-radius: 8px;
        background-color: @bg-alt;
        children: [ prompt, entry ];
    }
    prompt {
        text-color: @accent;
    }
    entry {
        placeholder: "cerca";
        placeholder-color: @dim;
        cursor: text;
    }
    message {
        padding: 6px 10px;
        border-radius: 8px;
        background-color: @bg-alt;
    }
    textbox {
        text-color: @fg;
    }
    listview {
        lines: 8;
        columns: 1;
        dynamic: true;
        fixed-height: false;
        scrollbar: false;
        spacing: 4px;
    }
    element {
        padding: 6px 10px;
        spacing: 10px;
        border-radius: 6px;
    }
    element normal.normal, element alternate.normal {
        background-color: transparent;
        text-color: @fg;
    }
    element normal.active, element alternate.active {
        text-color: @accent;
    }
    element normal.urgent, element alternate.urgent {
        text-color: @urgent;
    }
    element selected.normal, element selected.active {
        background-color: @accent;
        text-color: @on-accent;
    }
    element selected.urgent {
        background-color: @urgent;
        text-color: @on-accent;
    }
    element-icon {
        size: 22px;
        vertical-align: 0.5;
    }
    element-text {
        vertical-align: 0.5;
        text-color: inherit;
    }
  '';
in
{
  # ══ rofi: launcher (Mod+Space) e tutti i menu del desktop ════════════
  programs.rofi = {
    enable = true;
    terminal = "kitty";
    theme = "${theme}";
    extraConfig = {
      modi = "drun,run,window";
      show-icons = true;
      icon-theme = config.gtk.iconTheme.name;
      display-drun = ">";
      display-run = ">";
      display-window = ">";
      drun-display-format = "{name}";
    };
  };

  home.packages = [
    wifiQr
    pkgs.networkmanager_dmenu   # wifi: click sulla barra, pulsante nel centro di controllo
    pkgs.bzmenu                 # bluetooth: idem
  ];

  # Cercare "Wi-Fi QR" in rofi, il click medio sul wifi nella barra, il
  # pulsante nel centro di controllo o "show password" nel menu wifi.
  xdg.desktopEntries.wifi-qr = {
    name = "Wi-Fi QR";
    comment = "Mostra password e QR della rete Wi-Fi attiva in una finestra privata";
    exec = "${wifiQr}/bin/wifi-qr";
    icon = "network-wireless";
    terminal = false;
    categories = [ "Network" "Utility" ];
    settings.StartupWMClass = "wifi-qr";
  };

  # networkmanager_dmenu aggiunge da solo -dmenu e il prompt.
  xdg.configFile."networkmanager-dmenu/config.ini".text = ''
    [dmenu]
    dmenu_command = rofi -i
    prompt = wifi
    compact = True
    highlight = True
    wifi_icons = 󰤯󰤟󰤢󰤥󰤨
    format = {icon}  {name}  {sec}
    list_saved = False

    [dmenu_passphrase]
    obscure = True
    show_pass = wifi-qr

    [editor]
    terminal = kitty
    gui_if_available = True

    [nmdm]
    rescan_delay = 5
  '';
}

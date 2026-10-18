{ lib, osConfig, pkgs, ... }:

let
  p = import ./palette.nix;
  laptop = osConfig.networking.hostName == "armoredcoreVIP";
  # "36, 40, 59" per le variabili di swaync che vogliono il triplo RGB
  triplet = hex: lib.concatMapStringsSep ", " (i: toString (lib.fromHexString (builtins.substring i 2 hex))) [ 0 2 4 ];
in
{
  # ══ swaync: notifiche e centro di controllo (Mod+N, Mod+Shift+P) ═════
  # I comandi dei pulsanti girano in `/bin/sh -c "..."`: niente doppi
  # apici dentro. Chi apre un menu rofi chiude prima il pannello.
  services.swaync = {
    enable = true;
    settings = {
      positionX = "right";
      positionY = "top";
      layer = "overlay";
      control-center-layer = "top";
      layer-shell = true;
      cssPriority = "user";
      control-center-margin-top = 8;
      control-center-margin-right = 8;
      control-center-margin-bottom = 8;
      control-center-width = 420;
      notification-window-width = 400;
      fit-to-screen = true;
      timeout = 8;
      timeout-low = 4;
      timeout-critical = 0;
      hide-on-action = true;
      text-empty = "Nessuna notifica";
      widgets = [ "title" "dnd" "buttons-grid" "volume" ]
        ++ lib.optional laptop "backlight"
        ++ [ "mpris" "notifications" ];
      widget-config = {
        notifications.vexpand = true;
        title = {
          text = "Notifiche";
          clear-all-button = true;
          button-text = "Pulisci";
        };
        dnd.text = "Non disturbare";
        volume.label = "󰕾";
        backlight = {
          label = "󰃠";
          device = "intel_backlight";
        };
        mpris = {
          autohide = true;
          show-album-art = "when-available";
        };
        buttons-grid = {
          buttons-per-row = 5;
          actions = [
            { label = "󰤨"; command = "swaync-client -cp; networkmanager_dmenu"; }
            { label = "󰂯"; command = "swaync-client -cp; bzmenu --launcher rofi"; }
            { label = "󰐲"; command = "swaync-client -cp; wifi-qr"; }
            {
              label = "󰖔";
              type = "toggle";
              command = "nightlight.sh toggle";
              update-command = "nightlight.sh status";
            }
            { label = "󰐥"; command = "swaync-client -cp; powermenu.sh"; }
          ];
        };
      };
    };
    # Lo stile di swaync più i colori Tokyo Night Storm: le sue variabili
    # CSS sono tutte qui, il resto del file di default resta valido.
    style = ''
      @import url("file://${pkgs.swaynotificationcenter}/etc/xdg/swaync/style.css");

      :root {
        --cc-bg: rgba(${triplet p.bgDark}, 0.92);
        --noti-border-color: #${p.fgGutter};
        --noti-bg: ${triplet p.bg};
        --noti-bg-alpha: 0.95;
        --noti-bg-darker: #${p.bgDark};
        --noti-bg-hover: #${p.bgHighlight};
        --noti-bg-focus: rgba(${triplet p.bgHighlight}, 0.6);
        --noti-close-bg: #${p.terminalBlack};
        --noti-close-bg-hover: #${p.comment};
        --text-color: #${p.fg};
        --text-color-disabled: #${p.comment};
        --bg-selected: #${p.blue};
        --border-radius: 10px;
        --font-size-body: 13px;
        --font-size-summary: 14px;
      }

      * {
        font-family: "Monaspace Argon", "Symbols Nerd Font";
      }

      .control-center .widget-buttons-grid > flowbox > flowboxchild > button.toggle:checked {
        background: #${p.blue};
        color: #${p.bgDarker};
      }

      .notification.critical {
        border: 1px solid #${p.red};
      }
    '';
  };

  # ══ swayosd: volume e luminosità a schermo (i bind in binds.conf) ════
  services.swayosd = {
    enable = true;
    stylePath = pkgs.writeText "swayosd.css" ''
      window#osd {
        border-radius: 999px;
        border: 2px solid #${p.fgGutter};
        background: alpha(#${p.bgDark}, 0.92);
      }
      window#osd #container {
        margin: 14px 18px;
      }
      window#osd image,
      window#osd label {
        color: #${p.fg};
      }
      window#osd progressbar:disabled,
      window#osd image:disabled {
        opacity: 0.5;
      }
      window#osd progressbar,
      window#osd segmentedprogress {
        min-height: 6px;
        border-radius: 999px;
        background: transparent;
        border: none;
      }
      window#osd trough,
      window#osd segment {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: #${p.terminalBlack};
      }
      window#osd progress,
      window#osd segment.active {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: #${p.blue};
      }
      window#osd segment {
        margin-left: 8px;
      }
      window#osd segment:first-child {
        margin-left: 0;
      }
    '';
  };
}

{ lib, osConfig, ... }:

let
  p = import ./palette.nix;
  laptop = osConfig.networking.hostName == "armoredcoreVIP";
in
{
  # ══ waybar: la barra (Ctrl+Alt+W la nasconde) ═══════════════════════
  # A sinistra i tag 1–9 e 0 (il decimo): quello attivo in blu, quelli con
  # finestre in chiaro, quelli vuoti spenti. A destra un riquadro per
  # informazione; i click aprono i menu rofi (wifi, bluetooth, appunti,
  # spegnimento). mango parla il protocollo ext-workspace, che waybar
  # legge con ext/workspaces.
  programs.waybar = {
    enable = true;
    systemd.enable = true;   # parte con graphical-session.target
    settings.main = {
      layer = "top";
      position = "top";
      height = 30;
      margin-top = 6;
      margin-left = 8;
      margin-right = 8;
      spacing = 6;

      modules-left = [ "ext/workspaces" ];
      modules-right = [
        "tray"
        "pulseaudio"
        "cpu"
        "custom/kernel"
        "memory"
        "network"
        "bluetooth"
        "custom/clipboard"
      ] ++ lib.optional laptop "battery" ++ [
        "clock"
        "custom/power"
      ];

      "ext/workspaces" = {
        format = "{icon}";
        # Anche i tag vuoti (mango li segna "hidden"), in ordine 1…9, 0:
        # mango non dà un id ai workspace, si ordinano per nome (numerico).
        ignore-hidden = false;
        sort-by-name = true;
        format-icons."10" = "0";
        on-click = "activate";
      };

      # Solo quando un'app ha un'icona nel tray (es. Steam chiuso con Mod+Q).
      tray = {
        icon-size = 15;
        spacing = 8;
        show-passive-items = false;
      };

      pulseaudio = {
        format = "{icon} {volume}%";
        format-muted = "󰝟 muto";
        format-icons.default = [ "󰕿" "󰖀" "󰕾" ];
        scroll-step = 5;
        on-click = "pavucontrol";
        on-click-right = "swayosd-client --output-volume mute-toggle";
        tooltip-format = "{desc}";
      };

      cpu = {
        format = "󰻠 {usage}%";
        interval = 3;
        on-click = "kitty -e htop";
      };

      "custom/kernel" = {
        format = " {}";
        exec = "uname -r";
        interval = "once";
        tooltip = false;
      };

      memory = {
        format = "󰍛 {percentage}%";
        interval = 5;
        tooltip-format = "{used:0.1f} / {total:0.1f} GiB";
        on-click = "kitty -e htop";
      };

      # Click: menu wifi (networkmanager_dmenu). Medio: password e QR.
      network = {
        format-wifi = "{icon} {essid}";
        format-ethernet = "󰈀 cavo";
        format-disconnected = "󰤮 off";
        format-icons = [ "󰤟" "󰤢" "󰤥" "󰤨" ];
        max-length = 18;
        tooltip-format-wifi = "{essid} ({signalStrength}%)\n{ipaddr}";
        tooltip-format-ethernet = "{ifname}\n{ipaddr}";
        on-click = "networkmanager_dmenu";
        on-click-middle = "wifi-qr";
      };

      bluetooth = {
        format = "󰂯";
        format-off = "󰂲";
        format-disabled = "󰂲";
        format-connected = "󰂱 {num_connections}";
        tooltip-format-connected = "{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}";
        on-click = "bzmenu --launcher rofi";
      };

      "custom/clipboard" = {
        format = "󰅇";
        tooltip-format = "Cronologia appunti";
        on-click = "clipboard.sh";
      };

      battery = {
        format = "{icon} {capacity}%";
        format-charging = "󰂄 {capacity}%";
        format-plugged = "󰚥 {capacity}%";
        format-icons = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
        states = {
          warning = 20;
          critical = 10;
        };
        tooltip-format = "{timeTo}";
      };

      # "Mon 17 11:26"; il calendario nel tooltip.
      clock = {
        format = "{:%a %d %H:%M}";
        tooltip-format = "<tt>{calendar}</tt>";
        calendar = {
          mode = "month";
          weeks-pos = "";
          format = {
            months = "<span color='#${p.blue}'><b>{}</b></span>";
            weekdays = "<span color='#${p.comment}'>{}</span>";
            today = "<span color='#${p.bgDarker}' background='#${p.blue}'><b>{}</b></span>";
          };
        };
      };

      "custom/power" = {
        format = "⏻";
        tooltip-format = "Spegni, riavvia, esci…";
        on-click = "powermenu.sh";
      };
    };

    # Riquadri piccoli e separati sopra una barra trasparente.
    style = ''
      * {
        font-family: "Monaspace Argon", "Symbols Nerd Font";
        font-size: 13px;
        min-height: 0;
        border: none;
        border-radius: 0;
      }

      window#waybar {
        background: transparent;
        color: #${p.fg};
      }

      tooltip {
        background: #${p.bgDark};
        border: 1px solid #${p.fgGutter};
        border-radius: 8px;
      }
      tooltip label {
        color: #${p.fg};
      }

      .modules-left > widget > *,
      .modules-right > widget > * {
        background: alpha(#${p.bgDark}, 0.92);
        border: 1px solid #${p.bgHighlight};
        border-radius: 8px;
        padding: 0 10px;
      }

      #workspaces {
        padding: 0 4px;
      }
      #workspaces button {
        padding: 0 6px;
        margin: 3px 1px;
        border-radius: 6px;
        background: transparent;
        color: #${p.fg};
      }
      #workspaces button.hidden {
        color: #${p.comment};
      }
      #workspaces button.active {
        background: #${p.blue};
        color: #${p.bgDarker};
      }
      #workspaces button.urgent {
        background: #${p.red};
        color: #${p.bgDarker};
      }
      #workspaces button:hover {
        background: #${p.bgHighlight};
        color: #${p.fg};
      }

      #pulseaudio { color: #${p.blue}; }
      #pulseaudio.muted { color: #${p.comment}; }
      #cpu { color: #${p.green}; }
      #custom-kernel { color: #${p.blue1}; }
      #memory { color: #${p.magenta}; }
      #network { color: #${p.green1}; }
      #network.disconnected { color: #${p.comment}; }
      #bluetooth { color: #${p.cyan}; }
      #bluetooth.off, #bluetooth.disabled { color: #${p.comment}; }
      #custom-clipboard { color: #${p.yellow}; }
      #battery { color: #${p.green}; }
      #battery.warning:not(.charging) { color: #${p.yellow}; }
      #battery.critical:not(.charging) { color: #${p.red}; }
      #clock { color: #${p.fg}; }
      #custom-power { color: #${p.red}; padding: 0 12px 0 10px; }
    '';
  };
}

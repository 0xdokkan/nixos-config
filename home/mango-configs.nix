# ══ mango: config.conf + binds/rules/gaming + theme/host, validati a BUILD-TIME ══
# Se una delle config ha un errore o un avviso il sistema non si builda. ✨
#
# È una funzione { pkgs, layout, cursor, palette } → derivazione:
#   - home/mango.nix → la linka in ~/.config/mango/ (layout e cursore
#                      dell'host)
#   - flake.nix      → la espone in `checks`, così `nix flake check`
#                      fa girare `mango -p` davvero
#
# I file stanno nella stessa directory perché si includono a vicenda con
# path relativi: gaming.conf → config.conf → theme/host/rules/binds.conf.
#
# theme.conf e host.conf sono generati qui:
#   theme.conf  colori da home/palette.nix (0xRRGGBBAA) e cursore
#   host.conf   layout tastiera (us sul fisso, it,us sul portatile:
#               lo calcola home/mango.nix)
#
# `mango -p` esce con 1 sugli errori ma con 0 sugli avvisi ([WARN], per
# esempio due bind sullo stesso tasto): per questo il controllo guarda
# anche il suo output.
{ pkgs
, layout ? "us"
, cursor ? { name = "Bibata-Modern-Ice"; size = 20; }
, palette ? import ./palette.nix
}:

let
  c = name: alpha: "0x${palette.${name}}${alpha}";
  theme = pkgs.writeText "mango-theme.conf" ''
    # GENERATO da home/mango-configs.nix — colori da home/palette.nix
    root_color=${c "bgDarker" "ff"}
    border_color=${c "terminalBlack" "ff"}
    focus_color=${c "blue" "ff"}
    maximized_screen_color=${c "green1" "ff"}
    urgent_color=${c "red" "ff"}
    scratchpad_color=${c "cyan" "ff"}
    global_color=${c "magenta" "ff"}
    overlay_color=${c "orange" "ff"}
    drop_color=${c "blue" "55"}
    split_color=${c "yellow" "ff"}
    shadows_color=0x00000066

    # Schede dei gruppi (Mod+G)
    group_bar_height=26
    group_bar_decorate_font_desc=Monaspace Argon 10
    group_bar_decorate_bg_color=${c "bgDark" "ff"}
    group_bar_decorate_fg_color=${c "fgDark" "ff"}
    group_bar_decorate_focus_bg_color=${c "blue" "ff"}
    group_bar_decorate_focus_fg_color=${c "bgDarker" "ff"}
    group_bar_decorate_border_color=${c "terminalBlack" "ff"}
    group_bar_decorate_border_width=2
    group_bar_decorate_corner_radius=8

    # Etichette della overview in modalità salto
    jump_label_decorate_font_desc=Monaspace Argon Bold 14
    jump_label_decorate_bg_color=${c "bgDark" "ff"}
    jump_label_decorate_fg_color=${c "fg" "ff"}
    jump_label_decorate_focus_bg_color=${c "blue" "ff"}
    jump_label_decorate_focus_fg_color=${c "bgDarker" "ff"}
    jump_label_decorate_border_color=${c "blue" "ff"}
    jump_label_decorate_border_width=2
    jump_label_decorate_corner_radius=8

    # Lo stesso cursore di home.pointerCursor
    cursor_theme=${cursor.name}
    cursor_size=${toString cursor.size}
  '';
  host = pkgs.writeText "mango-host.conf" ''
    # GENERATO da home/mango-configs.nix — layout dall'host (vedi home/mango.nix)
    xkb_rules_layout=${layout}
  '';
in
pkgs.runCommand "mango-config-checked"
  { nativeBuildInputs = [ pkgs.mango ]; } ''
  mkdir -p $out
  cp ${../dotfiles/mango/config.conf} $out/config.conf
  cp ${../dotfiles/mango/binds.conf}  $out/binds.conf
  cp ${../dotfiles/mango/rules.conf}  $out/rules.conf
  cp ${../dotfiles/mango/gaming.conf} $out/gaming.conf
  cp ${theme} $out/theme.conf
  cp ${host}  $out/host.conf

  export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR
  for conf in config.conf gaming.conf; do
    status=0
    mango -c $out/$conf -p > raw.log 2>&1 || status=$?
    sed 's/\x1b\[[0-9;]*m//g' raw.log > check.log
    cat check.log
    if [ $status -ne 0 ] || grep -qiE 'error|warn' check.log; then
      echo "mango -p: $conf non è valida" >&2
      exit 1
    fi
  done
''

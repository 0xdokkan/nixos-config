{ pkgs, rofi ? pkgs.rofi }:

let
  mgba = pkgs.libretro.mgba;
  psx = pkgs.libretro.beetle-psx;
  snes = pkgs.libretro.snes9x;
  retroarch = pkgs.retroarch.withCores (_: [ mgba psx snes ]);
in
pkgs.runCommand "retro-suite" {
  nativeBuildInputs = [ pkgs.makeWrapper ];
  passthru = { inherit retroarch; };
  meta = {
    description = "Launcher per Metroid Zero Mission, Symphony of the Night e Super Metroid";
    mainProgram = "retro-suite";
    platforms = pkgs.lib.platforms.linux;
  };
} ''
  install -Dm644 ${./retro-suite.py} $out/libexec/retro-suite.py
  mkdir -p $out/bin
  makeWrapper ${pkgs.python3}/bin/python3 $out/bin/retro-suite \
    --add-flags "$out/libexec/retro-suite.py" \
    --set RETRO_SUITE_RETROARCH ${retroarch}/bin/retroarch \
    --set RETRO_SUITE_ROFI ${rofi}/bin/rofi \
    --set RETRO_SUITE_ZENITY ${pkgs.zenity}/bin/zenity \
    --set RETRO_SUITE_XDG_OPEN ${pkgs.xdg-utils}/bin/xdg-open \
    --set RETRO_SUITE_CORE_MGBA ${mgba}${mgba.libretroCore}/mgba_libretro.so \
    --set RETRO_SUITE_CORE_PSX ${psx}${psx.libretroCore}/mednafen_psx_libretro.so \
    --set RETRO_SUITE_CORE_SNES ${snes}${snes.libretroCore}/snes9x_libretro.so
''

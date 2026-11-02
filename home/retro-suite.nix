{ config, pkgs, ... }:

let
  suite = import ./retro-suite-package.nix {
    inherit pkgs;
    rofi = config.programs.rofi.package;
  };
in
{
  home.packages = [ suite suite.retroarch ];

  xdg.desktopEntries.retro-suite = {
    name = "Retro Suite";
    comment = "Metroid Zero Mission, Symphony of the Night e Super Metroid";
    exec = "${suite}/bin/retro-suite";
    icon = "applications-games";
    terminal = false;
    categories = [ "Game" "Emulator" ];
  };
}

# Gli script di dotfiles/mango/scripts:
# - i pacchetti veri (home/mango-scripts.nix): buildarli fa girare ShellCheck;
# - tests/mango-scripts.py li prova con mango, rofi & co. finti;
# - ogni "qualcosa.sh" chiamato da bind, waybar o swaync esiste davvero.
{ pkgs, scripts, home }:

let
  files = ../dotfiles/mango/scripts;
  binds = ../dotfiles/mango/binds.conf;
  callers = map (file: "${file}") [
    ../dotfiles/mango/config.conf
    binds
    home.xdg.configFile."waybar/config".source
    home.xdg.configFile."swaync/config.json".source
  ];
in
pkgs.runCommand "mango-scripts-checked" {
  nativeBuildInputs = with pkgs; [ python3 bash coreutils jq gawk findutils gnugrep ];
  packaged = builtins.attrValues scripts;
  names = builtins.attrNames scripts;
} ''
  cat ${pkgs.lib.escapeShellArgs callers} > callers
  for used in $(grep -ohE '[A-Za-z0-9_-]+\.sh' callers | sort -u); do
    case " $names " in
      *" $used "*) ;;
      *) echo "$used è usato ma non è tra gli script installati" >&2; exit 1 ;;
    esac
  done
  for script in ${files}/*.sh; do
    case " $names " in
      *" ''${script##*/} "*) ;;
      *) echo "''${script##*/} non è impacchettato in home/mango-scripts.nix" >&2; exit 1 ;;
    esac
  done
  for package in $packaged; do
    test -x "$package"/bin/*.sh
  done

  python ${./mango-scripts.py} ${files} ${binds}
  touch "$out"
''

{ pkgs, noctaliaPackage, configFile, paletteFile }:

pkgs.runCommand "noctalia-settings-checked" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  # Solo CLI offline: nessuna shell grafica, IPC di sessione o attivazione HM.
  python ${./noctalia-settings.py} \
    --noctalia ${pkgs.lib.getExe noctaliaPackage} \
    --config ${pkgs.lib.escapeShellArg (toString configFile)} \
    --palette ${paletteFile}
  touch "$out"
''

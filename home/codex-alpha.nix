# ══ Codex CLI dal canale alpha ════════════════════════════════════════
# Il pacchetto ufficiale della prerelease su GitHub, precompilato, invece
# della build da sorgente di llm-agents (che segue solo le stabili, e
# un'alpha da sorgente sarebbe una compilazione Rust completa a ogni
# aggiornamento, senza cache). Versione, URL e hash stanno in
# codex-alpha.json: li aggiorna `nixup` (all e ai) con
# codex-alpha-update.sh, alla release pubblicata per ultima, alpha o
# stabile che sia.
#
# Il pacchetto è quello che upstream installa (bin/, codex-path/rg,
# codex-resources/bwrap e la voce), quindi codex trova tutto da solo.
# Rispetto a llm-agents mancano le sue patch Nix: il demone app-server,
# se lo usi, si installa e si aggiorna da solo in ~/.codex.
{ pkgs }:

let
  inherit (pkgs) lib;
  pin = lib.importJSON ./codex-alpha.json;
in
pkgs.stdenv.mkDerivation {
  pname = "codex";
  inherit (pin) version;

  src = pkgs.fetchurl { inherit (pin) url hash; };
  # Il tar ha più cartelle in cima (bin, codex-path, codex-resources).
  sourceRoot = ".";

  nativeBuildInputs = [ pkgs.installShellFiles ];
  dontConfigure = true;
  dontBuild = true;
  # I binari restano come li pubblica upstream: strip e shrink-rpath
  # toccherebbero il $ORIGIN con cui la voce trova le sue librerie.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/codex $out/bin
    cp -r bin codex-path codex-resources codex-package.json $out/libexec/codex/
    # Tutto è musl statico tranne la voce, che usa la glibc: il loader
    # /lib64/ld-linux-x86-64.so.2 su NixOS c'è solo grazie a nix-ld, quindi
    # le diamo quello di Nix. GStreamer e Opus restano i suoi, via $ORIGIN.
    patchelf --set-interpreter ${pkgs.stdenv.cc.bintools.dynamicLinker} \
      $out/libexec/codex/codex-resources/voice/bin/codex-voice-host
    # Link e non wrapper: codex trova bwrap, rg e il resto del pacchetto
    # risalendo dal proprio eseguibile, com'è nel layout di upstream.
    for tool in codex codex-code-mode-host codex-exec-server; do
      ln -s ../libexec/codex/bin/$tool $out/bin/$tool
    done
    runHook postInstall
  '';

  postInstall = ''
    export HOME=$TMPDIR
    installShellCompletion --cmd codex \
      --bash <($out/bin/codex completion bash) \
      --fish <($out/bin/codex completion fish) \
      --zsh <($out/bin/codex completion zsh)
  '';

  # `codex --version` deve dire la versione del pin.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ pkgs.versionCheckHook ];

  meta = {
    description = "OpenAI Codex CLI, canale alpha (binari ufficiali)";
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/openai/codex/releases/tag/rust-v${pin.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "codex";
    platforms = [ "x86_64-linux" ];
  };
}

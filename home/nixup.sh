#!/usr/bin/env bash
# Il wrapper Nix fissa repository, host e sistema corrente. I test usano
# questo stesso script con percorsi temporanei e comandi Nix/sudo simulati.
set -euo pipefail

usage() {
    printf '%s\n' \
        'Uso: nixup [all|ai|apply]' \
        '  all    aggiorna tutti gli input (default), verifica e mostra il diff' \
        '  ai     aggiorna soltanto llm-agents, verifica e mostra il diff' \
        '  apply  usa il lock e le modifiche già presenti, senza aggiornare input' \
        'Il sistema cambia soltanto dopo conferma. Niente pull, commit o push automatici.'
}

die() {
    printf 'nixup: %s\n' "$*" >&2
    exit 1
}

mode=${1:-all}
[[ $# -le 1 ]] || { usage >&2; exit 2; }
case "$mode" in
    -h|--help) usage; exit 0 ;;
    all|ai|apply) ;;
    *) usage >&2; exit 2 ;;
esac

[[ $EUID -ne 0 ]] || die 'avvialo come utente normale, senza sudo.'
: "${NIXUP_REPO:?repository non configurato}"
: "${NIXUP_HOST:?host non configurato}"
: "${NIXUP_SYSTEM:?sistema corrente non configurato}"
: "${NIXUP_REBUILD:?nixos-rebuild non configurato}"
[[ -x "$NIXUP_SYSTEM/bin/switch-to-configuration" ]] || die 'questo comando va eseguito sul sistema NixOS installato.'
[[ $(uname -n) == "$NIXUP_HOST" ]] || die "host diverso da $NIXUP_HOST: nessuna operazione eseguita."
repo=$(realpath -e -- "$NIXUP_REPO")
[[ -d "$repo" ]] || die 'repository non trovato.'
cd -- "$repo"
[[ $(git rev-parse --show-toplevel) == "$repo" ]] || die 'il percorso deve essere la radice del repository Git.'
[[ -f flake.nix && -f flake.lock ]] || die 'servono flake.nix e flake.lock nel repository.'
git ls-files --error-unmatch -- flake.nix flake.lock >/dev/null || die 'flake.nix e flake.lock devono essere tracciati da Git.'

# Serializza le istanze del comando sullo stesso checkout. Il file del lock
# resta in .git; il lock del processo viene rilasciato all'uscita.
exec 9> "$(git rev-parse --git-path nixup.lock)"
flock -n 9 || die 'un altro nixup sta già lavorando su questo repository.'

[[ -z $(git ls-files --others --exclude-standard) ]] || die 'ci sono file non tracciati: controlla git status e aggiungi quelli della config con git add.'
if [[ "$mode" != apply && -n $(git status --porcelain) ]]; then
    die 'salva/committa le modifiche prima di aggiornare, oppure usa nixup apply per verificare quelle presenti senza aggiornare gli input.'
fi

workDir=$(mktemp -d -t nixup.XXXXXXXX)
cleanup() {
    # Solo i link creati da questa esecuzione; non cancellare store o dati utente.
    rm -f -- "$workDir/result"
    rmdir -- "$workDir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Repository: %s\nHost: %s\nModalità: %s\n' "$repo" "$NIXUP_HOST" "$mode"
printf '%s\n' 'Il flake.lock aggiornato resta nel repository anche in caso di errore o annullamento.'
case "$mode" in
    all) nix flake update ;;
    ai) nix flake update llm-agents ;;
    apply) printf '%s\n' 'Uso gli input già bloccati, senza cercare aggiornamenti.' ;;
esac

# Check, build e attivazione devono usare lo STESSO snapshot immutabile:
# una modifica dal desktop/editor mentre si guarda il diff non deve cambiare
# silenziosamente ciò che verrà applicato dopo la conferma.
snapshot=$(nix flake metadata --json --no-update-lock-file --no-write-lock-file . | jq -er '.path')
[[ "$snapshot" == /nix/store/* && -d "$snapshot" ]] || die 'Nix non ha restituito uno snapshot valido nello store.'
printf '\n%s\n' 'Verifico la configurazione...'
nix flake check --no-update-lock-file --no-write-lock-file "$snapshot"
printf '\n%s\n' 'Costruisco il sistema candidato (senza attivarlo)...'
nix build --no-update-lock-file --no-write-lock-file --out-link "$workDir/result" \
    "$snapshot#nixosConfigurations.$NIXUP_HOST.config.system.build.toplevel"
candidate=$(readlink -e -- "$workDir/result")
[[ -x "$candidate/bin/switch-to-configuration" ]] || die 'il risultato non è un sistema NixOS attivabile.'
printf '\n%s\n' 'Differenze rispetto al sistema attivo:'
nvd diff "$NIXUP_SYSTEM" "$candidate"

printf '\nApplicare questo sistema a %s? [s/N] ' "$NIXUP_HOST"
answer=
if ! IFS= read -r answer; then
    answer=
fi
case "${answer,,}" in
    s|si|sì|y|yes) ;;
    *)
        printf '\n%s\n' 'Annullato: sistema invariato. Il lock resta disponibile; puoi riprovare con nixup apply.'
        exit 0
        ;;
esac

# --store-path evita una seconda valutazione: si applica proprio la closure
# appena costruita e mostrata, non un nuovo risultato risolto come root.
sudo "$NIXUP_REBUILD" switch --store-path "$candidate"
printf '\n%s\n' \
    'Configurazione applicata. Provala prima di committare e pubblicare flake.lock.' \
    'Se è cambiato il kernel, serve un riavvio. Nessun reboot o garbage collection automatico.'

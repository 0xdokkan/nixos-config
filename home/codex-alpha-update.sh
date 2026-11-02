#!/usr/bin/env bash
# Porta home/codex-alpha.json alla release di Codex pubblicata per ultima
# su GitHub (alpha o stabile) che abbia già il pacchetto Linux caricato.
# Lo lancia nixup (all e ai) dalla radice del repository, dopo
# `nix flake update`. I test usano questo stesso script con curl e nix
# simulati (tests/codex-alpha.py).
set -euo pipefail

pin=${CODEX_ALPHA_PIN:-home/codex-alpha.json}
api=${CODEX_ALPHA_API:-https://api.github.com/repos/openai/codex/releases?per_page=30}
asset=codex-package-x86_64-unknown-linux-musl.tar.gz

die() {
    printf 'codex-alpha: %s\n' "$*" >&2
    exit 1
}

[[ -f "$pin" ]] || die "$pin non trovato (va lanciato dalla radice del repository)."
current=$(jq -er '.version' "$pin") || die "$pin non ha una versione valida."

releases=$(curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' "$api") \
    || die 'impossibile leggere le release da GitHub.'

# Le release di Codex hanno il tag rust-v<versione>; rusty-v8-* sono altri
# artefatti. Un'alpha appena pubblicata può non avere ancora il pacchetto:
# in quel caso vale la precedente.
# shellcheck disable=SC2016  # le variabili sono di jq, non della shell
latest=$(jq -ec --arg asset "$asset" '
    [ .[]
      | select((.draft | not) and (.tag_name | test("^rust-v[0-9]")))
      | . as $release
      | (.assets[] | select(.name == $asset and .state == "uploaded")) as $file
      | { published: $release.published_at,
          version: ($release.tag_name | ltrimstr("rust-v")),
          url: $file.browser_download_url } ]
    | sort_by(.published) | last
    | select(. != null)' <<<"$releases") \
    || die "nessuna release con $asset."
version=$(jq -er '.version' <<<"$latest")
url=$(jq -er '.url' <<<"$latest")

if [[ "$version" == "$current" ]]; then
    printf 'Codex: già alla %s.\n' "$current"
    exit 0
fi

printf "Codex: %s → %s (scarico il pacchetto per calcolarne l'hash)\n" "$current" "$version"
hash=$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -er '.hash') \
    || die "download di $url non riuscito: pin invariato."

# Scrittura atomica: un errore a metà non lascia un pin rotto.
tmp=$(mktemp "$pin.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
chmod 644 -- "$tmp"
jq -n --arg version "$version" --arg url "$url" --arg hash "$hash" \
    '{ version: $version, url: $url, hash: $hash }' > "$tmp"
mv -- "$tmp" "$pin"
trap - EXIT

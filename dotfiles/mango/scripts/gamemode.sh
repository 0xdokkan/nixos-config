#!/usr/bin/env bash
# Mod+Alt+G: modalità gioco. mango carica gaming.conf, che include
# config.conf e toglie gap, animazioni, blur e ombre; ripremendo torna a
# config.conf. I file stanno nello store (read-only): non si copiano, si
# dice a mango quale caricare con `mmsg dispatch load_config_file,FILE`.
#
# Lo stato è per istanza di mango (hash di MANGO_INSTANCE_SIGNATURE) in
# $XDG_RUNTIME_DIR, quindi un nuovo login riparte dalla config normale.
# flock mette in fila due pressioni ravvicinate. Se mango non accetta il
# comando lo stato non cambia; se manca il demone delle notifiche il
# cambio resta valido. Mod+Shift+C ricarica la config attiva, qualunque
# delle due sia.
set -euo pipefail

if [[ -z ${XDG_RUNTIME_DIR:-} || -z ${MANGO_INSTANCE_SIGNATURE:-} ]]; then
    echo 'gamemode: servono XDG_RUNTIME_DIR e MANGO_INSTANCE_SIGNATURE della sessione mango' >&2
    exit 1
fi
if [[ ! -d $XDG_RUNTIME_DIR || ! -w $XDG_RUNTIME_DIR ]]; then
    echo 'gamemode: XDG_RUNTIME_DIR non è una directory scrivibile' >&2
    exit 1
fi

dir=${XDG_CONFIG_HOME:-$HOME/.config}/mango
session=$(printf '%s' "$MANGO_INSTANCE_SIGNATURE" | sha256sum | cut -d ' ' -f 1)
state_dir=$XDG_RUNTIME_DIR/mango-gamemode
state=$state_dir/$session.state

umask 077
mkdir -p "$state_dir"
exec 9> "$state.lock"
flock -x 9

current=normal
if [[ -f $state ]]; then
    current=$(< "$state")
fi

case $current in
    normal)
        next=gaming
        file=$dir/gaming.conf
        message='ON — niente gap, animazioni, blur e ombre'
        ;;
    gaming)
        next=normal
        file=$dir/config.conf
        message='OFF — config normale ripristinata'
        ;;
    *)
        echo "gamemode: stato non valido in $state" >&2
        exit 1
        ;;
esac

# mango divide gli argomenti sulle virgole; e con un file che non esiste
# ripartirebbe dai suoi default, senza nessuna delle nostre scorciatoie.
if [[ $file == *,* || ! -r $file ]]; then
    echo "gamemode: config non utilizzabile: $file" >&2
    exit 1
fi

if ! reply=$(mmsg dispatch "load_config_file,$file") || [[ $reply != *'"success":true'* ]]; then
    echo 'gamemode: mango non ha caricato la config; stato precedente conservato' >&2
    notify-send -a mango 'Game mode' 'Cambio di config fallito (vedi journal)' || true
    exit 1
fi

printf '%s\n' "$next" > "$state"
notify-send -a mango 'Game mode' "$message" || true

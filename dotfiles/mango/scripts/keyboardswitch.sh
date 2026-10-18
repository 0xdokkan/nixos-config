#!/usr/bin/env bash
# Mod+K: layout tastiera successivo (it ↔ us sul portatile) e una
# notifica breve con quello attivo.
set -euo pipefail

mmsg dispatch switch_keyboard_layout > /dev/null
layout=$(mmsg get keyboardlayout | jq -r '.layout // empty')
notify-send -a mango -r 91190 -t 800 -i input-keyboard "${layout:-(layout)}" || true

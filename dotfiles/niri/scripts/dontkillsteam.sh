#!/usr/bin/env sh
#
# dontkillsteam.sh — versione niri
#
# Originale HyDE: chiudeva la finestra attiva ma se era Steam la "unmappava"
# tramite xdotool (per tenere Steam in tray). Per niri sostituiamo
# `hyprctl activewindow` con `niri msg --json focused-window`.

focused_app=$(niri msg --json focused-window 2>/dev/null | jq -r '.app_id // empty')

if [ "${focused_app}" = "Steam" ] || [ "${focused_app}" = "steam" ]; then
    # Steam usa xwayland — xdotool funziona sulle finestre X11
    xdotool windowunmap "$(xdotool getactivewindow)"
else
    niri msg action close-window
fi

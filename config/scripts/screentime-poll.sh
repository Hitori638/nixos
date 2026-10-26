#!/usr/bin/env bash
# screentime-poll.sh — one snapshot for Quickshell's screen-time tracker (run every 5 s).
#   L 0|1            screen locked?
#   A <class>        focused window
#   W <id>           workspace visible on some monitor (incl. shown special workspaces)
#   C <ws> <class>   every mapped window, on any workspace
#   P <status> <player>  MPRIS players (Spotify, browsers, mpv …)
L=0
pidof hyprlock >/dev/null 2>&1 && L=1
echo "L $L"
hyprctl activewindow -j 2>/dev/null | jq -r '"A " + (.class // "")' 2>/dev/null
hyprctl monitors -j 2>/dev/null | jq -r '.[] | "W \(.activeWorkspace.id)", (select((.specialWorkspace.id // 0) != 0) | "W \(.specialWorkspace.id)")' 2>/dev/null
hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.mapped and ((.hidden // false) | not)) | select((.class // "") != "") | "C \(.workspace.id) \(.class)"' 2>/dev/null
playerctl -a metadata --format 'P {{status}} {{playerName}}' 2>/dev/null
exit 0

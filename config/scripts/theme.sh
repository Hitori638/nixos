#!/usr/bin/env bash
# theme.sh light|dark — called by Quickshell's theme toggle.
# Sets the desktop-wide colour-scheme hint (libadwaita / GTK4 apps, and web pages
# using prefers-color-scheme in browsers that follow it) and swaps the GTK theme
# between Catppuccin Latte and Mocha for GTK3 apps such as Thunar.

mode="${1:-dark}"
if [ "$mode" = "light" ]; then
	scheme="prefer-light"
	gtk="catppuccin-latte-pink-standard"
else
	scheme="prefer-dark"
	gtk="catppuccin-mocha-pink-standard"
fi

set_key() {
	if command -v gsettings >/dev/null 2>&1; then
		gsettings set org.gnome.desktop.interface "$1" "$2"
	elif command -v dconf >/dev/null 2>&1; then
		dconf write "/org/gnome/desktop/interface/$1" "'$2'"
	fi
}

theme_exists() {
	for d in "$HOME/.nix-profile/share/themes" "/etc/profiles/per-user/$USER/share/themes" \
		"$HOME/.local/share/themes" "$HOME/.themes" "/run/current-system/sw/share/themes"; do
		[ -d "$d/$1" ] && return 0
	done
	return 1
}

set_key color-scheme "$scheme"
# only switch the GTK theme if that variant is installed (Latte needs one `nrs`)
theme_exists "$gtk" && set_key gtk-theme "$gtk"
exit 0

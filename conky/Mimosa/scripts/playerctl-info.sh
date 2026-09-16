#!/bin/bash

# Enhanced playerctl info script for widescreen music card

PCTL=$(playerctl status 2>/dev/null)

# Feather Font icons
ICON_NONE=""
ICON_STOPPED=""
ICON_PLAYING=""
ICON_PAUSED=""
ICON_UNKNOWN=""

case "$1" in
	-a)
		if [[ -z "$PCTL" ]]; then
			echo "No music playing"
		else
			playerctl metadata xesam:artist 2>/dev/null | cut -c 1-35
		fi
		;;
	-t)
		if [[ -z "$PCTL" ]]; then
			echo ""
		else
			playerctl metadata xesam:title 2>/dev/null | cut -c 1-35
		fi
		;;
	-p)
		if [[ -z "$PCTL" ]]; then
			echo ""
		else
			POS=$(playerctl position --format "{{ duration(position) }}" 2>/dev/null)
			LEN=$(playerctl metadata --format "{{ duration(mpris:length) }}" 2>/dev/null)
			if [[ -n "$LEN" && "$LEN" != "0:00" ]]; then
				echo "$POS / $LEN"
			else
				echo "$POS"
			fi
		fi
		;;
	-i)
		case "$PCTL" in
			"")
				echo "$ICON_NONE"
				;;
			"Stopped")
				echo "$ICON_STOPPED"
				;;
			"Playing")
				echo "$ICON_PLAYING"
				;;
			"Paused")
				echo "$ICON_PAUSED"
				;;
			*)
				echo "$ICON_UNKNOWN"
				;;
		esac
		;;
	*)
		echo "Usage: $0 -a (artist) | -t (title) | -p (position) | -i (icon)"
		exit 1
		;;
esac

exit 0

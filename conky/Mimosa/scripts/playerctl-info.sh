#!/bin/bash

# Enhanced playerctl info script for Conky Mimosa media widget
# Supports album art caching, multi-player priority, clean title/artist parsing,
# and progress percentage for Android Auto style wavy seekbar

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$(cd "$SCRIPT_DIR/../assets" 2>/dev/null && pwd)"
[[ ! -d "$ASSETS_DIR" ]] && ASSETS_DIR="$HOME/.config/conky/Mimosa/assets"

COVER_CACHE="/tmp/conky_cover.png"
URL_CACHE="/tmp/conky_current_arturl"
STATE_CACHE="/tmp/conky_media_state"
DEFAULT_COVER="$ASSETS_DIR/default_cover.png"

PLAYER_ARG="--player=spotify,plasma-browser-integration,elisa,strawberry,vlc,mpd,audacious,cider,%any"

# Feather Font icons
ICON_NONE=""
ICON_STOPPED=""
ICON_PLAYING=""
ICON_PAUSED=""
ICON_UNKNOWN=""

truncate_text() {
    local text="$1"
    local max=25
    if (( ${#text} > max )); then
        echo "${text:0:$((max-3))}..."
    else
        echo "$text"
    fi
}

update_cover() {
    local art_url="$1"
    local status="$2"
    local last_url=""
    [[ -f "$URL_CACHE" ]] && last_url=$(cat "$URL_CACHE" 2>/dev/null)

    if [[ -z "$status" || -z "$art_url" ]]; then
        if [[ "$last_url" != "default" || ! -f "$COVER_CACHE" ]]; then
            echo "default" > "$URL_CACHE"
            if [[ -f "$DEFAULT_COVER" ]]; then
                cp "$DEFAULT_COVER" "$COVER_CACHE" 2>/dev/null
            fi
        fi
        return 0
    fi

    if [[ "$art_url" == "$last_url" && -f "$COVER_CACHE" ]]; then
        return 0
    fi

    echo "$art_url" > "$URL_CACHE"

    local raw_image="/tmp/conky_raw_art"
    if [[ "$art_url" =~ ^file:// ]]; then
        local file_path="${art_url#file://}"
        file_path=$(python3 -c "import urllib.parse, sys; print(urllib.parse.unquote(sys.argv[1]))" "$file_path" 2>/dev/null || echo "$file_path")
        if [[ -f "$file_path" ]]; then
            raw_image="$file_path"
        else
            [[ -f "$DEFAULT_COVER" ]] && cp "$DEFAULT_COVER" "$COVER_CACHE" 2>/dev/null
            return 0
        fi
    elif [[ "$art_url" =~ ^https?:// ]]; then
        if ! curl -s -m 2 -o "$raw_image" "$art_url"; then
            [[ -f "$DEFAULT_COVER" ]] && cp "$DEFAULT_COVER" "$COVER_CACHE" 2>/dev/null
            return 0
        fi
    else
        [[ -f "$DEFAULT_COVER" ]] && cp "$DEFAULT_COVER" "$COVER_CACHE" 2>/dev/null
        return 0
    fi

    if command -v magick >/dev/null 2>&1; then
        magick "$raw_image" -resize 72x72^ -gravity center -extent 72x72 \
            \( -size 72x72 xc:none -draw "roundrectangle 0,0,72,72,8,8" \) \
            -compose DstIn -composite "$COVER_CACHE" 2>/dev/null
    elif command -v convert >/dev/null 2>&1; then
        convert "$raw_image" -resize 72x72^ -gravity center -extent 72x72 \
            \( -size 72x72 xc:none -draw "roundrectangle 0,0,72,72,8,8" \) \
            -compose DstIn -composite "$COVER_CACHE" 2>/dev/null
    else
        cp "$raw_image" "$COVER_CACHE" 2>/dev/null
    fi
}

refresh_data() {
    local now
    now=$(date +%s)
    local cache_time=0
    [[ -f "$STATE_CACHE" ]] && cache_time=$(stat -c %Y "$STATE_CACHE" 2>/dev/null || echo 0)

    if (( now - cache_time < 1 )) && [[ -f "$STATE_CACHE" ]]; then
        source "$STATE_CACHE" 2>/dev/null && return 0
    fi

    PCTL_STATUS=$(playerctl $PLAYER_ARG status 2>/dev/null || echo "")

    if [[ -z "$PCTL_STATUS" ]]; then
        PCTL_ARTIST="Media Player"
        PCTL_TITLE="No music playing"
        PCTL_ALBUM=""
        PCTL_TIME="Idle"
        PCTL_ICON="$ICON_NONE"
        PCTL_ARTURL=""
        PCTL_PERC="0"
    else
        case "$PCTL_STATUS" in
            "Playing") PCTL_ICON="$ICON_PLAYING" ;;
            "Paused")  PCTL_ICON="$ICON_PAUSED" ;;
            "Stopped") PCTL_ICON="$ICON_STOPPED" ;;
            *)         PCTL_ICON="$ICON_UNKNOWN" ;;
        esac

        local raw_artist raw_title raw_album
        raw_artist=$(playerctl $PLAYER_ARG metadata xesam:artist 2>/dev/null)
        raw_title=$(playerctl $PLAYER_ARG metadata xesam:title 2>/dev/null)
        raw_album=$(playerctl $PLAYER_ARG metadata xesam:album 2>/dev/null)
        PCTL_ARTURL=$(playerctl $PLAYER_ARG metadata mpris:artUrl 2>/dev/null)

        # Smart artist/title resolution (e.g. YouTube or web streams without xesam:artist)
        if [[ -z "$raw_artist" && -n "$raw_title" ]]; then
            if [[ "$raw_title" == *" • "* ]]; then
                raw_artist="${raw_title#* • }"
                raw_title="${raw_title%% • *}"
            elif [[ "$raw_title" == *" - "* ]]; then
                raw_artist="${raw_title%% - *}"
                raw_title="${raw_title#* - }"
            else
                raw_artist="Unknown Artist"
            fi
        fi

        # Clean up common YouTube video title suffixes
        raw_title=$(echo "$raw_title" | sed -E 's/ *\([Oo]fficial[^\)]*\)//g; s/ *\[[Oo]fficial[^\]]*\]//g')

        PCTL_ARTIST=$(truncate_text "${raw_artist:-Unknown Artist}")
        PCTL_TITLE=$(truncate_text "${raw_title:-Unknown Title}")
        PCTL_ALBUM=$(truncate_text "${raw_album:-}")

        local pos_raw len_raw
        pos_raw=$(playerctl $PLAYER_ARG position 2>/dev/null)
        len_raw=$(playerctl $PLAYER_ARG metadata mpris:length 2>/dev/null)

        local pos len
        pos=$(playerctl $PLAYER_ARG position --format "{{ duration(position) }}" 2>/dev/null)
        len=$(playerctl $PLAYER_ARG metadata --format "{{ duration(mpris:length) }}" 2>/dev/null)
        if [[ -n "$len" && "$len" != "0:00" ]]; then
            PCTL_TIME="$pos / $len"
        elif [[ -n "$pos" ]]; then
            PCTL_TIME="$pos"
        else
            PCTL_TIME=""
        fi

        if [[ -n "$pos_raw" && -n "$len_raw" && "$len_raw" -gt 0 ]]; then
            PCTL_PERC=$(awk -v p="$pos_raw" -v l="$len_raw" 'BEGIN {
                if (l > 0) {
                    val = (p * 1000000.0 / l) * 100.0;
                    if (val > 100) val = 100;
                    if (val < 0) val = 0;
                    printf "%.1f", val;
                } else {
                    print 0;
                }
            }')
        else
            PCTL_PERC="0"
        fi
    fi

    # Save to state cache
    cat << CACHE_EOF > "$STATE_CACHE"
PCTL_STATUS=$(printf '%q' "$PCTL_STATUS")
PCTL_ARTIST=$(printf '%q' "$PCTL_ARTIST")
PCTL_TITLE=$(printf '%q' "$PCTL_TITLE")
PCTL_ALBUM=$(printf '%q' "$PCTL_ALBUM")
PCTL_TIME=$(printf '%q' "$PCTL_TIME")
PCTL_ICON=$(printf '%q' "$PCTL_ICON")
PCTL_ARTURL=$(printf '%q' "$PCTL_ARTURL")
PCTL_PERC=$(printf '%q' "$PCTL_PERC")
CACHE_EOF

    update_cover "$PCTL_ARTURL" "$PCTL_STATUS"
}

refresh_data

case "$1" in
    -a) echo "$PCTL_ARTIST" ;;
    -t) echo "$PCTL_TITLE" ;;
    -l) echo "$PCTL_ALBUM" ;;
    -p) echo "$PCTL_TIME" ;;
    -i) echo "$PCTL_ICON" ;;
    -s) echo "$PCTL_STATUS" ;;
    -perc|--percent) echo "$PCTL_PERC" ;;
    -c|--cover) echo "$COVER_CACHE" ;;
    *)
        echo "Usage: $0 -a (artist) | -t (title) | -l (album) | -p (position) | -i (icon) | -s (status) | -perc (percent) | -c (cover)"
        exit 1
        ;;
esac

exit 0

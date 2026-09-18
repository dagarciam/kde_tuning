#!/bin/bash

# Enhanced playerctl info script for Conky Mimosa media widget
# Supports album art caching, multi-player priority, clean title/artist parsing,
# Spotify Canvas loop filtering, and progress percentage for Android Auto style wavy seekbar

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$(cd "$SCRIPT_DIR/../assets" 2>/dev/null && pwd)"
[[ ! -d "$ASSETS_DIR" ]] && ASSETS_DIR="$HOME/.config/conky/Mimosa/assets"

COVER_CACHE="/tmp/conky_cover.png"
URL_CACHE="/tmp/conky_current_arturl"
STATE_CACHE="/tmp/conky_media_state"
DEFAULT_COVER="$ASSETS_DIR/default_cover.png"

# Python interpreter selection (prefer project virtual environment)
PY_BIN=""
if [[ -x "$SCRIPT_DIR/../../../.venv/bin/python" ]]; then
    PY_BIN="$SCRIPT_DIR/../../../.venv/bin/python"
elif [[ -x "$HOME/vscode/kde_tuning/.venv/bin/python" ]]; then
    PY_BIN="$HOME/vscode/kde_tuning/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
    PY_BIN="python3"
fi

# Player priority: standalone music apps first, then native browser MPRIS, then plasma-browser-integration
PLAYER_ARG="--player=spotify,cider,elisa,strawberry,vlc,mpd,audacious,deadbeef,rhythmbox,chromium,google-chrome,chrome,brave,firefox,microsoft-edge,opera,vivaldi,plasma-browser-integration,%any"

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

    # When status is empty or stopped
    if [[ -z "$status" || "$status" == "Stopped" ]]; then
        local empty_count=0
        local count_file="/tmp/conky_empty_status_count"
        [[ -f "$count_file" ]] && empty_count=$(cat "$count_file" 2>/dev/null || echo 0)
        empty_count=$((empty_count + 1))
        echo "$empty_count" > "$count_file"

        # Only reset to default cover if stopped/empty for at least 2 consecutive seconds
        # This prevents brief track-change transitions from flashing the default cover
        if (( empty_count >= 2 )); then
            if [[ "$last_url" != "default" || ! -f "$COVER_CACHE" ]]; then
                echo "default" > "$URL_CACHE"
                [[ -f "$DEFAULT_COVER" ]] && cp "$DEFAULT_COVER" "$COVER_CACHE" 2>/dev/null
            fi
        fi
        return 0
    fi
    rm -f /tmp/conky_empty_status_count 2>/dev/null

    # If art_url is missing during playback, keep the existing cover rather than wiping it
    if [[ -z "$art_url" ]]; then
        if [[ ! -f "$COVER_CACHE" ]]; then
            echo "default" > "$URL_CACHE"
            [[ -f "$DEFAULT_COVER" ]] && cp "$DEFAULT_COVER" "$COVER_CACHE" 2>/dev/null
        fi
        return 0
    fi

    # If already cached successfully, avoid redundant disk writes
    if [[ "$art_url" == "$last_url" && -f "$COVER_CACHE" ]]; then
        return 0
    fi

    local raw_image="/tmp/conky_raw_art"
    local download_ok=0

    if [[ "$art_url" =~ ^file:// ]]; then
        local file_path="${art_url#file://}"
        if [[ -n "$PY_BIN" ]]; then
            file_path=$($PY_BIN -c "import urllib.parse, sys; print(urllib.parse.unquote(sys.argv[1]))" "$file_path" 2>/dev/null || printf '%b' "${file_path//%/\\x}")
        else
            file_path=$(printf '%b' "${file_path//%/\\x}")
        fi
        if [[ -f "$file_path" ]]; then
            cp "$file_path" "$raw_image" 2>/dev/null && download_ok=1
        fi
    elif [[ "$art_url" =~ ^https?:// ]]; then
        if curl -s -m 3 -o "$raw_image" "$art_url" 2>/dev/null; then
            [[ -s "$raw_image" ]] && download_ok=1
        fi
    fi

    if (( download_ok == 1 )); then
        # Successfully retrieved art: process rounded rectangle and save to COVER_CACHE
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
        # Only record art_url in URL_CACHE after successful generation
        echo "$art_url" > "$URL_CACHE"
    else
        # If retrieval failed (e.g. file still being written or slow download during track skip),
        # DO NOT record art_url in URL_CACHE so next tick retries immediately.
        if [[ ! -f "$COVER_CACHE" ]]; then
            echo "default" > "$URL_CACHE"
            [[ -f "$DEFAULT_COVER" ]] && cp "$DEFAULT_COVER" "$COVER_CACHE" 2>/dev/null
        fi
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

        # If artist is still unknown/empty, check if plasma-browser-integration has it
        if [[ -z "$raw_artist" || "$raw_artist" == "Unknown Artist" ]]; then
            local alt_artist
            alt_artist=$(playerctl -p plasma-browser-integration metadata xesam:artist 2>/dev/null)
            [[ -n "$alt_artist" ]] && raw_artist="$alt_artist"
        fi

        # Clean up common YouTube video title suffixes
        raw_title=$(echo "$raw_title" | sed -E 's/ *\([Oo]fficial[^\)]*\)//g; s/ *\[[Oo]fficial[^\]]*\]//g')

        # If album is empty or a URL, check if plasma-browser-integration has a clean album name
        if [[ -z "$raw_album" || "$raw_album" =~ ^https?:// ]]; then
            local alt_album
            alt_album=$(playerctl -p plasma-browser-integration metadata xesam:album 2>/dev/null)
            [[ -n "$alt_album" && ! "$alt_album" =~ ^https?:// ]] && raw_album="$alt_album"
        fi

        PCTL_ARTIST=$(truncate_text "${raw_artist:-Unknown Artist}")
        PCTL_TITLE=$(truncate_text "${raw_title:-Unknown Title}")
        PCTL_ALBUM=$(truncate_text "${raw_album:-}")

        # Fallback for art URL if primary player (e.g. Chromium native MPRIS) omits it
        if [[ -z "$PCTL_ARTURL" ]]; then
            PCTL_ARTURL=$(playerctl -p plasma-browser-integration metadata mpris:artUrl 2>/dev/null)
        fi

        # Spotify Web High-Res Album Art Detection:
        # If playing on Spotify Web, extract real album art from Open Graph tags instead of 32x32 favicon
        local spotify_url
        spotify_url=$(playerctl -p plasma-browser-integration metadata xesam:url 2>/dev/null)
        if [[ "$spotify_url" =~ ^https://open\.spotify\.com/ ]]; then
            local spotify_cache_url="/tmp/conky_spotify_url"
            local spotify_cache_art="/tmp/conky_spotify_art"
            local last_sp_url=""
            [[ -f "$spotify_cache_url" ]] && last_sp_url=$(cat "$spotify_cache_url" 2>/dev/null)

            if [[ "$spotify_url" == "$last_sp_url" && -s "$spotify_cache_art" ]]; then
                PCTL_ARTURL=$(cat "$spotify_cache_art" 2>/dev/null)
            else
                local fetched_art
                fetched_art=$(curl -s -m 1.5 -L "$spotify_url" 2>/dev/null | grep -o 'https://i\.scdn\.co/image/[a-zA-Z0-9]*' | head -n 1)
                if [[ -n "$fetched_art" ]]; then
                    echo "$spotify_url" > "$spotify_cache_url"
                    echo "$fetched_art" > "$spotify_cache_art"
                    PCTL_ARTURL="$fetched_art"
                fi
            fi
        fi

        local pos_raw len_raw
        pos_raw=$(playerctl $PLAYER_ARG position 2>/dev/null)
        len_raw=$(playerctl $PLAYER_ARG metadata mpris:length 2>/dev/null)

        local pos len
        pos=$(playerctl $PLAYER_ARG position --format "{{ duration(position) }}" 2>/dev/null)
        len=$(playerctl $PLAYER_ARG metadata --format "{{ duration(mpris:length) }}" 2>/dev/null)

        # Anti-Canvas Loop / Short Video Filter:
        # If length is <= 12 seconds (typical of Spotify Canvas video loop or short preview),
        # inspect other running players for the real audio track length.
        if [[ -n "$len_raw" && "$len_raw" -gt 0 && "$len_raw" -le 12000000 ]]; then
            for alt_p in $(playerctl --list-all 2>/dev/null); do
                local alt_len
                alt_len=$(playerctl -p "$alt_p" metadata mpris:length 2>/dev/null)
                if [[ -n "$alt_len" && "$alt_len" -gt 12000000 ]]; then
                    len_raw="$alt_len"
                    pos_raw=$(playerctl -p "$alt_p" position 2>/dev/null)
                    pos=$(playerctl -p "$alt_p" position --format "{{ duration(position) }}" 2>/dev/null)
                    len=$(playerctl -p "$alt_p" metadata --format "{{ duration(mpris:length) }}" 2>/dev/null)
                    break
                fi
            done
        fi

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

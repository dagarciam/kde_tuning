#!/bin/bash
# ==============================================================================
# lib/ini.sh - Configuration and INI file manipulation helpers
# ==============================================================================

[[ -n "${_LIB_INI_LOADED:-}" ]] && return 0
_LIB_INI_LOADED=1

set_single_line() {
    local file_path="$1"
    local match_regex="$2"
    local desired_line="$3"

    if $DRY_RUN; then
        log_dry "set line matching '$match_regex' to '$desired_line' in $file_path"
        return 0
    fi

    local tmp_file
    mkdir -p "$(dirname "$file_path")"
    touch "$file_path"
    tmp_file="$(mktemp)"
    grep -Ev "$match_regex" "$file_path" > "$tmp_file" || true
    mv "$tmp_file" "$file_path"
    printf '%s\n' "$desired_line" >> "$file_path"
}

set_ini_key() {
    local file_path="$1"
    local section="$2"
    local key="$3"
    local value="$4"

    if $DRY_RUN; then
        log_dry "set [$section] $key=$value in $file_path"
        return 0
    fi

    local tmp_file
    mkdir -p "$(dirname "$file_path")"
    touch "$file_path"
    tmp_file="$(mktemp)"

    awk -v section="$section" -v key="$key" -v value="$value" '
        BEGIN {
            in_section = 0
            section_found = 0
            key_written = 0
        }

        /^\[.*\]$/ {
            if (in_section && !key_written) {
                print key "=" value
                key_written = 1
            }
            in_section = ($0 == "[" section "]")
            if (in_section) {
                section_found = 1
            }
            print
            next
        }

        {
            if (in_section && $0 ~ "^" key "=") {
                if (!key_written) {
                    print key "=" value
                    key_written = 1
                }
                next
            }
            print
        }

        END {
            if (in_section && !key_written) {
                print key "=" value
                key_written = 1
            }
            if (!section_found) {
                print ""
                print "[" section "]"
                print key "=" value
            }
        }
    ' "$file_path" > "$tmp_file"

    mv "$tmp_file" "$file_path"
}

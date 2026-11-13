#!/bin/bash
set -Eeuo pipefail

# ==============================================================================
# Mimosa AGS - Hardware Auto-Detection Helper
# Detects CPU topology, GPU/VRAM, battery, active network interface,
# thermal sensors, and screen resolution.
# ==============================================================================



# --- 1. CPU Name & Topology ---
RAW_CPU_NAME="$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "Unknown CPU")"
CPU_VENDOR="$(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "Unknown")"

# Clean CPU model string to fit nicely in the card header (max ~20 chars)
CLEAN_CPU_NAME="$(echo "$RAW_CPU_NAME" | sed -E \
    -e 's/\(R\)//gi' \
    -e 's/\(TM\)//gi' \
    -e 's/[0-9]+th Gen //gi' \
    -e 's/Gen Intel/Intel/gi' \
    -e 's/[0-9]+-Core Processor//gi' \
    -e 's/Processor//gi' \
    -e 's/CPU//gi' \
    -e 's/with .*//gi' \
    -e 's/w\/ .*//gi' \
    -e 's/@.*//g' \
    -e 's/^AMD //i' \
    -e 's/[[:space:]]+/ /g' \
    -e 's/^[[:space:]]+//;s/[[:space:]]+$//'
)"
CLEAN_CPU_NAME="${CLEAN_CPU_NAME^^}"
if (( ${#CLEAN_CPU_NAME} > 20 )); then
    CLEAN_CPU_NAME="${CLEAN_CPU_NAME:0:20}"
fi
[[ -z "$CLEAN_CPU_NAME" ]] && CLEAN_CPU_NAME="PROCESSOR"

LOGICAL_THREADS="$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 4)"

# Count unique physical cores via sysfs thread_siblings_list
PHYSICAL_CORES=0
SMT_CORES=0
SINGLE_CORES=0
CORE_SIBLINGS=()
if [[ -d /sys/devices/system/cpu ]]; then
    declare -A SEEN_SIBLINGS=()
    for sib_file in /sys/devices/system/cpu/cpu[0-9]*/topology/thread_siblings_list; do
        [[ -r "$sib_file" ]] || continue
        sib_val="$(tr -d '[:space:]' < "$sib_file")"
        [[ -z "$sib_val" ]] && continue
        if [[ -z "${SEEN_SIBLINGS[$sib_val]:-}" ]]; then
            SEEN_SIBLINGS[$sib_val]=1
            CORE_SIBLINGS+=("$sib_val")
            ((PHYSICAL_CORES += 1))
            if [[ "$sib_val" == *","* || "$sib_val" == *"-"* ]]; then
                ((SMT_CORES += 1))
            else
                ((SINGLE_CORES += 1))
            fi
        fi
    done
fi
(( PHYSICAL_CORES == 0 )) && PHYSICAL_CORES="$LOGICAL_THREADS"

IS_X3D="false"
[[ "${RAW_CPU_NAME^^}" == *"X3D"* ]] && IS_X3D="true"

IS_HYBRID="false"
if (( SMT_CORES > 0 && SINGLE_CORES > 0 )); then
    IS_HYBRID="true"
fi

# --- 2. Battery Detection (Laptop vs Desktop) ---
HAS_BATTERY="false"
BATTERY_DEV=""
for bat in /sys/class/power_supply/BAT*; do
    if [[ -d "$bat" ]]; then
        HAS_BATTERY="true"
        BATTERY_DEV="$(basename "$bat")"
        break
    fi
done

# --- 3. Active Network Interface ---
ACTIVE_IFACE="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}' || true)"
if [[ -z "$ACTIVE_IFACE" ]] && command -v iw &>/dev/null; then
    ACTIVE_IFACE="$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}' || true)"
fi
if [[ -z "$ACTIVE_IFACE" ]]; then
    for net_path in /sys/class/net/*; do
        iface_name="$(basename "$net_path")"
        [[ "$iface_name" == "lo" || "$iface_name" == docker* || "$iface_name" == veth* || "$iface_name" == br-* || "$iface_name" == virbr* ]] && continue
        ACTIVE_IFACE="$iface_name"
        break
    done
fi
[[ -z "$ACTIVE_IFACE" ]] && ACTIVE_IFACE="wlan0"

# --- 4. GPU & VRAM Detection ---
GPU_TYPE="igpu"
GPU_DRIVER=""
DRM_CARD_DIR=""
DRM_CARD_PATH=""
VRAM_TOTAL=0

# Prefer DRM card with the largest dedicated VRAM (dGPU over iGPU)
for card_dir in /sys/class/drm/card[0-9]; do
    [[ -d "$card_dir/device" ]] || continue
    vram_file="$card_dir/device/mem_info_vram_total"
    if [[ -r "$vram_file" ]]; then
        card_vram="$(cat "$vram_file" 2>/dev/null || echo 0)"
        if (( card_vram > VRAM_TOTAL )); then
            VRAM_TOTAL="$card_vram"
            DRM_CARD_DIR="$card_dir"
            DRM_CARD_PATH="$card_dir/device"
            GPU_DRIVER="amdgpu"
        fi
    fi
done

# If no AMD VRAM sysfs found, check for NVIDIA or Intel DRM card
if [[ -z "$DRM_CARD_PATH" ]]; then
    if command -v nvidia-smi &>/dev/null && lspci 2>/dev/null | grep -qi "nvidia"; then
        GPU_DRIVER="nvidia"
        GPU_TYPE="dgpu"
    else
        for card_dir in /sys/class/drm/card[0-9]; do
            if [[ -d "$card_dir/device" ]]; then
                DRM_CARD_DIR="$card_dir"
                DRM_CARD_PATH="$card_dir/device"
                GPU_DRIVER="intel"
                break
            fi
        done
    fi
else
    # If VRAM > 2 GB, classify as dedicated GPU (or high-carveout APU)
    if (( VRAM_TOTAL > 2147483648 )); then
        GPU_TYPE="dgpu"
    fi
fi

# --- 5. Thermal Sensors (CPU & GPU hwmon paths) ---
CPU_TEMP_PATH=""
FALLBACK_TEMP_PATH=""
GPU_TEMP_PATH=""

for hw in /sys/class/hwmon/hwmon*; do
    [[ -r "$hw/name" ]] || continue
    hw_name="$(cat "$hw/name" 2>/dev/null || true)"
    case "$hw_name" in
        k10temp|zenpower|coretemp|cpu_thermal)
            if [[ -z "$CPU_TEMP_PATH" ]]; then
                for lbl_file in "$hw"/temp*_label; do
                    [[ -r "$lbl_file" ]] || continue
                    lbl_txt="$(cat "$lbl_file" 2>/dev/null || true)"
                    if [[ "$lbl_txt" =~ (Tctl|Tdie|Package|CPU) ]]; then
                        candidate="${lbl_file%_label}_input"
                        if [[ -r "$candidate" ]]; then
                            CPU_TEMP_PATH="$candidate"
                            break
                        fi
                    fi
                done
                [[ -z "$CPU_TEMP_PATH" && -r "$hw/temp1_input" ]] && CPU_TEMP_PATH="$hw/temp1_input"
            fi
            ;;
        thinkpad|asus*|acpitz|dell_smm)
            if [[ -z "$FALLBACK_TEMP_PATH" && -r "$hw/temp1_input" ]]; then
                FALLBACK_TEMP_PATH="$hw/temp1_input"
            fi
            ;;
        amdgpu|radeon|nouveau)
            if [[ -z "$GPU_TEMP_PATH" && -r "$hw/temp1_input" ]]; then
                GPU_TEMP_PATH="$hw/temp1_input"
            fi
            ;;
    esac
done

[[ -z "$CPU_TEMP_PATH" ]] && CPU_TEMP_PATH="$FALLBACK_TEMP_PATH"

if [[ -z "$CPU_TEMP_PATH" ]]; then
    for tz in /sys/class/thermal/thermal_zone*/temp; do
        if [[ -r "$tz" ]]; then
            CPU_TEMP_PATH="$tz"
            break
        fi
    done
fi
[[ -z "$GPU_TEMP_PATH" ]] && GPU_TEMP_PATH="${FALLBACK_TEMP_PATH:-$CPU_TEMP_PATH}"

# --- Output: JSON hardware profile on stdout (consumed by the AGS widget) ---
json_str() { printf "%s" "$1" | sed -e "s/\\\\/\\\\\\\\/g" -e "s/\"/\\\\\"/g"; }
cat <<JSON
{
  "cpu_name": "$(json_str "$CLEAN_CPU_NAME")",
  "core_siblings": [$(printf "\"%s\"\n" "${CORE_SIBLINGS[@]}" | paste -sd, -)],
  "cpu_vendor": "$(json_str "$CPU_VENDOR")",
  "physical_cores": ${PHYSICAL_CORES},
  "logical_threads": ${LOGICAL_THREADS},
  "is_x3d": ${IS_X3D},
  "is_hybrid": ${IS_HYBRID},
  "has_battery": ${HAS_BATTERY},
  "battery_dev": "$(json_str "$BATTERY_DEV")",
  "active_iface": "$(json_str "$ACTIVE_IFACE")",
  "gpu_type": "${GPU_TYPE}",
  "gpu_driver": "${GPU_DRIVER}",
  "drm_card_path": "$(json_str "$DRM_CARD_PATH")",
  "vram_total": ${VRAM_TOTAL},
  "cpu_temp_path": "$(json_str "$CPU_TEMP_PATH")",
  "gpu_temp_path": "$(json_str "$GPU_TEMP_PATH")"
}
JSON

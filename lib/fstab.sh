#!/bin/bash
# ==============================================================================
# lib/fstab.sh - Persistent secondary storage volume automounts (/etc/fstab)
# ==============================================================================

[[ -n "${_LIB_FSTAB_LOADED:-}" ]] && return 0
_LIB_FSTAB_LOADED=1

setup_fstab() {
    log_progress "$1" "$2" "Configuring storage volumes in /etc/fstab"

    # Target storage volumes: LABEL:MOUNTPOINT:FALLBACK_UUID
    local targets=(
        "Documentos:/documentos:6FFB75110F2D5860"
        "Juegos:/juegos:D8E8581CE857F6EA"
        "Personal:/personal:6F520EBC0641B2F4"
    )

    local user_uid
    local user_gid
    user_uid="$(id -u "$REAL_USER")"
    user_gid="$(id -g "$REAL_USER")"

    local fstab_file="/etc/fstab"
    local fstab_modified=false
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_file="/etc/fstab.bak-${timestamp}"

    ensure_file "$fstab_file"

    for entry in "${targets[@]}"; do
        IFS=':' read -r label mountpoint fallback_uuid <<< "$entry"

        local uuid=""
        local fstype=""
        local dev_node=""

        if command -v findfs &>/dev/null; then
            dev_node="$(findfs LABEL="$label" 2>/dev/null || true)"
        fi

        if [[ -n "$dev_node" ]]; then
            uuid="$(lsblk -no UUID "$dev_node" 2>/dev/null | head -1 || true)"
            fstype="$(lsblk -no FSTYPE "$dev_node" 2>/dev/null | head -1 || true)"
        fi

        # Fallback to UUID matching if label lookup yielded nothing
        if [[ -z "$uuid" && -n "$fallback_uuid" ]]; then
            if lsblk -no UUID 2>/dev/null | grep -qx "$fallback_uuid"; then
                uuid="$fallback_uuid"
                fstype="$(lsblk -rn -o UUID,FSTYPE 2>/dev/null | awk -v u="$uuid" '$1 == u {print $2; exit}')"
            fi
        fi

        if [[ -z "$uuid" ]]; then
            log_warn "Volume '$label' not detected on this system. Skipping."
            continue
        fi

        [[ -z "$fstype" ]] && fstype="ntfs"
        local mount_fs="$fstype"
        [[ "$fstype" == "ntfs3" ]] && mount_fs="ntfs"

        local mount_opts="defaults,nofail"
        if [[ "$mount_fs" == "ntfs" || "$mount_fs" == "vfat" || "$mount_fs" == "exfat" ]]; then
            mount_opts="defaults,nofail,uid=${user_uid},gid=${user_gid},x-systemd.device-timeout=10s"
        fi

        # Check if already in /etc/fstab by UUID or mount point
        if grep -qE "UUID=${uuid}" "$fstab_file" 2>/dev/null || awk -v m="$mountpoint" '$2 == m' "$fstab_file" 2>/dev/null | grep -q .; then
            log_ok "Mount $mountpoint (UUID=$uuid) already configured in $fstab_file"
            if $DRY_RUN; then
                log_dry "Ensure mount directory exists: $mountpoint"
            else
                if [[ ! -d "$mountpoint" ]]; then
                    run_as_root mkdir -p "$mountpoint"
                    run_as_root chown "${user_uid}:${user_gid}" "$mountpoint"
                fi
            fi
            continue
        fi

        local fstab_line="UUID=${uuid}  ${mountpoint}  ${mount_fs}  ${mount_opts}  0  0"

        if $DRY_RUN; then
            if ! $fstab_modified; then
                log_dry "Would backup $fstab_file to $backup_file"
                fstab_modified=true
            fi
            log_dry "Would create directory: $mountpoint"
            log_dry "Would add entry to $fstab_file: $fstab_line"
            log_dry "Would run: systemctl daemon-reload && mount $mountpoint"
        else
            if ! $fstab_modified; then
                log_info "Creating backup of $fstab_file at $backup_file..."
                run_as_root cp "$fstab_file" "$backup_file"
                run_as_root cp "$fstab_file" "/etc/fstab.bak"
                fstab_modified=true
            fi

            run_as_root mkdir -p "$mountpoint"
            run_as_root chown "${user_uid}:${user_gid}" "$mountpoint"

            log_info "Adding $label to $fstab_file ($mountpoint)..."
            printf '%s\n' "$fstab_line" | run_as_root tee -a "$fstab_file" > /dev/null

            log_ok "Added $label ($mountpoint) to $fstab_file"
        fi
    done

    if ! $DRY_RUN && $fstab_modified; then
        log_info "Reloading systemd daemon to recognize new mount points..."
        run_as_root systemctl daemon-reload

        for entry in "${targets[@]}"; do
            IFS=':' read -r label mountpoint fallback_uuid <<< "$entry"
            if grep -q " ${mountpoint} " "$fstab_file" 2>/dev/null; then
                if ! findmnt -M "$mountpoint" &>/dev/null; then
                    for current_run_media in "/run/media/${REAL_USER}/${label}" "/media/${REAL_USER}/${label}"; do
                        if findmnt -M "$current_run_media" &>/dev/null; then
                            log_info "Unmounting temporary mount at $current_run_media..."
                            run_as_root umount "$current_run_media" 2>/dev/null || log_warn "Could not unmount $current_run_media (may be in use)."
                        fi
                    done

                    if run_as_root mount "$mountpoint" 2>/dev/null; then
                        log_ok "Successfully mounted $mountpoint"
                    else
                        log_warn "Could not mount $mountpoint immediately (device may be busy). It will mount automatically on next reboot."
                    fi
                else
                    log_ok "$mountpoint is already mounted"
                fi
            fi
        done
    fi

    log_ok "fstab configuration completed"
}

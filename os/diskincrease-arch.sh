#!/bin/bash

set -Eeuo pipefail

trap 'echo "[ERROR] Command \"${BASH_COMMAND}\" failed on line ${LINENO}."; exit 1' ERR

###############################################################################
# Logging
###############################################################################

log() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1"
    exit 1
}

###############################################################################
# Root Check
###############################################################################

check_root() {
    [[ $EUID -eq 0 ]] || error "Please run this script as root."
}

###############################################################################
# OS Check
###############################################################################

check_os() {

    source /etc/os-release

    [[ "$ID" == "arch" ]] || \
        error "This script supports Arch Linux only."
}

###############################################################################
# Install Requirements
###############################################################################

install_requirements() {

    log "Refreshing package database..."

    pacman -Sy --noconfirm

    local packages=(
        cloud-utils
        lvm2
        parted
    )

    for pkg in "${packages[@]}"; do

        if ! pacman -Q "$pkg" >/dev/null 2>&1; then

            log "Installing $pkg..."

            pacman -S --noconfirm "$pkg"

        fi

    done

    local commands=(
        growpart
        pvresize
        lvextend
        resize2fs
        lsblk
        findmnt
        pvs
        vgs
        lvs
        partprobe
        udevadm
    )

    for cmd in "${commands[@]}"; do

        command -v "$cmd" >/dev/null 2>&1 || \
            error "Missing command: $cmd"

    done
}

###############################################################################
# Detect Storage
###############################################################################

get_storage_info() {

    ROOT_LV=$(findmnt -n -o SOURCE /)

    VG=$(lvs --noheadings -o vg_name "$ROOT_LV" | xargs)

    PV=$(pvs --noheadings -o pv_name --select vg_name="$VG" | head -1 | xargs)

    DISK="/dev/$(lsblk -dn -o PKNAME "$PV" | xargs)"

    DEVICE=$(basename "$PV")

    if [[ "$DEVICE" =~ ^nvme[0-9]+n[0-9]+p([0-9]+)$ ]]; then
        PARTITION="${BASH_REMATCH[1]}"
    elif [[ "$DEVICE" =~ ^[a-z]+([0-9]+)$ ]]; then
        PARTITION="${BASH_REMATCH[1]}"
    else
        error "Unable to determine partition number."
    fi

    log "Root LV : $ROOT_LV"
    log "VG      : $VG"
    log "PV      : $PV"
    log "Disk    : $DISK"
    log "Part    : $PARTITION"
}

###############################################################################
# Rescan Disk
###############################################################################

rescan_disk() {

    log "Rescanning disk..."

    echo 1 > "/sys/class/block/$(basename "$DISK")/device/rescan"

    partprobe "$DISK"

    udevadm settle

    sleep 2
}

###############################################################################
# Grow Partition
###############################################################################

grow_partition() {

    log "Growing partition..."

    OUTPUT=$(growpart "$DISK" "$PARTITION" 2>&1 || true)

    echo "$OUTPUT"

    if echo "$OUTPUT" | grep -q "NOCHANGE"; then
        log "Partition already occupies all available space."
    fi

    partprobe "$DISK"

    udevadm settle

    sleep 2
}

###############################################################################
# Resize Physical Volume
###############################################################################

resize_pv() {

    log "Resizing Physical Volume..."

    pvresize "$PV"
}

###############################################################################
# Extend Logical Volume
###############################################################################

extend_lv() {

    FREE=$(vgs --noheadings -o vg_free_count "$VG" | xargs)

    if [[ "$FREE" == "0" ]]; then

        log "No free extents available."

        return

    fi

    log "Extending Logical Volume..."

    lvextend -l +100%FREE "$ROOT_LV"
}

###############################################################################
# Resize ext4
###############################################################################

resize_filesystem() {

    log "Growing ext4 filesystem..."

    resize2fs "$ROOT_LV"
}

###############################################################################
# Verify
###############################################################################

verify() {

    echo

    echo "========================================"

    echo "Disk extension completed successfully"

    echo "========================================"

    echo

    df -h /

    echo

    pvs

    echo

    vgs

    echo

    lvs

    echo

    lsblk
}

###############################################################################
# Main
###############################################################################

main() {

    check_root

    check_os

    install_requirements

    get_storage_info

    rescan_disk

    grow_partition

    resize_pv

    extend_lv

    resize_filesystem

    #verify

    log "Done."
}

main "$@"
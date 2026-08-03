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
# Install Requirements
###############################################################################

install_requirements() {

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq

    apt-get install -y \
        cloud-guest-utils \
        lvm2 \
        parted
}

###############################################################################
# Detect Storage
###############################################################################

get_storage_info() {

    ROOT_LV=$(findmnt -n -o SOURCE /)

    VG=$(lvs --noheadings -o vg_name "$ROOT_LV" | xargs)

    PV=$(pvs --noheadings -o pv_name --select vg_name="$VG" | head -1 | xargs)

    DISK="/dev/$(lsblk -dn -o PKNAME "$PV" | xargs)"

    FILESYSTEM=$(findmnt -n -o FSTYPE /)

    log "Root LV       : $ROOT_LV"
    log "VG            : $VG"
    log "PV            : $PV"
    log "Disk          : $DISK"
    log "Filesystem    : $FILESYSTEM"
}

###############################################################################
# Rescan
###############################################################################

rescan_disk() {

    log "Rescanning disk..."

    echo 1 > "/sys/class/block/$(basename "$DISK")/device/rescan"

    partprobe "$DISK"

    udevadm settle

    sleep 2
}

###############################################################################
# Grow Extended Partition
###############################################################################

grow_extended() {

    log "Growing extended partition..."

    OUTPUT=$(growpart "$DISK" 2 2>&1 || true)

    echo "$OUTPUT"

    partprobe "$DISK"

    udevadm settle

    sleep 2
}

###############################################################################
# Grow Logical Partition
###############################################################################

grow_logical() {

    log "Growing logical partition..."

    OUTPUT=$(growpart "$DISK" 5 2>&1 || true)

    echo "$OUTPUT"

    partprobe "$DISK"

    udevadm settle

    sleep 2
}

###############################################################################
# Resize PV
###############################################################################

resize_pv() {

    log "Resizing Physical Volume..."

    pvresize "$PV"
}

###############################################################################
# Extend LV
###############################################################################

extend_lv() {

    log "Extending Logical Volume..."

    lvextend -l +100%FREE "$ROOT_LV"
}

###############################################################################
# Resize Filesystem
###############################################################################

resize_fs() {

    log "Growing filesystem..."

    resize2fs "$ROOT_LV"
}

###############################################################################
# Verify
###############################################################################

verify() {

    echo
    echo "====================================="
    echo "Resize completed"
    echo "====================================="

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

    install_requirements

    get_storage_info

    rescan_disk

    grow_extended

    grow_logical

    resize_pv

    extend_lv

    resize_fs

    #verify

    log "Disk extension completed successfully."
}

main "$@"
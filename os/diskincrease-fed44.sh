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

    log "Updating package metadata..."

    dnf -y makecache

    local packages=(
        cloud-utils-growpart
        lvm2
        parted
        xfsprogs
        util-linux
    )

    for pkg in "${packages[@]}"; do

        if ! rpm -q "$pkg" >/dev/null 2>&1; then

            log "Installing $pkg..."

            dnf install -y "$pkg"

        fi

    done

    local commands=(
        growpart
        pvresize
        lvextend
        xfs_growfs
        parted
        partprobe
        lsblk
        findmnt
        pvs
        vgs
        lvs
        udevadm
    )

    for cmd in "${commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || \
            error "$cmd is missing."
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
# Remove placeholder partition
###############################################################################

remove_placeholder() {

    if lsblk "${DISK}4" >/dev/null 2>&1; then

        SIZE=$(blockdev --getsize64 "${DISK}4")

        if [ "$SIZE" -le 4096 ]; then

            log "Removing 512-byte placeholder partition..."

            parted -s "$DISK" rm 4

            partprobe "$DISK"

            udevadm settle

            sleep 2

        fi

    fi
}

###############################################################################
# Grow partition
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

    FREE=$(vgs --noheadings -o vg_free_count "$VG" | xargs)

    if [ "$FREE" = "0" ]; then
        log "No free space available inside Volume Group."
        return
    fi

    log "Extending Logical Volume..."

    lvextend -l +100%FREE "$ROOT_LV"
}

###############################################################################
# Grow filesystem
###############################################################################

grow_fs() {

    log "Growing XFS filesystem..."

    xfs_growfs /
}

###############################################################################
# Verify
###############################################################################

verify() {

    echo

    echo "=============================="

    echo "Resize Finished"

    echo "=============================="

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

    remove_placeholder

    grow_partition

    resize_pv

    extend_lv

    grow_fs

    #verify

    log "Done."
}

main "$@"
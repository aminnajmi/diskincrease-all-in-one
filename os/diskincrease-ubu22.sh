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
# Checks
###############################################################################

check_root() {
    [[ $EUID -eq 0 ]] || error "Please run this script as root."
}

check_dependencies() {

    local deps=(
        lsblk
        findmnt
        growpart
        resize2fs
        partprobe
        udevadm
    )

    for cmd in "${deps[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || \
            error "Missing dependency: $cmd"
    done
}

###############################################################################
# Detect storage
###############################################################################

get_storage_info() {

    ROOT_PARTITION=$(findmnt -n -o SOURCE /)

    DEVICE=$(basename "$ROOT_PARTITION")

    DISK="/dev/$(lsblk -ndo PKNAME "$ROOT_PARTITION" | xargs)"

    if [[ "$DEVICE" =~ ^nvme[0-9]+n[0-9]+p([0-9]+)$ ]]; then
        PARTITION_NUMBER="${BASH_REMATCH[1]}"
    elif [[ "$DEVICE" =~ ^[a-z]+([0-9]+)$ ]]; then
        PARTITION_NUMBER="${BASH_REMATCH[1]}"
    else
        error "Unable to determine partition number."
    fi

    FILESYSTEM=$(findmnt -n -o FSTYPE /)

    log "Root Partition : $ROOT_PARTITION"
    log "Disk           : $DISK"
    log "Partition      : $PARTITION_NUMBER"
    log "Filesystem     : $FILESYSTEM"
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
# Grow partition
###############################################################################

grow_partition() {

    log "Growing partition..."

    OUTPUT=$(growpart "$DISK" "$PARTITION_NUMBER" 2>&1 || true)

    echo "$OUTPUT"

    if echo "$OUTPUT" | grep -q "NOCHANGE"; then
        log "Partition already occupies all available space."
        return
    fi

    partprobe "$DISK"

    udevadm settle
}

###############################################################################
# Resize filesystem
###############################################################################

resize_filesystem() {

    log "Growing filesystem..."

    case "$FILESYSTEM" in

        ext2|ext3|ext4)

            resize2fs "$ROOT_PARTITION"

            ;;

        xfs)

            xfs_growfs /

            ;;

        *)

            error "Unsupported filesystem: $FILESYSTEM"

            ;;

    esac
}

###############################################################################
# Verify
###############################################################################

verify() {

    echo
    echo "========================================"
    echo "Disk resize completed successfully"
    echo "========================================"

    echo

    df -h /

    echo

    lsblk
}

###############################################################################
# Main
###############################################################################

main() {

    check_root

    check_dependencies

    get_storage_info

    rescan_disk

    grow_partition

    resize_filesystem

    #verify
}

main "$@"
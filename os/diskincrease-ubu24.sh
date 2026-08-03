#!/bin/bash

set -Eeuo pipefail

trap 'echo "[ERROR] Command \"${BASH_COMMAND}\" failed on line ${LINENO}."; exit 1' ERR

log() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1"
    exit 1
}

check_root() {
    [[ $EUID -eq 0 ]] || error "Please run this script as root."
}

check_dependencies() {
    local deps=(
        lsblk
        findmnt
        lvs
        pvs
        pvresize
        lvextend
        growpart
        partprobe
        resize2fs
        udevadm
    )

    for cmd in "${deps[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || \
            error "Missing dependency: $cmd"
    done
}

get_storage_info() {

    ROOT_LV=$(findmnt -n -o SOURCE /)

    VG=$(lvs --noheadings -o vg_name "$ROOT_LV" | xargs)

    PV=$(pvs --noheadings -o pv_name --select vg_name="$VG" | head -1 | xargs)

    DISK="/dev/$(lsblk -dn -o PKNAME "$PV" | head -1 | xargs)"

    PARTITION_NUMBER=$(lsblk -no PARTN "$PV" | head -1 | xargs)

    FILESYSTEM=$(findmnt -n -o FSTYPE /)

    log "Root LV      : $ROOT_LV"
    log "Volume Group : $VG"
    log "Physical Vol.: $PV"
    log "Disk         : $DISK"
    log "Partition    : $PARTITION_NUMBER"
    log "Filesystem   : $FILESYSTEM"
}

rescan_disk() {

    log "Rescanning disk..."

    echo 1 > "/sys/class/block/$(basename "$DISK")/device/rescan"

    partprobe "$DISK"

    udevadm settle

    sleep 2
}

grow_partition() {

    log "Checking partition..."

    OUTPUT=$(growpart "$DISK" "$PARTITION_NUMBER" 2>&1) || true

    echo "$OUTPUT"

    if echo "$OUTPUT" | grep -q "NOCHANGE"; then
        log "Partition already occupies all available disk space."
        return
    fi

    partprobe "$DISK"

    udevadm settle
}

resize_pv() {

    log "Resizing Physical Volume..."

    pvresize "$PV"
}

extend_lv() {

    FREE_PE=$(vgs --noheadings -o vg_free_count "$VG" | xargs)

    if [[ "$FREE_PE" == "0" ]]; then
        log "No free space available in the Volume Group."
        return
    fi

    log "Extending Logical Volume..."

    lvextend -l +100%FREE "$ROOT_LV"
}

resize_filesystem() {

    case "$FILESYSTEM" in
        ext2|ext3|ext4)
            resize2fs "$ROOT_LV"
            ;;
        xfs)
            xfs_growfs /
            ;;
        *)
            error "Unsupported filesystem: $FILESYSTEM"
            ;;
    esac
}

verify_resize() {

    echo
    df -h /

    echo

    pvs

    echo

    vgs

    echo

    lvs
}

main() {

    check_root

    check_dependencies

    get_storage_info

    rescan_disk

    grow_partition

    resize_pv

    extend_lv

    resize_filesystem

    #verify_resize

    log "Disk extension completed successfully."
}

main "$@"
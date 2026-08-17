#!/usr/bin/env bash
set -Eeuo pipefail

# Universal Linux disk resizer. Designed to run directly with: curl ... | sudo bash

PROGRAM_NAME='Linux Disk Resizer'
AUTO_CONFIRM=${AUTO_CONFIRM:-true}

die() {
    printf '\nERROR:\n%s\n' "$*" >&2
    exit 1
}

log() { printf '%s\n' "$*"; }
ok() { log 'OK'; }
have() { command -v "$1" >/dev/null 2>&1; }

on_error() {
    local status=$?
    printf '\nERROR:\nResize failed at line %s (exit status %s). Run with bash -x for details.\n' "$1" "$status" >&2
    exit "$status"
}
trap 'on_error $LINENO' ERR

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die 'This script must be run as root.'
}

detect_os() {
    [[ -r /etc/os-release ]] || die 'Could not read /etc/os-release.'
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_NAME=${PRETTY_NAME:-${NAME:-Unknown Linux}}
}

install_packages() {
    log 'Checking required tools...'
    local packages=()
    if have apt-get; then
        packages=(cloud-guest-utils parted lvm2 e2fsprogs xfsprogs util-linux)
        DEBIAN_FRONTEND=noninteractive apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
    elif have dnf; then
        packages=(cloud-utils-growpart parted lvm2 e2fsprogs xfsprogs util-linux)
        dnf install -y "${packages[@]}"
    elif have yum; then
        packages=(cloud-utils-growpart parted lvm2 e2fsprogs xfsprogs util-linux)
        yum install -y "${packages[@]}"
    elif have zypper; then
        packages=(cloud-utils-growpart parted lvm2 e2fsprogs xfsprogs util-linux)
        zypper --non-interactive install --no-recommends "${packages[@]}"
    elif have pacman; then
        packages=(cloud-guest-utils parted lvm2 e2fsprogs xfsprogs util-linux)
        pacman --noconfirm -S --needed "${packages[@]}"
    elif have apk; then
        packages=(cloud-utils-growpart parted lvm2 e2fsprogs xfsprogs util-linux)
        apk add --no-cache "${packages[@]}"
    else
        die 'No supported package manager found (apt, dnf, yum, zypper, pacman, apk).'
    fi

    have findmnt && have lsblk && have partprobe || die 'Required block-device tools are unavailable after package installation.'
    have growpart || have parted || die 'Neither growpart nor parted is available.'
}

detect_layout() {
    ROOT_SOURCE=$(findmnt -n -o SOURCE --target /) || die 'Could not detect root filesystem.'
    ROOT_FSTYPE=$(findmnt -n -o FSTYPE --target /) || die 'Could not detect root filesystem type.'
    ROOT_SIZE=$(findmnt -n -o SIZE --target /) || ROOT_SIZE=$(df -hP / | awk 'NR == 2 { print $2 }')
    ROOT_DEVICE=$(readlink -f "$ROOT_SOURCE")
    [[ -b $ROOT_DEVICE ]] || die "Root filesystem source is not a block device: $ROOT_SOURCE"

    ROOT_BLOCK_TYPE=$(lsblk -dn -o TYPE "$ROOT_DEVICE")
    IS_LVM=false
    LV_PATH=''
    if [[ $ROOT_BLOCK_TYPE == lvm ]]; then
        IS_LVM=true
        have lvs && have pvresize && have lvextend || die 'Root filesystem uses LVM, but LVM tools are unavailable.'
        LV_PATH=$(lvs --noheadings -o lv_path "$ROOT_DEVICE" 2>/dev/null | xargs) || die 'Could not determine root logical volume.'
        [[ -b $LV_PATH ]] || die 'Could not determine root logical volume path.'
    fi

    # A safe automatic resize requires a partition-backed root device or LVM PV.
    PARTITION=$(lsblk -s -r -n -o PATH,TYPE "$ROOT_DEVICE" | awk '$2 == "part" { print $1; exit }')
    [[ -n $PARTITION && -b $PARTITION ]] || die 'Could not find a partition backing the root filesystem. Whole-disk, RAID, encrypted, and network-root layouts require manual handling.'
    PARTITION_SIZE_BEFORE=$(lsblk -bdn -o SIZE "$PARTITION")
    PART_NUMBER=$(lsblk -dn -o PARTN "$PARTITION")
    [[ $PART_NUMBER =~ ^[0-9]+$ ]] || die "Could not determine partition number for $PARTITION"
    PARENT_NAME=$(lsblk -dn -o PKNAME "$PARTITION")
    [[ -n $PARENT_NAME ]] || die "Could not determine parent disk for $PARTITION"
    DISK=$(lsblk -dn -o PATH "/dev/$PARENT_NAME")
    [[ -b $DISK ]] || die "Could not determine parent disk for $PARTITION"

    case $ROOT_FSTYPE in
        ext2|ext3|ext4|xfs) ;;
        *) die "Unsupported filesystem: $ROOT_FSTYPE" ;;
    esac
}

confirm() {
    log ''
    log '========================================'
    log " $PROGRAM_NAME"
    log '========================================'
    log ''
    log "OS:                $OS_NAME"
    log "Root filesystem:   $ROOT_SOURCE"
    log "Filesystem:        $ROOT_FSTYPE"
    log "Current root size: $ROOT_SIZE"
    log "Detected disk:     $DISK ($(lsblk -dn -o SIZE "$DISK"))"
    log "Root partition:    $PARTITION"
    log ''

    if [[ $AUTO_CONFIRM == true ]]; then
        log 'AUTO_CONFIRM=true; continuing without a prompt.'
        return
    fi
    local answer
    read -r -p 'Continue? [y/N] ' answer
    [[ $answer =~ ^[Yy]([Ee][Ss])?$ ]] || die 'Cancelled by user.'
}

grow_partition() {
    log 'Growing partition...'
    if have growpart; then
        growpart "$DISK" "$PART_NUMBER"
    else
        parted -s "$DISK" resizepart "$PART_NUMBER" 100%
    fi
    partprobe "$DISK"
    have udevadm && udevadm settle
    PARTITION_SIZE_AFTER=$(lsblk -bdn -o SIZE "$PARTITION")
    (( PARTITION_SIZE_AFTER > PARTITION_SIZE_BEFORE )) || die 'No free space detected after partition expansion.'
    ok
}

grow_lvm() {
    [[ $IS_LVM == true ]] || return 0
    log 'Growing LVM physical volume...'
    pvresize "$PARTITION"
    log 'Growing LVM logical volume...'
    lvextend -l +100%FREE "$LV_PATH"
    ok
}

grow_filesystem() {
    log 'Growing filesystem...'
    case $ROOT_FSTYPE in
        ext2|ext3|ext4) resize2fs "$ROOT_DEVICE" ;;
        xfs) xfs_growfs / ;;
    esac
    ok
}

verify() {
    local new_size
    new_size=$(findmnt -n -o SIZE --target /)
    log ''
    log 'Disk resize completed successfully.'
    log "Final root size: $new_size"
    log ''
    df -hT /
}

main() {
    require_root
    detect_os
    install_packages
    detect_layout
    confirm
    grow_partition
    grow_lvm
    grow_filesystem
    verify
}

main "$@"

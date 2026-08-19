#!/bin/bash

###############################################################################
# VPS Disk Increase - All In One
#
# Supported:
#   Ubuntu 22
#   Ubuntu 24
#   Ubuntu 26
#   Debian 13
#   Fedora 44
#   CentOS Stream 10
#   AlmaLinux 10
#   Rocky Linux 10
#   Arch Linux
#
# WARNING:
#   This script modifies partition/LVM/filesystem layout.
#   It does NOT format existing filesystems.
###############################################################################

set -Eeuo pipefail

###############################################################################
# Globals
###############################################################################

OS_ID=""
OS_VERSION=""
OS_NAME=""

ROOT_SOURCE=""
FILESYSTEM=""

VG=""
PV=""
DISK=""
PARTITION=""

NO_RESIZE_NEEDED=0

INITIAL_DISK_BYTES=0
FINAL_DISK_BYTES=0
INITIAL_DISK=""
FINAL_DISK=""
ADDED_DISK=""
FINAL_ROOT=""

###############################################################################
# Logging
###############################################################################

log() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

###############################################################################
# Human-readable size
###############################################################################

human_size() {

    local bytes="$1"

    if (( bytes >= 1099511627776 )); then
        awk -v b="$bytes" 'BEGIN {printf "%.1fT", b/1099511627776}'

    elif (( bytes >= 1073741824 )); then
        awk -v b="$bytes" 'BEGIN {printf "%.1fG", b/1073741824}'

    elif (( bytes >= 1048576 )); then
        awk -v b="$bytes" 'BEGIN {printf "%.1fM", b/1048576}'

    elif (( bytes >= 1024 )); then
        awk -v b="$bytes" 'BEGIN {printf "%.1fK", b/1024}'

    else
        echo "${bytes}B"
    fi
}

###############################################################################
# Capture disk information
###############################################################################

capture_initial_disk() {

    INITIAL_DISK_BYTES=$(lsblk -bdno SIZE "$DISK" 2>/dev/null | head -1 | xargs)

    [[ "$INITIAL_DISK_BYTES" =~ ^[0-9]+$ ]] || \
        error "Unable to determine initial disk size."

    INITIAL_DISK=$(human_size "$INITIAL_DISK_BYTES")
}

capture_final_disk() {

    FINAL_DISK_BYTES=$(lsblk -bdno SIZE "$DISK" 2>/dev/null | head -1 | xargs)

    [[ "$FINAL_DISK_BYTES" =~ ^[0-9]+$ ]] || \
        error "Unable to determine final disk size."

    FINAL_DISK=$(human_size "$FINAL_DISK_BYTES")

    if (( FINAL_DISK_BYTES > INITIAL_DISK_BYTES )); then
        ADDED_DISK=$(human_size $((FINAL_DISK_BYTES - INITIAL_DISK_BYTES)))
    else
        ADDED_DISK="0G"
    fi

    FINAL_ROOT=$(df -hP / | awk 'NR==2 {print $2}')

    [[ -n "$FINAL_ROOT" ]] || FINAL_ROOT="Unknown"
}

###############################################################################
# Final results
###############################################################################

final_success() {

    capture_final_disk

    echo
    echo "========================================="
    echo "          STORAGE RESIZE SUCCESS"
    echo "========================================="
    echo "OS        : $OS_NAME"
    echo "Previous  : $INITIAL_DISK"
    echo "Added     : +$ADDED_DISK"
    echo "Total     : $FINAL_DISK"
    echo "Root FS   : $FINAL_ROOT"
    echo "Status    : Successfully extended"
    echo "========================================="
    echo
}

final_no_resize() {

    capture_final_disk

    echo
    echo "========================================="
    echo "       STORAGE ALREADY AT MAXIMUM"
    echo "========================================="
    echo "OS        : $OS_NAME"
    echo "Total     : $FINAL_DISK"
    echo "Added     : 0G"
    echo "Root FS   : $FINAL_ROOT"
    echo "Status    : No additional storage detected"
    echo "========================================="
    echo
}

final_failure() {

    local current_disk="Unknown"

    if [[ -n "$DISK" ]] && [[ -b "$DISK" ]]; then
        current_disk=$(lsblk -bdno SIZE "$DISK" 2>/dev/null |
            head -1 |
            awk '{printf "%.1fG", $1/1073741824}')
    fi

    echo
    echo "========================================="
    echo "          STORAGE RESIZE FAILED"
    echo "========================================="
    echo "OS        : ${OS_NAME:-Unknown}"
    echo "Disk      : $current_disk"
    echo "Status    : Resize could not be completed"
    echo "========================================="
    echo
}

###############################################################################
# Error handler
###############################################################################

trap '
    trap - ERR
    final_failure
    exit 1
' ERR

###############################################################################
# Root check
###############################################################################

check_root() {

    if [[ $EUID -ne 0 ]]; then
        error "Script must be run as root."
    fi
}

###############################################################################
# OS detection
###############################################################################

detect_os() {

    [[ -f /etc/os-release ]] || \
        error "/etc/os-release not found."

    source /etc/os-release

    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"

    case "$OS_ID" in

        ubuntu)

            case "$OS_VERSION" in

                22.04)
                    OS_NAME="Ubuntu 22"
                    ;;

                24.04)
                    OS_NAME="Ubuntu 24"
                    ;;

                26.04)
                    OS_NAME="Ubuntu 26"
                    ;;

                *)
                    error "Unsupported Ubuntu version."
                    ;;

            esac
            ;;

        debian)

            [[ "$OS_VERSION" == "13" ]] || \
                error "Unsupported Debian version."

            OS_NAME="Debian 13"
            ;;

        fedora)

            [[ "$OS_VERSION" == "44" ]] || \
                error "Unsupported Fedora version."

            OS_NAME="Fedora 44"
            ;;

        centos)

            [[ "$OS_VERSION" == "10" ]] || \
                error "Unsupported CentOS version."

            OS_NAME="CentOS Stream 10"
            ;;

        almalinux)

            [[ "$OS_VERSION" == 10* ]] || \
                error "Unsupported AlmaLinux version."

            OS_NAME="AlmaLinux 10"
            ;;

        rocky)

            [[ "$OS_VERSION" == 10* ]] || \
                error "Unsupported Rocky Linux version."

            OS_NAME="Rocky Linux 10"
            ;;

        arch)

            OS_NAME="Arch Linux"
            ;;

        *)

            error "Unsupported operating system: $OS_ID"
            ;;

    esac

    log "Detected OS: $OS_NAME"
}

###############################################################################
# Command check
###############################################################################

require_command() {

    command -v "$1" >/dev/null 2>&1 || \
        error "Required command '$1' is not installed."
}

###############################################################################
# APT requirements
###############################################################################

install_apt_requirements() {

    if ! command -v growpart >/dev/null 2>&1; then

        export DEBIAN_FRONTEND=noninteractive

        apt-get update -qq >/dev/null 2>&1

        apt-get install -y cloud-guest-utils >/dev/null 2>&1
    fi

    require_command growpart
    require_command partprobe
}

###############################################################################
# DNF requirements
###############################################################################

install_dnf_requirements() {

    local packages=(
        cloud-utils-growpart
        lvm2
        parted
        xfsprogs
        util-linux
    )

    for package in "${packages[@]}"; do

        if ! rpm -q "$package" >/dev/null 2>&1; then
            dnf install -y "$package" >/dev/null 2>&1
        fi

    done

    require_command growpart
    require_command pvresize
    require_command lvextend
    require_command partprobe
}

###############################################################################
# Arch requirements
###############################################################################

install_arch_requirements() {

    if ! command -v growpart >/dev/null 2>&1; then
        error "growpart is not installed. Install cloud-utils first."
    fi

    require_command pvresize
    require_command lvextend
    require_command resize2fs
    require_command partprobe
}

###############################################################################
# Rescan disk
###############################################################################

rescan_disk() {

    local disk_name

    disk_name=$(basename "$DISK")

    if [[ -w "/sys/class/block/$disk_name/device/rescan" ]]; then
        echo 1 > "/sys/class/block/$disk_name/device/rescan"
    fi

    partprobe "$DISK" >/dev/null 2>&1 || true

    udevadm settle >/dev/null 2>&1 || true

    sleep 2
}

###############################################################################
# Detect LVM
###############################################################################

detect_lvm() {

    ROOT_SOURCE=$(findmnt -n -o SOURCE /)
    FILESYSTEM=$(findmnt -n -o FSTYPE /)

    if ! lvs "$ROOT_SOURCE" >/dev/null 2>&1; then
        error "Root filesystem is not an LVM logical volume."
    fi

    VG=$(lvs --noheadings -o vg_name "$ROOT_SOURCE" | xargs)

    [[ -n "$VG" ]] || \
        error "Unable to determine Volume Group."

    PV=$(pvs \
        --noheadings \
        -o pv_name \
        --select "vg_name=$VG" |
        head -1 |
        xargs)

    [[ -n "$PV" ]] || \
        error "Unable to determine Physical Volume."

    DISK="/dev/$(lsblk -dn -o PKNAME "$PV" | xargs)"

    [[ -b "$DISK" ]] || \
        error "Unable to determine physical disk."

    local device

    device=$(basename "$PV")

    if [[ "$device" =~ ^nvme[0-9]+n[0-9]+p([0-9]+)$ ]]; then

        PARTITION="${BASH_REMATCH[1]}"

    elif [[ "$device" =~ ^[a-z]+([0-9]+)$ ]]; then

        PARTITION="${BASH_REMATCH[1]}"

    else

        error "Unable to determine partition number."

    fi
}

###############################################################################
# Check additional storage
###############################################################################

has_additional_space() {

    local disk_size
    local partition_size

    disk_size=$(blockdev --getsize64 "$DISK")
    partition_size=$(blockdev --getsize64 "$PV")

    if (( disk_size > partition_size )); then
        return 0
    fi

    return 1
}

###############################################################################
# Grow partition
###############################################################################

grow_partition() {

    local disk_sectors
    local partition_sectors
    local difference
    local output
    local status

    disk_sectors=$(blockdev --getsz "$DISK")
    partition_sectors=$(blockdev --getsz "$PV")

    difference=$((disk_sectors - partition_sectors))

    if (( difference <= 2048 )); then

        NO_RESIZE_NEEDED=1
        return 0
    fi

    if output=$(growpart "$DISK" "$PARTITION" 2>&1); then
        status=0
    else
        status=$?
    fi

    if echo "$output" | grep -q "NOCHANGE"; then

        NO_RESIZE_NEEDED=1
        return 0
    fi

    if (( status != 0 )); then
        error "Unable to extend partition."
    fi

    partprobe "$DISK" >/dev/null 2>&1 || true

    udevadm settle >/dev/null 2>&1 || true

    sleep 2
}

###############################################################################
# Resize PV
###############################################################################

resize_pv() {

    pvresize "$PV" >/dev/null 2>&1
}

###############################################################################
# Extend root LV
###############################################################################

extend_root_lv() {

    local free_extents

    free_extents=$(vgs \
        --noheadings \
        -o vg_free_count \
        "$VG" |
        xargs)

    if [[ "$free_extents" == "0" ]]; then
        return 0
    fi

    lvextend -l +100%FREE "$ROOT_SOURCE" >/dev/null 2>&1
}

###############################################################################
# Grow EXT4
###############################################################################

grow_ext4() {

    resize2fs "$ROOT_SOURCE" >/dev/null 2>&1
}

###############################################################################
# Grow XFS
###############################################################################

grow_xfs() {

    xfs_growfs / >/dev/null 2>&1
}

###############################################################################
# Ubuntu 22
###############################################################################

resize_ubuntu22() {

    ROOT_SOURCE=$(findmnt -n -o SOURCE /)
    FILESYSTEM=$(findmnt -n -o FSTYPE /)

    [[ "$FILESYSTEM" == "ext4" ]] || \
        error "Unexpected filesystem."

    DISK="/dev/$(lsblk -dn -o PKNAME "$ROOT_SOURCE" | xargs)"

    [[ -b "$DISK" ]] || \
        error "Unable to determine disk."

    local device

    device=$(basename "$ROOT_SOURCE")

    if [[ "$device" =~ ^nvme[0-9]+n[0-9]+p([0-9]+)$ ]]; then
        PARTITION="${BASH_REMATCH[1]}"
    elif [[ "$device" =~ ^[a-z]+([0-9]+)$ ]]; then
        PARTITION="${BASH_REMATCH[1]}"
    else
        error "Unable to determine partition."
    fi

    capture_initial_disk

    rescan_disk

    local disk_size
    local partition_size

    disk_size=$(blockdev --getsize64 "$DISK")
    partition_size=$(blockdev --getsize64 "$ROOT_SOURCE")

    if (( disk_size <= partition_size )); then
        final_no_resize
        return 0
    fi

    if ! growpart "$DISK" "$PARTITION" >/dev/null 2>&1; then
        final_no_resize
        return 0
    fi

    partprobe "$DISK" >/dev/null 2>&1 || true

    udevadm settle >/dev/null 2>&1 || true

    sleep 2

    resize2fs "$ROOT_SOURCE" >/dev/null 2>&1

    final_success
}

###############################################################################
# Ubuntu 24 / 26
###############################################################################

resize_ubuntu_lvm() {

    detect_lvm

    [[ "$FILESYSTEM" == "ext4" ]] || \
        error "Unexpected filesystem."

    capture_initial_disk

    rescan_disk

    if ! has_additional_space; then

        final_no_resize
        return 0

    fi

    grow_partition

    if [[ "$NO_RESIZE_NEEDED" == "1" ]]; then

        final_no_resize
        return 0

    fi

    resize_pv
    extend_root_lv
    grow_ext4

    final_success
}

###############################################################################
# Debian 13
###############################################################################

resize_debian13() {

    detect_lvm

    [[ "$FILESYSTEM" == "ext4" ]] || \
        error "Unexpected filesystem."

    [[ "$PARTITION" == "5" ]] || \
        error "Unexpected LVM partition."

    capture_initial_disk

    rescan_disk

    if ! has_additional_space; then

        final_no_resize
        return 0

    fi

    growpart "$DISK" 2 >/dev/null 2>&1

    partprobe "$DISK" >/dev/null 2>&1 || true

    udevadm settle >/dev/null 2>&1 || true

    sleep 2

    growpart "$DISK" 5 >/dev/null 2>&1

    partprobe "$DISK" >/dev/null 2>&1 || true

    udevadm settle >/dev/null 2>&1 || true

    sleep 2

    resize_pv
    extend_root_lv
    grow_ext4

    final_success
}

###############################################################################
# Fedora / CentOS / AlmaLinux / Rocky
###############################################################################

resize_rhel_xfs() {

    detect_lvm

    [[ "$FILESYSTEM" == "xfs" ]] || \
        error "Unexpected filesystem."

    [[ "$PARTITION" == "3" ]] || \
        error "Unexpected LVM partition."

    capture_initial_disk

    rescan_disk

    ###########################################################################
    # Remove only verified 512-byte placeholder partition
    ###########################################################################

    local placeholder="${DISK}4"

    if [[ "$DISK" =~ nvme|mmcblk ]]; then
        placeholder="${DISK}p4"
    fi

    if [[ -b "$placeholder" ]]; then

        local placeholder_size

        placeholder_size=$(blockdev --getsize64 "$placeholder")

        if (( placeholder_size <= 4096 )); then

            parted -s "$DISK" rm 4 >/dev/null 2>&1

            partprobe "$DISK" >/dev/null 2>&1 || true

            udevadm settle >/dev/null 2>&1 || true

            sleep 2

        else

            error "Unexpected partition 4 detected."

        fi
    fi

    if ! has_additional_space; then

        final_no_resize
        return 0

    fi

    grow_partition

    if [[ "$NO_RESIZE_NEEDED" == "1" ]]; then

        final_no_resize
        return 0

    fi

    resize_pv
    extend_root_lv
    grow_xfs

    final_success
}

###############################################################################
# Arch Linux
###############################################################################

resize_arch() {

    detect_lvm

    [[ "$FILESYSTEM" == "ext4" ]] || \
        error "Unexpected filesystem."

    capture_initial_disk

    rescan_disk

    if ! has_additional_space; then

        final_no_resize
        return 0

    fi

    grow_partition

    if [[ "$NO_RESIZE_NEEDED" == "1" ]]; then

        final_no_resize
        return 0

    fi

    resize_pv
    extend_root_lv
    grow_ext4

    final_success
}

###############################################################################
# Main
###############################################################################

main() {

    check_root

    detect_os

    case "$OS_ID" in

        ubuntu)

            install_apt_requirements

            case "$OS_VERSION" in

                22.04)
                    resize_ubuntu22
                    ;;

                24.04|26.04)
                    resize_ubuntu_lvm
                    ;;

                *)
                    error "Unsupported Ubuntu version."
                    ;;

            esac

            ;;

        debian)

            install_apt_requirements
            resize_debian13
            ;;

        fedora|centos|almalinux|rocky)

            install_dnf_requirements
            resize_rhel_xfs
            ;;

        arch)

            install_arch_requirements
            resize_arch
            ;;

        *)

            error "Unsupported operating system."
            ;;

    esac
}

main "$@"

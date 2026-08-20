#!/bin/bash

###############################################################################
# VPS DISK INCREASE - ALL IN ONE
#
# Supported:
#   Ubuntu 22 / 24 / 26
#   Debian 11 / 12 / 13
#   Fedora 44
#   CentOS Stream 10
#   AlmaLinux 8 / 9 / 10
#   Rocky Linux 10
#   Arch Linux
###############################################################################

set -Eeuo pipefail

###############################################################################
# GLOBALS
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
# LOGGING
###############################################################################

log() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

###############################################################################
# HUMAN SIZE
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
# CAPTURE INITIAL DISK
###############################################################################

capture_initial_disk() {

    INITIAL_DISK_BYTES=$(lsblk -bdno SIZE "$DISK" 2>/dev/null |
        head -1 |
        xargs)

    [[ "$INITIAL_DISK_BYTES" =~ ^[0-9]+$ ]] || \
        error "Unable to determine initial disk size."

    INITIAL_DISK=$(human_size "$INITIAL_DISK_BYTES")
}

###############################################################################
# CAPTURE FINAL DISK
###############################################################################

capture_final_disk() {

    FINAL_DISK_BYTES=$(lsblk -bdno SIZE "$DISK" 2>/dev/null |
        head -1 |
        xargs)

    [[ "$FINAL_DISK_BYTES" =~ ^[0-9]+$ ]] || \
        error "Unable to determine final disk size."

    FINAL_DISK=$(human_size "$FINAL_DISK_BYTES")

    if (( FINAL_DISK_BYTES > INITIAL_DISK_BYTES )); then
        ADDED_DISK=$(human_size \
            $((FINAL_DISK_BYTES - INITIAL_DISK_BYTES)))
    else
        ADDED_DISK="0G"
    fi

    FINAL_ROOT=$(df -hP / | awk 'NR==2 {print $2}')

    [[ -n "$FINAL_ROOT" ]] || FINAL_ROOT="Unknown"
}

###############################################################################
# FINAL SUCCESS
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

###############################################################################
# FINAL NO RESIZE
###############################################################################

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

###############################################################################
# FINAL FAILURE
###############################################################################

final_failure() {

    echo
    echo "========================================="
    echo "          STORAGE RESIZE FAILED"
    echo "========================================="
    echo "OS        : ${OS_NAME:-Unknown}"
    echo "Status    : Resize could not be completed"
    echo "========================================="
    echo
}

###############################################################################
# ERROR TRAP
###############################################################################

trap '
    trap - ERR
    final_failure
    exit 1
' ERR

###############################################################################
# ROOT CHECK
###############################################################################

check_root() {

    if [[ $EUID -ne 0 ]]; then
        error "Script must be run as root."
    fi
}

###############################################################################
# OS DETECTION
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

            case "$OS_VERSION" in
                11)
                    OS_NAME="Debian 11"
                    ;;
                12)
                    OS_NAME="Debian 12"
                    ;;
                13)
                    OS_NAME="Debian 13"
                    ;;
                *)
                    error "Unsupported Debian version."
                    ;;
            esac
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

            case "$OS_VERSION" in
                8*)
                    OS_NAME="AlmaLinux 8"
                    ;;
                9*)
                    OS_NAME="AlmaLinux 9"
                    ;;
                10*)
                    OS_NAME="AlmaLinux 10"
                    ;;
                *)
                    error "Unsupported AlmaLinux version."
                    ;;
            esac
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

            error "Unsupported operating system."
            ;;

    esac

    log "Detected OS: $OS_NAME"
}

###############################################################################
# REQUIRED COMMAND
###############################################################################

require_command() {

    command -v "$1" >/dev/null 2>&1 || \
        error "Required command '$1' is not installed."
}

###############################################################################
# APT REQUIREMENTS
###############################################################################

install_apt_requirements() {

    local missing=0

    command -v growpart >/dev/null 2>&1 || missing=1
    command -v pvresize >/dev/null 2>&1 || missing=1
    command -v lvextend >/dev/null 2>&1 || missing=1
    command -v partprobe >/dev/null 2>&1 || missing=1

    if (( missing == 1 )); then

        log "Installing required packages..."

        export DEBIAN_FRONTEND=noninteractive

        apt-get update -qq >/dev/null 2>&1

        apt-get install -y \
            cloud-guest-utils \
            lvm2 \
            parted \
            >/dev/null 2>&1
    fi

    require_command growpart
    require_command pvresize
    require_command lvextend
    require_command partprobe
}

###############################################################################
# DNF REQUIREMENTS
###############################################################################

install_dnf_requirements() {

    local packages=(
        cloud-utils-growpart
        lvm2
        parted
        xfsprogs
        util-linux
    )

    local missing=0

    for package in "${packages[@]}"; do

        if ! rpm -q "$package" >/dev/null 2>&1; then
            missing=1
            break
        fi

    done

    if (( missing == 1 )); then

        log "Installing required packages..."

        dnf install -y \
            "${packages[@]}" \
            >/dev/null 2>&1
    fi

    require_command growpart
    require_command pvresize
    require_command lvextend
    require_command partprobe
}

###############################################################################
# ARCH REQUIREMENTS
###############################################################################

install_arch_requirements() {

    local missing=0

    command -v growpart >/dev/null 2>&1 || missing=1
    command -v pvresize >/dev/null 2>&1 || missing=1
    command -v lvextend >/dev/null 2>&1 || missing=1
    command -v resize2fs >/dev/null 2>&1 || missing=1
    command -v partprobe >/dev/null 2>&1 || missing=1

    if (( missing == 1 )); then

        log "Installing required packages..."

        pacman -Sy --noconfirm archlinux-keyring \
            >/dev/null 2>&1 || true

        pacman -S --noconfirm \
            cloud-guest-utils \
            lvm2 \
            parted \
            >/dev/null 2>&1
    fi

    require_command growpart
    require_command pvresize
    require_command lvextend
    require_command resize2fs
    require_command partprobe
}

###############################################################################
# RESCAN DISK
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
# DETECT LVM
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

    elif [[ "$device" =~ ^mmcblk[0-9]+p([0-9]+)$ ]]; then

        PARTITION="${BASH_REMATCH[1]}"

    elif [[ "$device" =~ ^[a-z]+([0-9]+)$ ]]; then

        PARTITION="${BASH_REMATCH[1]}"

    else

        error "Unable to determine partition number."

    fi
}

###############################################################################
# CHECK ADDITIONAL SPACE
###############################################################################

has_additional_space() {

    local disk_size
    local partition_size

    disk_size=$(blockdev --getsize64 "$DISK")
    partition_size=$(blockdev --getsize64 "$PV")

    (( disk_size > partition_size ))
}

###############################################################################
# GROW PARTITION
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
        echo "$output" >&2
        error "Unable to extend partition."
    fi

    partprobe "$DISK" >/dev/null 2>&1 || true
    udevadm settle >/dev/null 2>&1 || true
    sleep 2
}

###############################################################################
# RESIZE PV
###############################################################################

resize_pv() {

    pvresize "$PV" >/dev/null 2>&1
}

###############################################################################
# EXTEND ROOT LV
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
# EXT4
###############################################################################

grow_ext4() {

    resize2fs "$ROOT_SOURCE" >/dev/null 2>&1
}

###############################################################################
# XFS
###############################################################################

grow_xfs() {

    xfs_growfs / >/dev/null 2>&1
}

###############################################################################
# UBUNTU 22
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
# UBUNTU 24 / 26
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
# DEBIAN 11 / 12 / 13
###############################################################################

resize_debian_generic() {

    detect_lvm

    [[ "$FILESYSTEM" == "ext4" ]] || \
        error "Unexpected Debian root filesystem."

    capture_initial_disk

    rescan_disk

    if ! has_additional_space; then

        final_no_resize
        return 0

    fi

    local table_type

    table_type=$(parted -ms "$DISK" print 2>/dev/null |
        awk -F: 'NR==2 {print $6}')

    if [[ "$table_type" == "msdos" ]]; then

        if (( PARTITION >= 5 )); then

            local extended_output=""
            local logical_output=""

            extended_output=$(growpart "$DISK" 2 2>&1) || true

            if echo "$extended_output" | grep -q "NOCHANGE"; then

                final_no_resize
                return 0

            fi

            if ! echo "$extended_output" | grep -q "CHANGED"; then

                echo "$extended_output" >&2
                error "Unable to extend Debian extended partition."

            fi

            partprobe "$DISK" >/dev/null 2>&1 || true
            udevadm settle >/dev/null 2>&1 || true
            sleep 2

            logical_output=$(growpart \
                "$DISK" \
                "$PARTITION" \
                2>&1) || true

            if echo "$logical_output" | grep -q "NOCHANGE"; then

                final_no_resize
                return 0

            fi

            if ! echo "$logical_output" | grep -q "CHANGED"; then

                echo "$logical_output" >&2
                error "Unable to extend Debian LVM partition."

            fi

            partprobe "$DISK" >/dev/null 2>&1 || true
            udevadm settle >/dev/null 2>&1 || true
            sleep 2

        else

            local primary_output=""

            primary_output=$(growpart \
                "$DISK" \
                "$PARTITION" \
                2>&1) || true

            if echo "$primary_output" | grep -q "NOCHANGE"; then

                final_no_resize
                return 0

            fi

            if ! echo "$primary_output" | grep -q "CHANGED"; then

                echo "$primary_output" >&2
                error "Unable to extend Debian LVM partition."

            fi

            partprobe "$DISK" >/dev/null 2>&1 || true
            udevadm settle >/dev/null 2>&1 || true
            sleep 2

        fi

    elif [[ "$table_type" == "gpt" ]]; then

        local gpt_output=""

        gpt_output=$(growpart \
            "$DISK" \
            "$PARTITION" \
            2>&1) || true

        if echo "$gpt_output" | grep -q "NOCHANGE"; then

            final_no_resize
            return 0

        fi

        if ! echo "$gpt_output" | grep -q "CHANGED"; then

            echo "$gpt_output" >&2
            error "Unable to extend Debian LVM partition."

        fi

        partprobe "$DISK" >/dev/null 2>&1 || true
        udevadm settle >/dev/null 2>&1 || true
        sleep 2

    else

        error "Unsupported Debian partition table."

    fi

    resize_pv
    extend_root_lv
    grow_ext4

    final_success
}

###############################################################################
# FEDORA / CENTOS / ALMALINUX / ROCKY
###############################################################################

resize_rhel_xfs() {

    detect_lvm

    [[ "$FILESYSTEM" == "xfs" ]] || \
        error "Unexpected filesystem."

    capture_initial_disk

    rescan_disk

    local disk_sectors
    local pv_end_sector
    local available_sectors
    local minimum_growth

    disk_sectors=$(blockdev --getsz "$DISK")

    pv_end_sector=$(parted -ms "$DISK" unit s print 2>/dev/null |
        awk -F: -v p="$PARTITION" '
            $1 == p {
                gsub("s","",$3)
                print $3
                exit
            }
        ')

    if [[ -z "$pv_end_sector" ]]; then

        error "Unable to determine LVM partition boundary."

    fi

    available_sectors=$((disk_sectors - pv_end_sector - 1))

    minimum_growth=2048

    if (( available_sectors <= minimum_growth )); then

        final_no_resize
        return 0

    fi

    log "Additional storage detected."

    local placeholder

    if [[ "$DISK" =~ nvme|mmcblk ]]; then

        placeholder="${DISK}p4"

    else

        placeholder="${DISK}4"

    fi

    if [[ -b "$placeholder" ]]; then

        local placeholder_size

        placeholder_size=$(blockdev --getsize64 "$placeholder")

        if (( placeholder_size <= 4096 )); then

            parted -s "$DISK" rm 4 >/dev/null 2>&1 || true

            partprobe "$DISK" >/dev/null 2>&1 || true
            udevadm settle >/dev/null 2>&1 || true

            sleep 2

        else

            error "Unexpected partition 4 detected."

        fi
    fi

    local output=""
    local status=0

    if output=$(growpart "$DISK" "$PARTITION" 2>&1); then

        status=0

    else

        status=$?

    fi

    if echo "$output" | grep -q "NOCHANGE"; then

        final_no_resize
        return 0

    fi

    if (( status != 0 )); then

        echo "$output" >&2

        error "Unable to extend LVM partition."

    fi

    partprobe "$DISK" >/dev/null 2>&1 || true
    udevadm settle >/dev/null 2>&1 || true

    sleep 2

    resize_pv
    extend_root_lv
    grow_xfs

    final_success
}

###############################################################################
# ARCH LINUX
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
# MAIN
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

            case "$OS_VERSION" in

                11|12|13)
                    resize_debian_generic
                    ;;

                *)
                    error "Unsupported Debian version."
                    ;;

            esac

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

###############################################################################
# RUN
###############################################################################

main "$@"

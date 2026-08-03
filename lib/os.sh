#!/usr/bin/env bash
# shellcheck shell=bash

detect_distribution() {
    [[ -r /etc/os-release ]] || { error 'Cannot read /etc/os-release; Linux distribution cannot be detected.'; return 1; }
    # os-release is a system-controlled shell-compatible file.
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID=${ID,,}
    DISTRO_VERSION_ID=${VERSION_ID:-}
    DISTRO_VERSION_MAJOR=${DISTRO_VERSION_ID%%.*}
    [[ -n $DISTRO_ID ]] || { error 'Distribution ID is missing from /etc/os-release.'; return 1; }
}

detect_package_manager() {
    local manager
    for manager in apt-get dnf yum zypper pacman apk; do
        if command_exists "$manager"; then
            PACKAGE_MANAGER=$manager
            return 0
        fi
    done
    error 'No supported package manager was found (apt-get, dnf, yum, zypper, pacman, apk).'
    return 1
}

# Map an os-release ID and major version to a resize script. Add one entry here
# when adding a supported script. A blank version is a distribution-wide fallback.
resolve_resize_script() {
    local key="${DISTRO_ID}:${DISTRO_VERSION_MAJOR}"
    case "$key" in
        ubuntu:22) echo 'diskincrease-ubu22.sh' ;;
        ubuntu:24) echo 'diskincrease-ubu24.sh' ;;
        ubuntu:26) echo 'diskincrease-ubu26.sh' ;;
        debian:10) echo 'diskincrease-deb10.sh' ;;
        debian:11) echo 'diskincrease-deb11.sh' ;;
        debian:12) echo 'diskincrease-deb12.sh' ;;
        debian:13) echo 'diskincrease-deb13.sh' ;;
        almalinux:8) echo 'diskincrease-AlmaLinux8.sh' ;;
        almalinux:9) echo 'diskincrease-AlmaLinux9.sh' ;;
        almalinux:10) echo 'diskincrease-AlmaLinux10.sh' ;;
        rocky:10) echo 'diskincrease-RockyLinux10.sh' ;;
        centos:10) echo 'diskincrease-cenS10.sh' ;;
        fedora:44) echo 'diskincrease-fed44.sh' ;;
        arch:*) echo 'diskincrease-arch.sh' ;;
        *) return 1 ;;
    esac
}

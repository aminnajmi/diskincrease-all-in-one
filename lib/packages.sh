#!/usr/bin/env bash
# shellcheck shell=bash

package_installed() {
    local package=$1
    case ${PACKAGE_MANAGER:-} in
        apt-get) dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed' ;;
        dnf|yum|zypper) rpm -q "$package" >/dev/null 2>&1 ;;
        pacman) pacman -Q "$package" >/dev/null 2>&1 ;;
        apk) apk info -e "$package" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

install_package() {
    local package=$1
    detect_package_manager
    if package_installed "$package"; then
        info "Package already installed: $package"
        return 0
    fi
    [[ ${AUTO_INSTALL_PACKAGES:-true} == true ]] || { error "Required package is missing: $package"; return 1; }
    info "Installing package: $package"
    case $PACKAGE_MANAGER in
        apt-get) run apt-get update && run apt-get install -y "$package" ;;
        dnf|yum) run "$PACKAGE_MANAGER" install -y "$package" ;;
        zypper) run zypper --non-interactive install "$package" ;;
        pacman) run pacman --noconfirm -S "$package" ;;
        apk) run apk add "$package" ;;
    esac
}

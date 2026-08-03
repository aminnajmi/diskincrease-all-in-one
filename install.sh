#!/usr/bin/env bash
# Bootstrap installer. Intended to be run as root, including through curl | bash.
set -Eeuo pipefail

PROJECT_NAME=${PROJECT_NAME:-disk-resizer}
INSTALL_DIR=${INSTALL_DIR:-/opt/disk-resizer}
REPOSITORY_URL=${DISK_RESIZER_REPOSITORY:-https://github.com/aminnajmi/disk-resizer.git}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die 'Run the installer as root (for example: curl ... | sudo bash).'; }

install_git() {
    command_exists git && return 0
    printf 'Git is not installed; installing it...\n'
    if command_exists apt-get; then apt-get update && apt-get install -y git
    elif command_exists dnf; then dnf install -y git
    elif command_exists yum; then yum install -y git
    elif command_exists zypper; then zypper --non-interactive install git
    elif command_exists pacman; then pacman --noconfirm -S git
    elif command_exists apk; then apk add git
    else die 'Git is missing and no supported package manager was found.'
    fi
    command_exists git || die 'Git installation did not complete successfully.'
}

main() {
    require_root
    install_git
    if [[ -d $INSTALL_DIR/.git ]]; then
        printf 'Updating %s in %s...\n' "$PROJECT_NAME" "$INSTALL_DIR"
        git -C "$INSTALL_DIR" pull --ff-only || die 'Failed to update the existing repository.'
    elif [[ -e $INSTALL_DIR ]]; then
        die "$INSTALL_DIR exists but is not a Git repository; move it aside before installing."
    else
        printf 'Cloning %s into %s...\n' "$PROJECT_NAME" "$INSTALL_DIR"
        git clone "$REPOSITORY_URL" "$INSTALL_DIR" || die 'Failed to clone the repository.'
    fi
    find "$INSTALL_DIR" -type f -name '*.sh' -exec chmod 0755 {} +
    exec "$INSTALL_DIR/launcher.sh"
}

main "$@"

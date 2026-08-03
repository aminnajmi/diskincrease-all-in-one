#!/usr/bin/env bash
# Dispatches to an OS-specific resize script; it deliberately contains no resize logic.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=config.sh
. "$SCRIPT_DIR/config.sh"
# shellcheck source=lib/logger.sh
. "$SCRIPT_DIR/lib/logger.sh"
# shellcheck source=lib/utils.sh
. "$SCRIPT_DIR/lib/utils.sh"
# shellcheck source=lib/os.sh
. "$SCRIPT_DIR/lib/os.sh"

init_logger
trap cleanup EXIT

main() {
    require_root
    info "$PROJECT_NAME $PROJECT_VERSION starting."
    info 'Detecting operating system...'
    detect_distribution
    info "Detected: ${PRETTY_NAME:-$DISTRO_ID} (ID: $DISTRO_ID, version: ${DISTRO_VERSION_ID:-unknown})."

    local script script_path
    if ! script=$(resolve_resize_script); then
        error "Unsupported distribution: ${DISTRO_ID} ${DISTRO_VERSION_ID:-unknown}. No matching resize script is available."
        return 64
    fi
    script_path="$SCRIPT_DIR/os/$script"
    if [[ ! -f $script_path ]]; then
        error "The mapped resize script is missing: $script_path"
        return 66
    fi
    if [[ ! -x $script_path ]]; then
        error "The mapped resize script is not executable: $script_path"
        return 126
    fi

    info "Launching resize script: os/$script"
    # The OS script's logic is untouched; formatting its output here ensures every
    # line in the central log receives the same timestamped structure.
    if execute_resize_script "$script_path"; then
        success 'Disk resize script completed successfully.'
    else
        local result=${PIPESTATUS[0]}
        error "Disk resize script failed with exit code $result. See $LOG_FILE for details."
        return "$result"
    fi
}

execute_resize_script() {
    local script_path=$1 line result
    "$script_path" 2>&1 | while IFS= read -r line || [[ -n $line ]]; do
        info "[${script_path##*/}] $line"
    done
    result=${PIPESTATUS[0]}
    return "$result"
}

main "$@"

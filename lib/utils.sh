#!/usr/bin/env bash
# shellcheck shell=bash

command_exists() { command -v "$1" >/dev/null 2>&1; }

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        error 'This operation must be run as root. Re-run with sudo.'
        return 1
    fi
}

run() {
    if [[ ${DEBUG:-false} == true ]]; then
        info "Running: $*"
    fi
    "$@"
}

cleanup() {
    local exit_code=$?
    [[ $exit_code -eq 0 ]] || error "Stopped with exit code $exit_code."
}

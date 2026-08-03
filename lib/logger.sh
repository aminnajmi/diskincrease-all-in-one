#!/usr/bin/env bash
# shellcheck shell=bash

_log() {
    local level=$1 color=$2 message=$3 timestamp line
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    line="[$timestamp] $level $message"

    # Logging must not hide the actual resize result if the log path is unavailable.
    printf '%b%s%b\n' "$color" "$line" "$COLOR_RESET" >&2
    if [[ -n ${LOG_FILE:-} ]] && ! printf '%s\n' "$line" >>"$LOG_FILE"; then
        printf '%b[%s] WARNING Unable to write to %s%b\n' "$COLOR_YELLOW" "$timestamp" "$LOG_FILE" "$COLOR_RESET" >&2
    fi
}

init_logger() {
    COLOR_RESET=$'\033[0m'
    COLOR_BLUE=$'\033[0;34m'
    COLOR_YELLOW=$'\033[0;33m'
    COLOR_RED=$'\033[0;31m'
    COLOR_GREEN=$'\033[0;32m'
    [[ -t 2 ]] || COLOR_RESET= COLOR_BLUE= COLOR_YELLOW= COLOR_RED= COLOR_GREEN=
    : "${LOG_FILE:?LOG_FILE must be set before initializing logging}"
    touch "$LOG_FILE" || {
        printf 'ERROR: Cannot create log file: %s\n' "$LOG_FILE" >&2
        return 1
    }
}

info()    { _log INFO "$COLOR_BLUE" "$*"; }
warning() { _log WARNING "$COLOR_YELLOW" "$*"; }
error()   { _log ERROR "$COLOR_RED" "$*"; }
success() { _log SUCCESS "$COLOR_GREEN" "$*"; }

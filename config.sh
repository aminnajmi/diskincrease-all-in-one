#!/usr/bin/env bash
# shellcheck shell=bash

# Central configuration. Environment values may override these defaults.
: "${PROJECT_NAME:=disk-resizer}"
: "${PROJECT_VERSION:=$(<"${BASH_SOURCE[0]%/*}/VERSION")}" 
: "${LOG_FILE:=/var/log/disk-resizer.log}"
: "${DEBUG:=false}"
: "${AUTO_INSTALL_PACKAGES:=true}"
: "${INSTALL_DIR:=/opt/disk-resizer}"
: "${REPOSITORY_URL:=https://github.com/aminnajmi/disk-resizer.git}"

#!/usr/bin/env bash
# Lightweight tests that require only Bash; run with: bash tests/os_mapping_test.sh
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../lib/os.sh
. "$ROOT_DIR/lib/os.sh"

assert_mapping() {
    local distro=$1 major=$2 expected=$3 actual
    DISTRO_ID=$distro
    DISTRO_VERSION_MAJOR=$major
    actual=$(resolve_resize_script)
    [[ $actual == "$expected" ]] || {
        printf 'Expected %s:%s -> %s, got %s\n' "$distro" "$major" "$expected" "$actual" >&2
        return 1
    }
}

assert_mapping ubuntu 22 diskincrease-ubu22.sh
assert_mapping ubuntu 24 diskincrease-ubu24.sh
assert_mapping debian 13 diskincrease-deb13.sh
assert_mapping almalinux 9 diskincrease-AlmaLinux9.sh
assert_mapping rocky 10 diskincrease-RockyLinux10.sh
assert_mapping arch rolling diskincrease-arch.sh

DISTRO_ID=opensuse
DISTRO_VERSION_MAJOR=15
! resolve_resize_script
printf 'OS mapping tests passed.\n'

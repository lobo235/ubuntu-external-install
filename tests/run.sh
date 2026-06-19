#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

test_bash_syntax() {
  bash -n install-ubuntu-external.sh
  pass "bash syntax"
}

test_shellcheck_if_available() {
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck install-ubuntu-external.sh tests/run.sh
    pass "shellcheck"
  else
    printf 'SKIP shellcheck not installed\n'
  fi
}

test_version() {
  local out
  out="$(./install-ubuntu-external.sh --version)"
  [[ "${out}" == "install-ubuntu-external 0.2.0" ]] || fail "unexpected version output: ${out}"
  pass "version output"
}

test_help() {
  ./install-ubuntu-external.sh --help >/dev/null
  pass "help output"
}

test_single_casper_detection() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/casper" "${tmp}/.disk"
  : >"${tmp}/casper/filesystem.squashfs"
  printf 'Ubuntu 24.04.2 LTS amd64\n' >"${tmp}/.disk/info"

  (
    # shellcheck disable=SC1091
    source ./install-ubuntu-external.sh
    SOURCE_DIR="${tmp}"
    PROFILE="desktop"
    detect_source
    [[ "${SOURCE_LAYOUT}" == "single-casper" ]] || exit 10
    [[ "${#SOURCE_LAYERS[@]}" -eq 1 ]] || exit 11
  )

  rm -rf "${tmp}"
  pass "single casper source detection"
}

test_layered_casper_detection() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/casper" "${tmp}/.disk"
  : >"${tmp}/casper/minimal.squashfs"
  : >"${tmp}/casper/minimal.en.squashfs"
  : >"${tmp}/casper/minimal.standard.squashfs"
  : >"${tmp}/casper/minimal.standard.en.squashfs"
  printf 'Ubuntu 26.04 LTS amd64\n' >"${tmp}/.disk/info"

  (
    # shellcheck disable=SC1091
    source ./install-ubuntu-external.sh
    SOURCE_DIR="${tmp}"
    PROFILE="desktop"
    detect_source
    [[ "${SOURCE_LAYOUT}" == "layered-casper" ]] || exit 20
    [[ "${#SOURCE_LAYERS[@]}" -eq 4 ]] || exit 21
  )

  rm -rf "${tmp}"
  pass "layered casper source detection"
}

test_minimal_layered_detection() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/casper" "${tmp}/.disk"
  : >"${tmp}/casper/minimal.squashfs"
  printf 'Ubuntu 26.04 LTS amd64\n' >"${tmp}/.disk/info"

  (
    # shellcheck disable=SC1091
    source ./install-ubuntu-external.sh
    SOURCE_DIR="${tmp}"
    PROFILE="minimal"
    detect_source
    [[ "${SOURCE_LAYOUT}" == "layered-casper" ]] || exit 30
    [[ "${#SOURCE_LAYERS[@]}" -eq 1 ]] || exit 31
  )

  rm -rf "${tmp}"
  pass "minimal layered source detection"
}

test_efi_grub_fallback_config() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/boot/efi"

  (
    # shellcheck disable=SC1091
    source ./install-ubuntu-external.sh
    TARGET_MNT="${tmp}"
    BOOTLOADER_ID="ubuntu-external"
    part_path() { echo "/dev/disk/by-uuid/fake-root"; }
    blkid() { echo "11111111-2222-3333-4444-555555555555"; }
    write_efi_grub_fallback_config
    grep -q 'search.fs_uuid 11111111-2222-3333-4444-555555555555 root' "${tmp}/boot/efi/EFI/BOOT/grub.cfg"
    # shellcheck disable=SC2016
    grep -q 'configfile $prefix/grub.cfg' "${tmp}/boot/efi/EFI/BOOT/grub.cfg"
    cmp "${tmp}/boot/efi/EFI/BOOT/grub.cfg" "${tmp}/boot/efi/EFI/ubuntu-external/grub.cfg"
    cmp "${tmp}/boot/efi/EFI/BOOT/grub.cfg" "${tmp}/boot/efi/EFI/ubuntu/grub.cfg"
    cmp "${tmp}/boot/efi/EFI/BOOT/grub.cfg" "${tmp}/boot/efi/boot/grub/grub.cfg"
  )

  rm -rf "${tmp}"
  pass "efi grub fallback config"
}

test_chroot_resolver_restore() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/etc" "${tmp}/run/systemd/resolve"
  ln -s ../run/systemd/resolve/stub-resolv.conf "${tmp}/etc/resolv.conf"
  printf 'nameserver 127.0.0.53\n' >"${tmp}/run/systemd/resolve/stub-resolv.conf"

  (
    # shellcheck disable=SC1091
    source ./install-ubuntu-external.sh
    TARGET_MNT="${tmp}"
    prepare_chroot_resolver
    [[ -f "${tmp}/etc/resolv.conf" && ! -L "${tmp}/etc/resolv.conf" ]] || exit 40
    restore_chroot_resolver
    [[ -L "${tmp}/etc/resolv.conf" ]] || exit 41
    [[ "$(readlink "${tmp}/etc/resolv.conf")" == "../run/systemd/resolve/stub-resolv.conf" ]] || exit 42
  )

  rm -rf "${tmp}"
  pass "chroot resolver restore"
}

test_grub_dropin_uses_visible_menu() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/etc/default/grub.d" "${tmp}/etc/cloud" "${tmp}/var/log/ubuntu-external-installer" "${tmp}/var/lib/dbus"
  : >"${tmp}/var/lib/dbus/machine-id"
  : >"${tmp}/etc/resolv.conf"

  (
    # shellcheck disable=SC1091
    source ./install-ubuntu-external.sh
    TARGET_MNT="${tmp}"
    TARGET_HOSTNAME="ubuntu-external"
    UBUNTU_CODENAME="resolute"
    UBUNTU_VERSION="26.04"
    PROFILE="desktop"
    ROOTDELAY="10"
    KEEP_CLOUD_INIT=0
    INSTALL_LOG="${tmp}/install.log"
    NEW_USER="tester"
    mkdir -p "${tmp}/etc/apt"
    : >"${INSTALL_LOG}"
    part_path() { echo "/dev/fake$1"; }
    blkid() {
      if [[ "$*" == *"/dev/fake1"* ]]; then
        echo "ESP-UUID"
      else
        echo "ROOT-UUID"
      fi
    }
    write_system_config
    grep -q '^GRUB_TIMEOUT_STYLE=menu$' "${tmp}/etc/default/grub.d/99-usb-root.cfg"
    grep -q '^GRUB_TIMEOUT=10$' "${tmp}/etc/default/grub.d/99-usb-root.cfg"
    grep -q '^GRUB_RECORDFAIL_TIMEOUT=10$' "${tmp}/etc/default/grub.d/99-usb-root.cfg"
  )

  rm -rf "${tmp}"
  pass "grub visible menu drop-in"
}

test_option_validation_rejects_unsafe_values() {
  (
    # shellcheck disable=SC1091
    source ./install-ubuntu-external.sh
    ISO_PATH="/tmp/fake.iso"
    TARGET_ARG="/dev/fake"
    NEW_USER="bad;user"
    PROMPT_PASSWORD=1
    validate_options
  ) >/dev/null 2>&1 && fail "unsafe username was accepted"

  (
    # shellcheck disable=SC1091
    source ./install-ubuntu-external.sh
    ISO_PATH="/tmp/fake.iso"
    TARGET_ARG="/dev/fake"
    NEW_USER="safeuser"
    PROMPT_PASSWORD=1
    TARGET_HOSTNAME=$'host\n127.0.0.1 injected'
    validate_options
  ) >/dev/null 2>&1 && fail "unsafe hostname was accepted"

  (
    # shellcheck disable=SC1091
    source ./install-ubuntu-external.sh
    ISO_PATH="/tmp/fake.iso"
    TARGET_ARG="/dev/fake"
    NEW_USER="safeuser"
    PROMPT_PASSWORD=1
    BOOTLOADER_ID="../evil"
    validate_options
  ) >/dev/null 2>&1 && fail "unsafe bootloader id was accepted"

  (
    # shellcheck disable=SC1091
    source ./install-ubuntu-external.sh
    ISO_PATH="/tmp/fake.iso"
    TARGET_ARG="/dev/fake"
    NEW_USER="safeuser"
    PROMPT_PASSWORD=1
    COPY_PROGRESS="sometimes"
    validate_options
  ) >/dev/null 2>&1 && fail "invalid copy progress mode was accepted"

  pass "unsafe option validation"
}

test_bash_syntax
test_shellcheck_if_available
test_version
test_help
test_single_casper_detection
test_layered_casper_detection
test_minimal_layered_detection
test_efi_grub_fallback_config
test_chroot_resolver_restore
test_grub_dropin_uses_visible_menu
test_option_validation_rejects_unsafe_values

printf '\nAll non-destructive tests passed.\n'

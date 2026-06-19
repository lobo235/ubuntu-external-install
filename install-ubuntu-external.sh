#!/usr/bin/env bash
set -euo pipefail

INSTALLER_NAME="install-ubuntu-external"
INSTALLER_VERSION="0.2.1"

ISO_PATH=""
SOURCE_DIR=""
TARGET_ARG=""
TARGET_DISK=""
PROFILE="desktop"
TARGET_HOSTNAME="ubuntu-external"
NEW_USER=""
NO_USER=0
PROMPT_PASSWORD=0
PASSWORD_HASH=""
ALLOW_LOCKED_USER=0
DRY_RUN=0
ASSUME_YES=0
EXPECT_SERIAL=""
EXPECT_MODEL=""
ALLOW_NON_USB=0
ALLOW_LOOP_TARGET=0
UNMOUNT_TARGET=0
ESP_SIZE="1128MiB"
ESP_LABEL="UBUNTU_EFI"
ROOT_LABEL="UBUNTU_ROOT"
ROOTDELAY="10"
BOOTLOADER_ID="ubuntu-external"
WRITE_NVRAM=0
FINALIZE_MODE="online"
KEEP_CLOUD_INIT=0
APT_MIRROR="https://archive.ubuntu.com/ubuntu/"
SECURITY_MIRROR="https://security.ubuntu.com/ubuntu/"
POST_INSTALL_SCRIPT=""
SKIP_FINALIZE=0
COPY_PROGRESS="periodic"
COPY_STATUS_INTERVAL=30
TARGET_MNT=""
WORK_DIR=""
SOURCE_MOUNT=""
SOURCE_WAS_MOUNTED=0
IMAGE_WORK_DIR=""
HOST_MODE="native"
SOURCE_LAYOUT=""
SOURCE_LAYERS=()
SOURCE_DESCRIPTION=""
UBUNTU_CODENAME="unknown"
UBUNTU_VERSION="unknown"
INSTALL_LOG=""
TARGET_MODIFIED=0
RESOLV_BACKUP_PATH=""
ACTIVE_RSYNC_PID=""

declare -a CREATED_MOUNTS=()

die() {
  echo "error: $*" >&2
  exit 1
}

warn() {
  echo "warning: $*" >&2
}

info() {
  echo "$*"
}

usage() {
  cat <<'EOF'
Usage:
  sudo ./install-ubuntu-external.sh --iso PATH --target DISK --user NAME --prompt-password
  sudo ./install-ubuntu-external.sh --source DIR --target DISK --user NAME --password-hash HASH

Installs Ubuntu Desktop amd64 onto an external USB/removable drive.

Input:
  --iso PATH                 Ubuntu Desktop ISO to mount read-only
  --source DIR               Already mounted Ubuntu installer filesystem

Target:
  --target DEVICE            Whole target disk, preferably /dev/disk/by-id/...
  --expect-serial SERIAL     Require target serial to match
  --expect-model TEXT        Require target model to contain text
  --allow-non-usb            Allow non-USB/non-removable target disks
  --allow-loop-target        Allow loop device targets for tests
  --unmount-target           Unmount target child filesystems before wiping

User:
  --user NAME                User to create in the installed system
  --prompt-password          Prompt with passwd inside the chroot
  --password-hash HASH       Set an existing crypt(3) password hash
  --allow-locked-user        Permit creating a user with locked password
  --no-user                  Advanced: create no user

Install behavior:
  --profile desktop|minimal  Filesystem profile for layered Ubuntu ISOs
  --hostname NAME            Installed system hostname
  --esp-size SIZE            EFI partition size, default 1128MiB
  --esp-label LABEL          EFI filesystem label
  --root-label LABEL         Root filesystem label
  --rootdelay SECONDS        GRUB rootdelay, default 10
  --bootloader-id NAME       UEFI bootloader id
  --write-nvram              Write a firmware NVRAM entry
  --online                   Install boot packages with apt, default
  --offline                  Do not apt install; fail if required tools are absent
  --keep-cloud-init          Do not disable cloud-init
  --apt-mirror URL           Ubuntu archive mirror
  --security-mirror URL      Ubuntu security mirror
  --post-install-script PATH Run script inside target chroot near the end
  --skip-finalize            Test mode: skip chroot package/user/GRUB work
  --copy-progress MODE       periodic, detailed, or never; default periodic

Control:
  --dry-run                  Validate inputs and print the plan only
  --yes                      Skip destructive confirmation only
  --version                  Print version
  --help                     Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --iso) ISO_PATH="${2:-}"; shift 2 ;;
      --source) SOURCE_DIR="${2:-}"; shift 2 ;;
      --target) TARGET_ARG="${2:-}"; shift 2 ;;
      --profile) PROFILE="${2:-}"; shift 2 ;;
      --hostname) TARGET_HOSTNAME="${2:-}"; shift 2 ;;
      --user) NEW_USER="${2:-}"; shift 2 ;;
      --prompt-password) PROMPT_PASSWORD=1; shift ;;
      --password-hash) PASSWORD_HASH="${2:-}"; shift 2 ;;
      --allow-locked-user) ALLOW_LOCKED_USER=1; shift ;;
      --no-user) NO_USER=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --yes) ASSUME_YES=1; shift ;;
      --expect-serial) EXPECT_SERIAL="${2:-}"; shift 2 ;;
      --expect-model) EXPECT_MODEL="${2:-}"; shift 2 ;;
      --allow-non-usb) ALLOW_NON_USB=1; shift ;;
      --allow-loop-target) ALLOW_LOOP_TARGET=1; shift ;;
      --unmount-target) UNMOUNT_TARGET=1; shift ;;
      --esp-size) ESP_SIZE="${2:-}"; shift 2 ;;
      --esp-label) ESP_LABEL="${2:-}"; shift 2 ;;
      --root-label) ROOT_LABEL="${2:-}"; shift 2 ;;
      --rootdelay) ROOTDELAY="${2:-}"; shift 2 ;;
      --bootloader-id) BOOTLOADER_ID="${2:-}"; shift 2 ;;
      --write-nvram) WRITE_NVRAM=1; shift ;;
      --online) FINALIZE_MODE="online"; shift ;;
      --offline) FINALIZE_MODE="offline"; shift ;;
      --keep-cloud-init) KEEP_CLOUD_INIT=1; shift ;;
      --apt-mirror) APT_MIRROR="${2:-}"; shift 2 ;;
      --security-mirror) SECURITY_MIRROR="${2:-}"; shift 2 ;;
      --post-install-script) POST_INSTALL_SCRIPT="${2:-}"; shift 2 ;;
      --skip-finalize) SKIP_FINALIZE=1; shift ;;
      --copy-progress) COPY_PROGRESS="${2:-}"; shift 2 ;;
      --version) echo "${INSTALLER_NAME} ${INSTALLER_VERSION}"; exit 0 ;;
      --help|-h) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "run with sudo: sudo ./install-ubuntu-external.sh ..."
}

detect_host_mode() {
  if grep -qi microsoft /proc/version 2>/dev/null; then
    HOST_MODE="wsl2"
  else
    HOST_MODE="native"
  fi
}

print_wsl2_guidance() {
  [[ "${HOST_MODE}" == "wsl2" ]] || return 0
  cat <<'EOF'
Detected WSL2.
Make sure the target disk was attached from elevated PowerShell, for example:
  wsl --mount --bare \\.\PHYSICALDRIVE<N>
Then confirm the disk appears inside WSL with:
  lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN,TYPE,FSTYPE,MOUNTPOINTS

This script does not attach Windows disks automatically.

EOF
}

check_architecture() {
  local machine
  machine="$(uname -m)"
  [[ "${machine}" == "x86_64" ]] || die "v1 supports x86_64 hosts only; got ${machine}"
}

dependency_package_hint() {
  case "$1" in
    sgdisk) echo "gdisk" ;;
    mkfs.vfat) echo "dosfstools" ;;
    mkfs.ext4) echo "e2fsprogs" ;;
    rsync) echo "rsync" ;;
    findmnt) echo "util-linux" ;;
    lsblk) echo "util-linux" ;;
    blkid) echo "util-linux" ;;
    wipefs) echo "util-linux" ;;
    udevadm) echo "udev" ;;
    mount|umount|losetup|blockdev) echo "util-linux" ;;
    chroot) echo "coreutils" ;;
    awk|sed|sort|xargs|find|du) echo "coreutils/findutils" ;;
    *) echo "" ;;
  esac
}

check_host_dependencies() {
  local missing=() cmd hint
  local required=(
    awk sed sort xargs find grep head tail tr date tee cp rm mkdir chmod sleep readlink basename dirname du
    lsblk findmnt blkid sgdisk wipefs mkfs.vfat mkfs.ext4 swapon swapoff
    mount umount rsync chroot blockdev udevadm
  )
  if [[ -n "${ISO_PATH}" ]]; then
    required+=(losetup)
  fi

  for cmd in "${required[@]}"; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done

  if ((${#missing[@]} > 0)); then
    echo "error: missing required commands:" >&2
    for cmd in "${missing[@]}"; do
      hint="$(dependency_package_hint "${cmd}")"
      if [[ -n "${hint}" ]]; then
        printf '  %-12s install package: %s\n' "${cmd}" "${hint}" >&2
      else
        printf '  %s\n' "${cmd}" >&2
      fi
    done
    echo >&2
    echo "On Ubuntu/Debian, install the listed packages with apt before rerunning." >&2
    exit 1
  fi
}

validate_hostname() {
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || die "--hostname must be a single DNS-safe label, 1-63 letters/digits/hyphens"
}

validate_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "--user must match: lowercase letter or underscore, then lowercase letters/digits/_/-, max 32 chars"
}

validate_fs_label() {
  local option value max_len
  option="$1"
  value="$2"
  max_len="$3"
  [[ "${#value}" -le "${max_len}" && "${value}" =~ ^[A-Za-z0-9_-]+$ ]] || die "${option} must be 1-${max_len} chars using only letters, digits, underscore, or hyphen"
}

validate_bootloader_id() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ && "$1" != *".."* ]] || die "--bootloader-id must be 1-64 safe path chars and must not contain '..'"
}

validate_mirror_url() {
  local option value
  option="$1"
  value="$2"
  [[ "${value}" =~ ^https?://[^[:space:]\"\'\<\>]+/$ ]] || die "${option} must be an http(s) URL ending in / with no whitespace"
}

validate_options() {
  [[ -n "${ISO_PATH}" || -n "${SOURCE_DIR}" ]] || die "pass either --iso PATH or --source DIR"
  [[ -z "${ISO_PATH}" || -z "${SOURCE_DIR}" ]] || die "pass only one of --iso or --source"
  [[ -n "${TARGET_ARG}" ]] || die "pass --target DEVICE"
  [[ "${PROFILE}" == "desktop" || "${PROFILE}" == "minimal" ]] || die "--profile must be desktop or minimal"
  [[ "${FINALIZE_MODE}" == "online" || "${FINALIZE_MODE}" == "offline" ]] || die "internal error: bad finalization mode"
  [[ "${COPY_PROGRESS}" == "periodic" || "${COPY_PROGRESS}" == "detailed" || "${COPY_PROGRESS}" == "never" ]] || die "--copy-progress must be periodic, detailed, or never"
  [[ "${PROMPT_PASSWORD}" -eq 0 || -z "${PASSWORD_HASH}" ]] || die "--prompt-password and --password-hash are mutually exclusive"
  [[ "${NO_USER}" -eq 0 || -z "${NEW_USER}" ]] || die "--no-user cannot be combined with --user"
  [[ "${NO_USER}" -eq 0 || "${PROMPT_PASSWORD}" -eq 0 ]] || die "--no-user cannot be combined with --prompt-password"
  [[ "${NO_USER}" -eq 0 || -z "${PASSWORD_HASH}" ]] || die "--no-user cannot be combined with --password-hash"
  [[ "${ROOTDELAY}" =~ ^[0-9]+$ ]] || die "--rootdelay must be a non-negative integer"
  [[ -z "${POST_INSTALL_SCRIPT}" || -f "${POST_INSTALL_SCRIPT}" ]] || die "--post-install-script is not a file: ${POST_INSTALL_SCRIPT}"
  validate_hostname "${TARGET_HOSTNAME}"
  validate_fs_label "--esp-label" "${ESP_LABEL}" 11
  validate_fs_label "--root-label" "${ROOT_LABEL}" 16
  validate_bootloader_id "${BOOTLOADER_ID}"
  validate_mirror_url "--apt-mirror" "${APT_MIRROR}"
  validate_mirror_url "--security-mirror" "${SECURITY_MIRROR}"

  if [[ -z "${NEW_USER}" && "${NO_USER}" -eq 0 ]]; then
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      NEW_USER="${SUDO_USER}"
    else
      die "no install user selected; pass --user NAME, or pass --no-user only if you will provision accounts another way"
    fi
  fi

  if [[ "${NO_USER}" -eq 0 && "${PROMPT_PASSWORD}" -eq 0 && -z "${PASSWORD_HASH}" && "${ALLOW_LOCKED_USER}" -eq 0 ]]; then
    die "user ${NEW_USER} needs a password choice; pass --prompt-password, --password-hash HASH, or --allow-locked-user"
  fi
  if [[ "${NO_USER}" -eq 0 ]]; then
    validate_username "${NEW_USER}"
  fi

  if [[ "${NO_USER}" -eq 1 ]]; then
    warn "--no-user selected; the installed desktop may not be usable until an account is provisioned another way"
  fi

  if [[ "${ALLOW_LOCKED_USER}" -eq 1 && "${NO_USER}" -eq 0 ]]; then
    warn "creating ${NEW_USER} with a locked password; normal password login will not work"
  fi
}

make_work_dirs() {
  WORK_DIR="$(mktemp -d /tmp/ubuntu-external-installer.XXXXXX)"
  TARGET_MNT="${WORK_DIR}/target"
  INSTALL_LOG="${WORK_DIR}/install.log"
  mkdir -p "${TARGET_MNT}"
  : >"${INSTALL_LOG}"
}

record_mount() {
  CREATED_MOUNTS+=("$1")
}

cleanup_mounts() {
  local mp
  set +e
  for ((i=${#CREATED_MOUNTS[@]}-1; i>=0; i--)); do
    mp="${CREATED_MOUNTS[$i]}"
    umount -R "${mp}" 2>/dev/null
  done
  CREATED_MOUNTS=()
  set -e
}

cleanup_image_mounts() {
  set +e
  if [[ -n "${IMAGE_WORK_DIR}" && -d "${IMAGE_WORK_DIR}" ]]; then
    umount "${IMAGE_WORK_DIR}/merged" 2>/dev/null
    find "${IMAGE_WORK_DIR}/layers" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | while read -r mp; do
      umount "${mp}" 2>/dev/null
    done
    rm -rf "${IMAGE_WORK_DIR}"
    IMAGE_WORK_DIR=""
  fi
  set -e
}

cleanup() {
  local exit_code=$?
  set +e
  if [[ -n "${ACTIVE_RSYNC_PID}" ]] && kill -0 "${ACTIVE_RSYNC_PID}" 2>/dev/null; then
    kill "${ACTIVE_RSYNC_PID}" 2>/dev/null
    wait "${ACTIVE_RSYNC_PID}" 2>/dev/null
  fi
  restore_chroot_resolver
  cleanup_mounts
  cleanup_image_mounts
  if [[ "${SOURCE_WAS_MOUNTED}" -eq 1 && -n "${SOURCE_MOUNT}" ]]; then
    umount "${SOURCE_MOUNT}" 2>/dev/null
  fi
  if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
    rm -rf "${WORK_DIR}"
  fi
  sync
  if [[ "${exit_code}" -ne 0 && "${TARGET_MODIFIED}" -eq 1 ]]; then
    echo "Install failed after target modification. The target disk may be partially installed." >&2
    echo "You can rerun the script to recreate it from scratch." >&2
  fi
  exit "${exit_code}"
}

prepare_chroot_resolver() {
  local target_resolv
  target_resolv="${TARGET_MNT}/etc/resolv.conf"
  RESOLV_BACKUP_PATH="${TARGET_MNT}/etc/resolv.conf.ubuntu-external-installer-backup"

  [[ -f /etc/resolv.conf ]] || return 0
  rm -f "${RESOLV_BACKUP_PATH}"
  if [[ -e "${target_resolv}" || -L "${target_resolv}" ]]; then
    mv "${target_resolv}" "${RESOLV_BACKUP_PATH}"
  fi
  cp /etc/resolv.conf "${target_resolv}"
}

restore_chroot_resolver() {
  local target_resolv
  [[ -n "${TARGET_MNT}" ]] || return 0
  target_resolv="${TARGET_MNT}/etc/resolv.conf"
  [[ -n "${RESOLV_BACKUP_PATH}" && -e "${RESOLV_BACKUP_PATH}" ]] || return 0

  rm -f "${target_resolv}"
  mv "${RESOLV_BACKUP_PATH}" "${target_resolv}"
  RESOLV_BACKUP_PATH=""
}

mount_source_if_needed() {
  if [[ -n "${ISO_PATH}" ]]; then
    [[ -f "${ISO_PATH}" ]] || die "ISO does not exist: ${ISO_PATH}"
    SOURCE_MOUNT="${WORK_DIR}/source"
    mkdir -p "${SOURCE_MOUNT}"
    mount -o loop,ro "${ISO_PATH}" "${SOURCE_MOUNT}"
    SOURCE_WAS_MOUNTED=1
    SOURCE_DIR="${SOURCE_MOUNT}"
    SOURCE_DESCRIPTION="ISO $(basename "${ISO_PATH}")"
  else
    [[ -d "${SOURCE_DIR}" ]] || die "source directory does not exist: ${SOURCE_DIR}"
    SOURCE_DIR="$(readlink -f "${SOURCE_DIR}")"
    SOURCE_DESCRIPTION="mounted source ${SOURCE_DIR}"
  fi
}

detect_source() {
  SOURCE_LAYERS=()
  if [[ -f "${SOURCE_DIR}/casper/filesystem.squashfs" ]]; then
    SOURCE_LAYOUT="single-casper"
    SOURCE_LAYERS=("${SOURCE_DIR}/casper/filesystem.squashfs")
  elif [[ -f "${SOURCE_DIR}/casper/minimal.squashfs" ]]; then
    SOURCE_LAYOUT="layered-casper"
    SOURCE_LAYERS=(
      "${SOURCE_DIR}/casper/minimal.squashfs"
    )
    [[ -f "${SOURCE_DIR}/casper/minimal.en.squashfs" ]] && SOURCE_LAYERS+=("${SOURCE_DIR}/casper/minimal.en.squashfs")
    if [[ "${PROFILE}" == "desktop" ]]; then
      [[ -f "${SOURCE_DIR}/casper/minimal.standard.squashfs" ]] || die "desktop profile needs ${SOURCE_DIR}/casper/minimal.standard.squashfs"
      SOURCE_LAYERS+=("${SOURCE_DIR}/casper/minimal.standard.squashfs")
      [[ -f "${SOURCE_DIR}/casper/minimal.standard.en.squashfs" ]] && SOURCE_LAYERS+=("${SOURCE_DIR}/casper/minimal.standard.en.squashfs")
    fi
  else
    die "unsupported source layout: expected Ubuntu Desktop casper filesystem.squashfs or minimal*.squashfs"
  fi

  if [[ -f "${SOURCE_DIR}/.disk/info" ]]; then
    local disk_info
    disk_info="$(head -n 1 "${SOURCE_DIR}/.disk/info" || true)"
    [[ "${disk_info}" == *"Ubuntu"* ]] || warn "source .disk/info does not look like Ubuntu: ${disk_info}"
    if [[ "${disk_info}" =~ Ubuntu[[:space:]]+([0-9][^[:space:]]*) ]]; then
      UBUNTU_VERSION="${BASH_REMATCH[1]}"
    fi
  else
    warn "source is missing .disk/info; continuing based on casper layout"
  fi

  if [[ -f "${SOURCE_DIR}/casper/filesystem.size" || -f "${SOURCE_DIR}/casper/filesystem.manifest" || "${SOURCE_LAYOUT}" == "layered-casper" ]]; then
    true
  fi
}

resolve_target_disk() {
  [[ -e "${TARGET_ARG}" ]] || die "target does not exist: ${TARGET_ARG}"
  TARGET_DISK="$(readlink -f "${TARGET_ARG}")"
  [[ -b "${TARGET_DISK}" ]] || die "target is not a block device: ${TARGET_DISK}"
}

target_children() {
  lsblk -nr -o PATH "${TARGET_DISK}" | tail -n +2
}

target_has_mounts() {
  local mounts
  mounts="$(lsblk -nr -o PATH,MOUNTPOINTS "${TARGET_DISK}" | awk 'NF > 1 {print}' || true)"
  [[ -n "${mounts}" ]]
}

unmount_target_children() {
  local child
  while read -r child; do
    [[ -n "${child}" ]] || continue
    if findmnt -rn --source "${child}" >/dev/null 2>&1; then
      umount "${child}" || die "failed to unmount ${child}"
    fi
    if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "${child}"; then
      swapoff "${child}" || die "failed to swapoff ${child}"
    fi
  done < <(target_children)
}

validate_target() {
  local type tran rm serial model size ro
  type="$(lsblk -dn -o TYPE "${TARGET_DISK}" | xargs)"
  tran="$(lsblk -dn -o TRAN "${TARGET_DISK}" | xargs || true)"
  rm="$(lsblk -dn -o RM "${TARGET_DISK}" | xargs || true)"
  serial="$(lsblk -dn -o SERIAL "${TARGET_DISK}" | xargs || true)"
  model="$(lsblk -dn -o MODEL "${TARGET_DISK}" | xargs || true)"
  size="$(lsblk -dn -o SIZE "${TARGET_DISK}" | xargs || true)"
  ro="$(lsblk -dn -o RO "${TARGET_DISK}" | xargs || true)"

  [[ "${type}" == "disk" ]] || die "target must be a whole disk; got type ${type} for ${TARGET_DISK}"
  [[ "${ro}" != "1" ]] || die "target is read-only: ${TARGET_DISK}"

  if target_has_mounts; then
    if [[ "${UNMOUNT_TARGET}" -eq 1 ]]; then
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        warn "target has mounted filesystems; --unmount-target would unmount them during a real install"
      else
        unmount_target_children
      fi
    else
      echo "error: target has mounted filesystems:" >&2
      lsblk -nr -o PATH,MOUNTPOINTS "${TARGET_DISK}" | awk 'NF > 1 {print "  " $0}' >&2
      echo "Unmount them and retry, or pass --unmount-target." >&2
      exit 1
    fi
  fi

  if [[ "${TARGET_DISK}" == /dev/loop* ]]; then
    [[ "${ALLOW_LOOP_TARGET}" -eq 1 ]] || die "loop targets require --allow-loop-target"
  elif [[ "${ALLOW_NON_USB}" -eq 0 && "${tran}" != "usb" && "${rm}" != "1" ]]; then
    die "target is not USB/removable (transport='${tran}', removable='${rm}'); pass --allow-non-usb to override"
  fi

  [[ -z "${EXPECT_SERIAL}" || "${serial}" == "${EXPECT_SERIAL}" ]] || die "serial mismatch: got '${serial}', expected '${EXPECT_SERIAL}'"
  [[ -z "${EXPECT_MODEL}" || "${model}" == *"${EXPECT_MODEL}"* ]] || die "model mismatch: got '${model}', expected substring '${EXPECT_MODEL}'"

  info "Target disk:"
  lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN,RM,TYPE,FSTYPE,MOUNTPOINTS,RO "${TARGET_DISK}"
  info
  info "Verified ${TARGET_DISK}: ${model:-unknown model}, serial ${serial:-unknown}, ${size:-unknown size}, transport ${tran:-unknown}."
}

partition_suffix() {
  case "${TARGET_DISK}" in
    *[0-9]|/dev/nvme*|/dev/mmcblk*) echo "p" ;;
    *) echo "" ;;
  esac
}

part_path() {
  local suffix
  suffix="$(partition_suffix)"
  echo "${TARGET_DISK}${suffix}$1"
}

source_target_overlap_check() {
  local source_device source_parent target_name
  target_name="$(basename "${TARGET_DISK}")"

  if [[ -n "${ISO_PATH}" ]]; then
    source_device="$(findmnt -T "${ISO_PATH}" -no SOURCE 2>/dev/null || true)"
  else
    source_device="$(findmnt -T "${SOURCE_DIR}" -no SOURCE 2>/dev/null || true)"
  fi
  [[ -n "${source_device}" ]] || return 0
  source_device="$(readlink -f "${source_device}" 2>/dev/null || echo "${source_device}")"
  source_parent="$(lsblk -no PKNAME "${source_device}" 2>/dev/null | head -n 1 | xargs || true)"
  if [[ "${source_device}" == "${TARGET_DISK}" || "${source_parent}" == "${target_name}" ]]; then
    die "source appears to live on the target disk; use a different disk for the ISO/source"
  fi
}

print_plan() {
  cat <<EOF
Install plan
============
Installer: ${INSTALLER_NAME} ${INSTALLER_VERSION}
Host mode: ${HOST_MODE}
Source: ${SOURCE_DESCRIPTION}
Detected Ubuntu version: ${UBUNTU_VERSION}
Source layout: ${SOURCE_LAYOUT}
Profile: ${PROFILE}
Target: ${TARGET_DISK}
Partition plan: GPT, ESP ${ESP_SIZE} FAT32 label=${ESP_LABEL}, root ext4 label=${ROOT_LABEL}
Hostname: ${TARGET_HOSTNAME}
User: $(if [[ "${NO_USER}" -eq 1 ]]; then echo "none"; else echo "${NEW_USER}"; fi)
Password: $(if [[ "${NO_USER}" -eq 1 ]]; then echo "n/a"; elif [[ "${PROMPT_PASSWORD}" -eq 1 ]]; then echo "prompt during install"; elif [[ -n "${PASSWORD_HASH}" ]]; then echo "hash provided"; else echo "locked"; fi)
Boot: UEFI x86_64 removable, bootloader-id=${BOOTLOADER_ID}, write-nvram=$(yes_no "${WRITE_NVRAM}")
Secure Boot goal: Ubuntu signed shim/GRUB packages when finalized online
Finalization: $(if [[ "${SKIP_FINALIZE}" -eq 1 ]]; then echo "skipped; result is not bootable"; else echo "${FINALIZE_MODE}"; fi)
Cloud-init: $(if [[ "${KEEP_CLOUD_INIT}" -eq 1 ]]; then echo "preserve"; else echo "disable"; fi)
Rootdelay: ${ROOTDELAY}
EOF
  echo "Layers:"
  printf '  %s\n' "${SOURCE_LAYERS[@]}"
}

yes_no() {
  if [[ "$1" -eq 1 ]]; then echo "yes"; else echo "no"; fi
}

confirm_destroy() {
  local expected answer
  [[ "${ASSUME_YES}" -eq 0 ]] || return 0
  expected="ERASE ${TARGET_DISK}"
  echo
  echo "This will ERASE ALL DATA on ${TARGET_DISK}."
  echo "Type exactly '${expected}' to continue:"
  read -r answer
  [[ "${answer}" == "${expected}" ]] || die "confirmation did not match; aborting"
}

partition_disk() {
  local esp root
  esp="$(part_path 1)"
  root="$(part_path 2)"

  TARGET_MODIFIED=1
  sgdisk --zap-all "${TARGET_DISK}"
  wipefs --all --force "${TARGET_DISK}"
  sgdisk \
    "--new=1:1MiB:+${ESP_SIZE}" --typecode=1:EF00 --change-name=1:EFI-SYSTEM \
    --new=2:0:0 --typecode=2:8304 --change-name=2:UBUNTU-ROOT \
    "${TARGET_DISK}"

  if command -v partprobe >/dev/null 2>&1; then
    partprobe "${TARGET_DISK}" || true
  else
    blockdev --rereadpt "${TARGET_DISK}" || true
  fi
  udevadm settle
  sleep 2

  [[ -b "${esp}" ]] || die "expected ${esp} to exist"
  [[ -b "${root}" ]] || die "expected ${root} to exist"

  mkfs.vfat -F32 -n "${ESP_LABEL}" "${esp}"
  mkfs.ext4 -F -L "${ROOT_LABEL}" "${root}"
}

mount_target() {
  local esp root
  esp="$(part_path 1)"
  root="$(part_path 2)"
  mount "${root}" "${TARGET_MNT}"
  record_mount "${TARGET_MNT}"
  mkdir -p "${TARGET_MNT}/boot/efi"
  mount "${esp}" "${TARGET_MNT}/boot/efi"
  record_mount "${TARGET_MNT}/boot/efi"
}

format_bytes() {
  local bytes="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "${bytes}" 2>/dev/null && return 0
  fi
  printf '%s bytes\n' "${bytes}"
}

estimate_copy_size() {
  local source_dir="$1"
  du -sb "${source_dir}" 2>/dev/null | awk '{print $1}'
}

print_copy_status() {
  local started_at="$1"
  local now elapsed

  now="$(date +%s)"
  elapsed=$((now - started_at))
  info "Still copying... elapsed $((elapsed / 60))m$((elapsed % 60))s."
}

rsync_copy_to_target() {
  local source_dir="$1" description="$2" estimated_bytes estimated_size
  local rsync_info="stats2"
  local rsync_pid started_at rsync_status

  estimated_bytes="$(estimate_copy_size "${source_dir}")"
  if [[ -n "${estimated_bytes}" ]]; then
    estimated_size="$(format_bytes "${estimated_bytes}")"
    info "${description} copy size is about ${estimated_size}."
  else
    info "${description} copy size could not be estimated."
  fi
  info "This is usually the longest step. On typical external USB storage it can take 10-90 minutes depending on target speed, source media, and host USB port."

  case "${COPY_PROGRESS}" in
    detailed)
      info "Detailed copy progress is enabled; rsync will update the same terminal line while files are copied."
      rsync -aAX --numeric-ids --info="${rsync_info},progress2" "${source_dir}"/ "${TARGET_MNT}"/
      ;;
    periodic)
      info "Periodic copy status is enabled; a short update will print every ${COPY_STATUS_INTERVAL}s."
      started_at="$(date +%s)"
      rsync -aAX --numeric-ids --info="${rsync_info}" "${source_dir}"/ "${TARGET_MNT}"/ &
      rsync_pid=$!
      ACTIVE_RSYNC_PID="${rsync_pid}"
      while kill -0 "${rsync_pid}" 2>/dev/null; do
        sleep "${COPY_STATUS_INTERVAL}"
        if kill -0 "${rsync_pid}" 2>/dev/null; then
          print_copy_status "${started_at}"
        fi
      done
      set +e
      wait "${rsync_pid}"
      rsync_status=$?
      set -e
      ACTIVE_RSYNC_PID=""
      return "${rsync_status}"
      ;;
    never)
      info "Copy progress is disabled. The next rsync summary appears after the copy finishes."
      rsync -aAX --numeric-ids --info="${rsync_info}" "${source_dir}"/ "${TARGET_MNT}"/
      ;;
  esac
}

mount_and_copy_source() {
  local lowerdir="" layer_count i src dest mp
  IMAGE_WORK_DIR="$(mktemp -d /tmp/ubuntu-external-image.XXXXXX)"
  mkdir -p "${IMAGE_WORK_DIR}/images" "${IMAGE_WORK_DIR}/layers" "${IMAGE_WORK_DIR}/merged"

  layer_count="${#SOURCE_LAYERS[@]}"
  for ((i = 0; i < layer_count; i++)); do
    src="${SOURCE_LAYERS[$i]}"
    dest="${IMAGE_WORK_DIR}/images/$(printf '%02d-%s' "${i}" "$(basename "${src}")")"
    mp="${IMAGE_WORK_DIR}/layers/$(printf '%02d' "${i}")"
    mkdir -p "${mp}"
    cp "${src}" "${dest}"
    mount -o loop,ro "${dest}" "${mp}"
  done

  if ((layer_count == 1)); then
    info "Copying Ubuntu filesystem to target..."
    rsync_copy_to_target "${IMAGE_WORK_DIR}/layers/00" "Ubuntu filesystem"
  else
    for ((i = layer_count - 1; i >= 0; i--)); do
      mp="${IMAGE_WORK_DIR}/layers/$(printf '%02d' "${i}")"
      if [[ -z "${lowerdir}" ]]; then
        lowerdir="${mp}"
      else
        lowerdir="${lowerdir}:${mp}"
      fi
    done
    mount -t overlay overlay -o "lowerdir=${lowerdir}" "${IMAGE_WORK_DIR}/merged"
    info "Copying merged Ubuntu filesystem to target..."
    rsync_copy_to_target "${IMAGE_WORK_DIR}/merged" "Merged Ubuntu filesystem"
  fi
  cleanup_image_mounts
}

detect_target_os_release() {
  if [[ -f "${TARGET_MNT}/etc/os-release" ]]; then
    local id version_id version_codename
    id="$(sed -n 's/^ID=//p' "${TARGET_MNT}/etc/os-release" | head -n 1 | tr -d '"')"
    version_id="$(sed -n 's/^VERSION_ID=//p' "${TARGET_MNT}/etc/os-release" | head -n 1 | tr -d '"')"
    version_codename="$(sed -n 's/^VERSION_CODENAME=//p' "${TARGET_MNT}/etc/os-release" | head -n 1 | tr -d '"')"
    UBUNTU_CODENAME="${version_codename:-${UBUNTU_CODENAME}}"
    UBUNTU_VERSION="${version_id:-${UBUNTU_VERSION}}"
    [[ "${id}" == "ubuntu" ]] || die "extracted system is not Ubuntu; got ID=${id:-unknown}"
  fi
}

write_apt_sources_if_needed() {
  local codename="$1"
  local sources_dir="${TARGET_MNT}/etc/apt/sources.list.d"
  local has_archive=0

  mkdir -p "${sources_dir}"
  if grep -Rqs "Suites: .*${codename}" "${TARGET_MNT}/etc/apt/sources.list" "${sources_dir}" 2>/dev/null ||
     grep -Rqs "${codename}" "${TARGET_MNT}/etc/apt/sources.list" "${sources_dir}" 2>/dev/null; then
    has_archive=1
  fi

  find "${sources_dir}" -maxdepth 1 -type f \( -name '*cdrom*.list' -o -name '*cdrom*.sources' \) -delete 2>/dev/null || true
  sed -i '/^[[:space:]]*deb cdrom:/d' "${TARGET_MNT}/etc/apt/sources.list" 2>/dev/null || true

  if [[ "${has_archive}" -eq 1 ]]; then
    return 0
  fi

  rm -f "${TARGET_MNT}/etc/apt/sources.list" "${TARGET_MNT}/etc/apt/sources.list.save"
  cat >"${sources_dir}/ubuntu.sources" <<EOF
Types: deb
URIs: ${APT_MIRROR}
Suites: ${codename} ${codename}-updates ${codename}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: ${SECURITY_MIRROR}
Suites: ${codename}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_installer_metadata() {
  local meta_dir="${TARGET_MNT}/etc"
  local user_value
  if [[ "${NO_USER}" -eq 1 ]]; then
    user_value=""
  else
    user_value="${NEW_USER}"
  fi

  cat >"${meta_dir}/ubuntu-external-installer.json" <<EOF
{
  "installer_name": "$(json_escape "${INSTALLER_NAME}")",
  "installer_version": "$(json_escape "${INSTALLER_VERSION}")",
  "installed_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source_type": "$(if [[ -n "${ISO_PATH}" ]]; then echo "iso"; else echo "source"; fi)",
  "source_basename": "$(json_escape "$(if [[ -n "${ISO_PATH}" ]]; then basename "${ISO_PATH}"; else basename "${SOURCE_DIR}"; fi)")",
  "ubuntu_version": "$(json_escape "${UBUNTU_VERSION}")",
  "ubuntu_codename": "$(json_escape "${UBUNTU_CODENAME}")",
  "profile": "$(json_escape "${PROFILE}")",
  "target_root_label": "$(json_escape "${ROOT_LABEL}")",
  "target_esp_label": "$(json_escape "${ESP_LABEL}")",
  "boot_mode": "uefi-removable",
  "created_user": "$(json_escape "${user_value}")",
  "hostname": "$(json_escape "${TARGET_HOSTNAME}")"
}
EOF
}

write_efi_grub_fallback_config() {
  local root_uuid esp_dir esp_boot_grub_dir
  root_uuid="$(blkid -s UUID -o value "$(part_path 2)")"
  esp_dir="${TARGET_MNT}/boot/efi/EFI"
  esp_boot_grub_dir="${TARGET_MNT}/boot/efi/boot/grub"

  # Removable GRUB may start without an embedded prefix that points at the
  # external root filesystem. Keep a tiny ESP-side handoff by UUID.
  mkdir -p "${esp_dir}/BOOT" "${esp_dir}/${BOOTLOADER_ID}" "${esp_dir}/ubuntu" "${esp_boot_grub_dir}"
  cat >"${esp_dir}/BOOT/grub.cfg" <<EOF
search.fs_uuid ${root_uuid} root
set prefix=(\$root)'/boot/grub'
configfile \$prefix/grub.cfg
EOF
  cp "${esp_dir}/BOOT/grub.cfg" "${esp_dir}/${BOOTLOADER_ID}/grub.cfg"
  cp "${esp_dir}/BOOT/grub.cfg" "${esp_dir}/ubuntu/grub.cfg"
  cp "${esp_dir}/BOOT/grub.cfg" "${esp_boot_grub_dir}/grub.cfg"
}

install_report_script() {
  mkdir -p "${TARGET_MNT}/usr/local/sbin"
  cat >"${TARGET_MNT}/usr/local/sbin/ubuntu-external-report" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

OUTPUT=""
VERBOSE=0
INCLUDE_NETWORK=0
INCLUDE_HARDWARE_IDS=0
INCLUDE_FULL_JOURNAL=0
NETWORK_CHECK=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="${2:-}"; shift 2 ;;
    --verbose) VERBOSE=1; shift ;;
    --include-network-details) INCLUDE_NETWORK=1; shift ;;
    --include-hardware-ids) INCLUDE_HARDWARE_IDS=1; shift ;;
    --include-full-journal) INCLUDE_FULL_JOURNAL=1; shift ;;
    --no-network-check) NETWORK_CHECK=0; shift ;;
    --help|-h)
      cat <<'HELP'
Usage: sudo ubuntu-external-report [--output PATH] [--verbose]
       [--include-network-details] [--include-hardware-ids]
       [--include-full-journal] [--no-network-check]
HELP
      exit 0
      ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -n "${OUTPUT}" ]]; then
  exec >"${OUTPUT}"
fi

status() {
  printf '%-5s %s\n' "$1" "$2"
}

section() {
  printf '\n## %s\n' "$1"
}

cmd() {
  echo "+ $*"
  "$@" 2>&1 || true
}

redact_report() {
  local sed_args=(
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<redacted-ipv4>/g'
    -e 's/([[:xdigit:]]{1,4}:){2,}[[:xdigit:]:]+/<redacted-ipv6>/g'
    -e 's/(DNS server list to: ).*/\1<redacted-dns-servers>/'
    -e 's/(search domain list to: ).*/\1<redacted-search-domains>/'
  )

  if [[ "${INCLUDE_HARDWARE_IDS}" -eq 0 ]]; then
    sed_args+=(
      -e 's/[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}/<redacted-uuid>/g'
      -e 's/(Hardware Serial: ).*/\1<redacted>/'
      -e 's/(Product UUID: ).*/\1<redacted>/'
      -e 's/(Machine ID: ).*/\1<redacted>/'
      -e 's/(Boot ID: ).*/\1<redacted>/'
      -e 's/(Static hostname: ).*/\1<redacted>/'
      -e 's/("created_user": ")[^"]*(")/\1<redacted>\2/'
      -e 's/("hostname": ")[^"]*(")/\1<redacted>\2/'
    )
  fi

  if [[ "${INCLUDE_NETWORK}" -eq 1 ]]; then
    if [[ "${INCLUDE_HARDWARE_IDS}" -eq 1 ]]; then
      cat
    else
      sed -E "${sed_args[@]:4}"
    fi
  else
    sed -E "${sed_args[@]}"
  fi
}

cmd_redacted() {
  echo "+ $*"
  "$@" 2>&1 | redact_report || true
}

echo "ubuntu-external-report"
echo "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

section "Summary"
if [[ -d /sys/firmware/efi ]]; then status PASS "booted in UEFI mode"; else status FAIL "not booted in UEFI mode"; fi
if findmnt / >/dev/null; then status PASS "root filesystem is mounted"; else status FAIL "root filesystem is not visible to findmnt"; fi
if findmnt /boot/efi >/dev/null; then status PASS "/boot/efi is mounted"; else status FAIL "/boot/efi is not mounted"; fi
if [[ -f /boot/efi/EFI/BOOT/BOOTX64.EFI ]]; then status PASS "removable UEFI fallback bootloader exists"; else status FAIL "missing /boot/efi/EFI/BOOT/BOOTX64.EFI"; fi
if [[ -f /boot/efi/boot/grub/grub.cfg ]]; then status PASS "ESP /boot/grub GRUB handoff exists"; else status WARN "missing /boot/efi/boot/grub/grub.cfg handoff"; fi
if grep -q 'set timeout=10' /boot/grub/grub.cfg 2>/dev/null; then status PASS "GRUB menu timeout includes 10 seconds"; else status WARN "GRUB menu timeout is not confirmed as 10 seconds"; fi
if systemctl is-enabled NetworkManager.service >/dev/null 2>&1 || systemctl is-active NetworkManager.service >/dev/null 2>&1; then status PASS "NetworkManager is enabled or active"; else status WARN "NetworkManager is not enabled/active"; fi
if [[ -s /etc/machine-id ]]; then status PASS "machine-id exists"; else status WARN "machine-id is empty or missing"; fi

section "Installer Metadata"
if [[ -f /etc/ubuntu-external-installer.json ]]; then
  redact_report < /etc/ubuntu-external-installer.json
else
  status WARN "missing /etc/ubuntu-external-installer.json"
fi

section "System"
cmd cat /etc/os-release
cmd uname -srmo
cmd_redacted hostnamectl
if command -v mokutil >/dev/null 2>&1; then cmd mokutil --sb-state; else status WARN "mokutil not installed; Secure Boot state unknown"; fi

section "Mounts"
cmd findmnt /
cmd findmnt /boot/efi
if [[ "${INCLUDE_HARDWARE_IDS}" -eq 1 ]]; then
  cmd lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,RM,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
else
  cmd lsblk -o NAME,SIZE,MODEL,TRAN,RM,TYPE,FSTYPE,MOUNTPOINTS
fi

section "Boot Files"
cmd find /boot/efi -maxdepth 5 -type f
cmd_redacted sh -c "grep -HnE 'search.fs_uuid|set prefix|configfile' /boot/efi/EFI/BOOT/grub.cfg /boot/efi/EFI/ubuntu/grub.cfg /boot/efi/EFI/ubuntu-external/grub.cfg /boot/efi/boot/grub/grub.cfg 2>/dev/null || true"
cmd sh -c "grep -nE 'recordfail|set timeout=|timeout_style' /boot/grub/grub.cfg 2>/dev/null | head -40 || true"
cmd_redacted cat /proc/cmdline

section "Users"
created_user="$(sed -n 's/.*"created_user": "\([^"]*\)".*/\1/p' /etc/ubuntu-external-installer.json 2>/dev/null || true)"
if [[ -n "${created_user}" ]]; then
  if id "${created_user}" >/dev/null 2>&1; then
    if [[ "${INCLUDE_HARDWARE_IDS}" -eq 1 ]]; then
      status PASS "created user exists: ${created_user}"
      id "${created_user}" || true
    else
      status PASS "created user exists"
    fi
  else
    status FAIL "created user is missing"
  fi
else
  status WARN "installer metadata has no created_user"
fi

section "Services"
cmd_redacted systemctl --no-pager --full --lines=0 status NetworkManager.service
cmd_redacted systemctl --no-pager --full --lines=0 status gdm.service
cmd_redacted systemctl --no-pager --full --lines=0 status fstrim.timer

section "Resolver"
cmd ls -l /etc/resolv.conf
cmd sh -c "readlink -f /etc/resolv.conf || true"
cmd_redacted systemctl --no-pager --full --lines=0 status systemd-resolved.service

section "Apt"
cmd find /etc/apt -maxdepth 3 -type f \( -name '*.list' -o -name '*.sources' \) -print
if [[ "${NETWORK_CHECK}" -eq 1 ]]; then
  echo "+ apt-get update -o Debug::NoLocking=1"
  apt-get update -o Debug::NoLocking=1 2>&1 | redact_report || status WARN "apt-get update failed"
else
  status WARN "network apt check skipped"
fi

section "Focused Journal"
if command -v journalctl >/dev/null 2>&1; then
  if [[ "${INCLUDE_FULL_JOURNAL}" -eq 1 ]]; then
    journalctl -b --no-pager 2>&1 | redact_report || true
  else
    status WARN "journal output skipped by default; rerun with --include-full-journal after review if needed"
  fi
else
  status WARN "journalctl is not available"
fi

if [[ "${VERBOSE}" -eq 1 ]]; then
  section "Verbose Package Checks"
  cmd dpkg -l grub-efi-amd64-signed shim-signed efibootmgr sudo
fi

if [[ -n "${OUTPUT}" ]]; then
  echo
  echo "Report written to ${OUTPUT}" >&2
fi
EOF
  chmod 0755 "${TARGET_MNT}/usr/local/sbin/ubuntu-external-report"
}

write_system_config() {
  local root_uuid esp_uuid codename
  root_uuid="$(blkid -s UUID -o value "$(part_path 2)")"
  esp_uuid="$(blkid -s UUID -o value "$(part_path 1)")"
  codename="${UBUNTU_CODENAME}"
  [[ "${codename}" != "unknown" && -n "${codename}" ]] || die "could not detect Ubuntu codename from extracted system"

  cat >"${TARGET_MNT}/etc/fstab" <<EOF
UUID=${root_uuid} / ext4 defaults,noatime,errors=remount-ro 0 1
UUID=${esp_uuid} /boot/efi vfat umask=0077 0 1
EOF

  printf '%s\n' "${TARGET_HOSTNAME}" >"${TARGET_MNT}/etc/hostname"
  cat >"${TARGET_MNT}/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 ${TARGET_HOSTNAME}

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

  write_apt_sources_if_needed "${codename}"

  if [[ "${KEEP_CLOUD_INIT}" -eq 0 ]]; then
    mkdir -p "${TARGET_MNT}/etc/cloud"
    touch "${TARGET_MNT}/etc/cloud/cloud-init.disabled"
  fi
  : >"${TARGET_MNT}/etc/machine-id"
  rm -f "${TARGET_MNT}/var/lib/dbus/machine-id"

  mkdir -p "${TARGET_MNT}/etc/default/grub.d"
cat >"${TARGET_MNT}/etc/default/grub.d/99-usb-root.cfg" <<EOF
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash rootdelay=${ROOTDELAY}"
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
GRUB_RECORDFAIL_TIMEOUT=10
GRUB_DISABLE_OS_PROBER=true
EOF

  mkdir -p "${TARGET_MNT}/var/log/ubuntu-external-installer"
  cp "${INSTALL_LOG}" "${TARGET_MNT}/var/log/ubuntu-external-installer/install.log"
  write_installer_metadata
  install_report_script
}

bind_mounts() {
  mount --bind /dev "${TARGET_MNT}/dev"; record_mount "${TARGET_MNT}/dev"
  mount --bind /dev/pts "${TARGET_MNT}/dev/pts"; record_mount "${TARGET_MNT}/dev/pts"
  mount -t proc proc "${TARGET_MNT}/proc"; record_mount "${TARGET_MNT}/proc"
  mount -t sysfs sys "${TARGET_MNT}/sys"; record_mount "${TARGET_MNT}/sys"
  mount --bind /run "${TARGET_MNT}/run"; record_mount "${TARGET_MNT}/run"
}

run_chroot_finalization() {
  local grub_args=()
  prepare_chroot_resolver
  bind_mounts

  if [[ "${FINALIZE_MODE}" == "online" ]]; then
    chroot "${TARGET_MNT}" /bin/bash -eux <<'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y grub-efi-amd64-signed shim-signed efibootmgr sudo
systemctl enable NetworkManager.service || true
systemctl enable gdm.service || true
systemctl enable fstrim.timer || true
update-initramfs -u -k all
EOF
  else
    chroot "${TARGET_MNT}" /bin/bash -eux <<'EOF'
command -v grub-install
command -v update-grub
dpkg -s grub-efi-amd64-signed shim-signed sudo >/dev/null
systemctl enable NetworkManager.service || true
systemctl enable gdm.service || true
systemctl enable fstrim.timer || true
update-initramfs -u -k all
EOF
  fi
  restore_chroot_resolver

  if [[ "${NO_USER}" -eq 0 ]]; then
    if ! chroot "${TARGET_MNT}" id -u -- "${NEW_USER}" >/dev/null 2>&1; then
      chroot "${TARGET_MNT}" useradd -m -s /bin/bash -G sudo,adm,cdrom,dip,plugdev -- "${NEW_USER}"
    fi
    if [[ -n "${PASSWORD_HASH}" ]]; then
      chroot "${TARGET_MNT}" usermod -p "${PASSWORD_HASH}" -- "${NEW_USER}"
    elif [[ "${PROMPT_PASSWORD}" -eq 1 ]]; then
      echo
      echo "Set the password for ${NEW_USER} in the new Ubuntu install:"
      chroot "${TARGET_MNT}" passwd -- "${NEW_USER}"
    else
      chroot "${TARGET_MNT}" passwd -l -- "${NEW_USER}" >/dev/null
    fi
  fi

  grub_args=(
    --target=x86_64-efi
    --efi-directory=/boot/efi
    "--bootloader-id=${BOOTLOADER_ID}"
    --recheck
  )
  if [[ "${WRITE_NVRAM}" -eq 0 ]]; then
    grub_args+=(--removable --no-nvram)
  fi

  chroot "${TARGET_MNT}" grub-install "${grub_args[@]}" "${TARGET_DISK}"
  chroot "${TARGET_MNT}" update-grub
  write_efi_grub_fallback_config

  if [[ -n "${POST_INSTALL_SCRIPT}" ]]; then
    cp "${POST_INSTALL_SCRIPT}" "${TARGET_MNT}/tmp/ubuntu-external-post-install.sh"
    chmod 0700 "${TARGET_MNT}/tmp/ubuntu-external-post-install.sh"
    chroot "${TARGET_MNT}" /usr/bin/env \
      "TARGET_HOSTNAME=${TARGET_HOSTNAME}" \
      "NEW_USER=${NEW_USER}" \
      "UBUNTU_CODENAME=${UBUNTU_CODENAME}" \
      /bin/bash /tmp/ubuntu-external-post-install.sh
    rm -f "${TARGET_MNT}/tmp/ubuntu-external-post-install.sh"
  fi
}

finalize_install() {
  sync
  cleanup_mounts
  sync
  TARGET_MODIFIED=0
}

run_install() {
  print_plan | tee -a "${INSTALL_LOG}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo
    echo "Dry run complete. No target changes were made."
    return 0
  fi

  confirm_destroy
  exec > >(tee -a "${INSTALL_LOG}") 2>&1
  partition_disk
  mount_target
  mount_and_copy_source
  detect_target_os_release
  write_system_config

  if [[ "${SKIP_FINALIZE}" -eq 1 ]]; then
    warn "--skip-finalize selected; result is not expected to boot"
  else
    run_chroot_finalization
    cp "${INSTALL_LOG}" "${TARGET_MNT}/var/log/ubuntu-external-installer/install.log"
  fi

  finalize_install
  echo
  echo "Done. The target should now be bootable as a UEFI removable Ubuntu external drive."
  echo "After first boot, run: sudo ubuntu-external-report --output ubuntu-external-report.txt"
}

main() {
  parse_args "$@"
  require_root
  detect_host_mode
  print_wsl2_guidance
  check_architecture
  validate_options
  check_host_dependencies
  make_work_dirs
  trap cleanup EXIT
  mount_source_if_needed
  detect_source
  resolve_target_disk
  validate_target
  source_target_overlap_check
  run_install
  trap - EXIT
  cleanup
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

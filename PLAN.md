# Ubuntu External Drive Installer Plan

## Goal

Create a shareable installer for putting Ubuntu Desktop amd64 onto an external USB/removable drive. The original target was a Sabrent USB4 NVMe enclosure, but v1 should work for ordinary USB sticks and external SSDs too.

## Non-Goals For v1

- Non-Ubuntu distributions.
- Ubuntu Server/Subiquity installers.
- BIOS/legacy boot.
- ARM or cross-architecture installs.
- Disk encryption, btrfs, ZFS, swap, or separate `/home`.
- Automatic ISO download.
- Windows-side `wsl --mount` automation.
- Full rollback after target disk modification.

## User-Facing Files

- `install-ubuntu-external.sh`: main installer.
- `README.md`: usage, warnings, WSL2 notes, tested matrix, troubleshooting, issue-reporting guidance.
- `tests/`: fast Bash tests plus optional loopback/manual helpers.
- `tests/manual-boot-checklist.md`: boot validation checklist.
- `.github/ISSUE_TEMPLATE/bug_report.md`: structured bug reports.

## CLI Shape

Required/primary options:

- `--iso PATH`: preferred input; loop-mount an Ubuntu Desktop ISO read-only.
- `--source DIR`: use an already mounted installer filesystem.
- `--target DEVICE`: target whole disk or stable `/dev/disk/by-id/...` path.
- `--user NAME`: create an install user.
- `--prompt-password` or `--password-hash HASH`: make the install usable at first boot.

Safety and automation:

- `--dry-run`: validate and print the plan only.
- `--yes`: skip the destructive confirmation prompt only.
- `--expect-serial SERIAL`
- `--expect-model TEXT`
- `--allow-non-usb`
- `--allow-loop-target`
- `--unmount-target`

Install behavior:

- `--profile desktop|minimal`
- `--hostname NAME`
- `--esp-size SIZE`
- `--esp-label LABEL`
- `--root-label LABEL`
- `--rootdelay SECONDS`
- `--bootloader-id NAME`
- `--write-nvram`
- `--online`
- `--offline`
- `--keep-cloud-init`
- `--apt-mirror URL`
- `--security-mirror URL`
- `--post-install-script PATH`
- `--allow-locked-user`
- `--no-user`
- `--skip-finalize`
- `--version`
- `--help`

## Safety Model

- Fail before destructive work if required host commands are missing.
- Collect all missing dependencies and print package hints for Ubuntu/Debian.
- Require `--target`; never hardcode a disk.
- Resolve the target to a whole disk.
- Refuse mounted target filesystems by default.
- If `--unmount-target` is passed, unmount/swapoff only devices belonging to the target.
- Require USB/removable transport by default.
- Allow loop devices only with `--allow-loop-target`.
- Reject source and target overlap.
- Print source, target, partition plan, profile, user, boot mode, and finalization mode before wiping.
- Require confirmation text `ERASE <resolved-disk>` unless `--yes` is passed.

## Supported Source Layouts

Detect and support Ubuntu Desktop amd64 live ISO casper layouts:

- Single root filesystem: `casper/filesystem.squashfs`.
- Layered filesystem: `casper/minimal*.squashfs`, with `--profile minimal|desktop`.

Fail with a useful diagnostic for unsupported layouts, including Ubuntu Server/Subiquity images.

## Install Flow

1. Parse CLI options.
2. Check host dependencies.
3. Detect host mode: native Linux or WSL2.
4. Mount ISO or validate mounted source.
5. Detect Ubuntu release/codename/architecture/source layout.
6. Resolve and validate target disk.
7. Validate user/password choices.
8. Print plan or exit for `--dry-run`.
9. Confirm destructive action.
10. Partition target as GPT:
    - ESP: FAT32, default 1128 MiB.
    - Root: ext4, rest of disk.
11. Extract root filesystem from squashfs source.
12. Write target config:
    - `/etc/fstab`
    - hostname and hosts
    - apt sources only if missing or installer-media-specific
    - machine-id reset
    - optional cloud-init disable
    - grub rootdelay config
    - installer metadata and install log
    - post-boot diagnostic script
13. Online finalization by default:
    - install boot/admin packages.
    - enable core desktop services when present.
    - update initramfs.
    - create user and set password/hash.
    - install UEFI removable GRUB.
14. Optional post-install script.
15. Cleanup mounts/temp state and sync.

## Boot Strategy

Default to UEFI x86_64 removable boot:

- `grub-install --target=x86_64-efi`
- `--removable`
- `--no-nvram`
- signed Ubuntu shim/GRUB packages for Secure Boot compatibility

`--write-nvram` is advanced and off by default.

## WSL2 Support

Detect WSL2 and print focused guidance. The script validates the Linux-side environment, but does not call Windows `wsl.exe` or attach disks automatically.

README covers:

- identifying the Windows disk,
- attaching with elevated PowerShell,
- confirming with `lsblk`,
- dry-running,
- installing,
- detaching safely.

## Post-Boot Diagnostic Report

Install `/usr/local/sbin/ubuntu-external-report` by default.

Default report should be privacy-conscious and GitHub-issue friendly:

- PASS/WARN/FAIL summary lines.
- installer version and redacted metadata.
- distro, kernel, boot mode, Secure Boot status if available.
- root and ESP mount status.
- ESP bootloader file checks.
- kernel command line/rootdelay.
- user/group sanity for the configured install user.
- NetworkManager status.
- apt source sanity.
- block-device overview.
- focused journal excerpts for failing checks.

Optional flags:

- `--output PATH`
- `--verbose`
- `--include-network-details`
- `--include-full-journal`
- `--no-network-check`

Documentation must tell users to review reports before uploading them to GitHub issues.

## Testing Strategy

Tier 1: fast local tests.

- `shellcheck` when available.
- argument parsing.
- source layout detection with fixtures.
- config file generation.
- dependency report behavior.

Tier 2: loopback destructive rehearsal.

- create sparse disk image.
- attach with `losetup`.
- partition/format/mount/configure with fake source root.
- verify labels, partitions, fstab, metadata, cleanup.

Tier 3: manual boot validation.

- use a real Ubuntu Desktop ISO.
- install to the 128GB USB stick.
- boot laptop.
- verify UEFI boot, optional Secure Boot, login, networking, apt, reboot.
- run `sudo ubuntu-external-report --output ubuntu-external-report.txt`.

## Documentation Promises

README must distinguish:

- **Tested**: actually installed and booted versions/devices.
- **Recognized source layouts**: ISO layouts the script knows how to process.
- **Unsupported**: things outside v1 scope.

The repo should not claim broad Sabrent-specific validation until a Sabrent enclosure is tested again.

# Ubuntu External Drive Installer

[![Synthetic tests](https://github.com/lobo235/ubuntu-external-install/workflows/Synthetic%20tests/badge.svg)](https://github.com/lobo235/ubuntu-external-install/actions/workflows/synthetic-tests.yml)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-enabled-brightgreen)](https://www.shellcheck.net/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Installs Ubuntu Desktop amd64 from a local ISO or mounted installer source onto an external USB/removable drive using a UEFI removable bootloader. This was originally built for a Sabrent USB4 NVMe enclosure, but the v1 target is any external USB/removable drive.

This script is destructive. It repartitions and formats the target disk.

## Agent-Guided Install

If you want Claude Code, Codex, OpenCode, or another local coding agent to walk you through the install, paste this into the agent:

```text
Help me install Ubuntu 26.04 Desktop amd64 onto an external drive using https://github.com/lobo235/ubuntu-external-install. Download the repository, read AGENT_INSTALL_PROMPT.md and SECURITY.md, and follow them exactly. Ask me the required questions one at a time, identify the target disk safely, run a dry-run first, use the safest target guards available, and do not run destructive commands until I explicitly confirm the dry-run plan.
```

The full agent prompt lives in [`AGENT_INSTALL_PROMPT.md`](AGENT_INSTALL_PROMPT.md).

## Supported Scope

Tested:

- Created a Ubuntu 26.04 Desktop amd64 install on a 128GB Samsung USB flash drive from native Linux.
- Booted that USB on a Dell laptop, reached the desktop, and logged in successfully.

Recognized source layouts:

- Ubuntu Desktop amd64 live ISO with `casper/filesystem.squashfs`.
- Ubuntu Desktop amd64 live ISO with layered `casper/minimal*.squashfs`.

Unsupported in v1:

- Ubuntu Server/Subiquity ISOs.
- Non-Ubuntu distributions.
- BIOS/legacy boot.
- ARM or cross-architecture installs.
- Encryption, btrfs, ZFS, swap, or separate `/home`.
- Automatic ISO downloads.

## Install Dependencies

The installer checks dependencies before destructive work and reports all missing commands it can detect.

On Ubuntu/Debian hosts, these packages are typically needed:

```bash
sudo apt install gdisk dosfstools e2fsprogs rsync util-linux udev coreutils findutils
```

`shellcheck` is optional and only used by tests if installed.

## Basic Usage

Prefer a stable target path under `/dev/disk/by-id/`.

```bash
sudo ./install-ubuntu-external.sh --dry-run \
  --iso ~/Downloads/ubuntu-26.04-desktop-amd64.iso \
  --target /dev/disk/by-id/usb-... \
  --user alice \
  --prompt-password
```

If the plan looks right:

```bash
sudo ./install-ubuntu-external.sh \
  --iso ~/Downloads/ubuntu-26.04-desktop-amd64.iso \
  --target /dev/disk/by-id/usb-... \
  --user alice \
  --prompt-password
```

## Source Options

Use an ISO file:

```bash
sudo ./install-ubuntu-external.sh --iso ubuntu.iso --target /dev/disk/by-id/usb-... --user alice --prompt-password
```

Use an already mounted installer filesystem:

```bash
sudo ./install-ubuntu-external.sh --source /mnt/ubuntu-installer --target /dev/disk/by-id/usb-... --user alice --prompt-password
```

The source must not live on the same disk as the target.

## Safety Options

Useful target guards:

```bash
--expect-serial SERIAL
--expect-model TEXT
```

By default, the target must be a USB/removable whole disk. Advanced overrides:

```bash
--allow-non-usb
--allow-loop-target
```

Mounted target filesystems cause an error by default. To let the script unmount target children:

```bash
--unmount-target
```

Automation can skip the prompt with:

```bash
--yes
```

`--yes` skips only the confirmation prompt. It does not skip safety validation.

## Users And Passwords

A usable desktop install needs a user. Pass `--user NAME`, or let the script infer the sudo user when possible.

For normal installs, use:

```bash
--prompt-password
```

For automation:

```bash
--password-hash '...'
```

Advanced modes:

```bash
--allow-locked-user
--no-user
```

These can produce a system that boots but is not practically usable until accounts are provisioned another way.

## Boot Model

v1 is UEFI x86_64 only. By default it installs Ubuntu signed shim/GRUB packages and writes the removable fallback path without touching firmware NVRAM:

```text
/EFI/BOOT/BOOTX64.EFI
```

Advanced users can pass `--write-nvram`, but portable external drives should normally avoid it.

## WSL2 Notes

The script can run from WSL2 if the Linux side has the needed block devices, mount features, and chroot support. It does not attach Windows disks for you.

Typical flow:

1. In elevated PowerShell, identify the external disk carefully.
   ```powershell
   Get-Disk | Format-Table Number,FriendlyName,SerialNumber,Size,BusType,PartitionStyle,OperationalStatus
   ```
2. Attach it to WSL:
   ```powershell
   wsl --mount --bare \\.\PHYSICALDRIVE<N>
   ```
3. In WSL, confirm the target:
   ```bash
   lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN,TYPE,FSTYPE,MOUNTPOINTS
   ```
4. Run the installer with `--dry-run`.
5. Confirm the dry-run target disk, model, serial, size, and transport before running the real install.
6. Shut down WSL or detach the disk from Windows before unplugging.

Do not select the Windows system disk.

## Post-Boot Report

The installer places this diagnostic script in the target system:

```bash
sudo ubuntu-external-report --output ubuntu-external-report.txt
```

The default report is intended to be safe enough for GitHub issues, but review it before uploading. It avoids full journals, full network details, raw hardware serials, SSH keys, command history, and arbitrary config dumps.

Only include more detail if requested and after review:

```bash
sudo ubuntu-external-report --include-network-details --output report.txt
sudo ubuntu-external-report --include-hardware-ids --output report.txt
sudo ubuntu-external-report --include-full-journal --output report.txt
```

## Reporting Issues

Open a GitHub issue with:

- Ubuntu ISO filename/version.
- Host environment: WSL2 or native Linux, and distro/version.
- Target type: USB stick, Sabrent enclosure, or other external drive.
- Command used, with personal paths redacted.
- Failure phase: dry-run, partition, extract, finalize, first boot, login, networking.
- Whether Secure Boot was enabled.
- `ubuntu-external-report` output if the system booted far enough to run it.

Review reports before uploading. Do not include private paths, IP addresses, DNS domains, hardware serials, Wi-Fi SSIDs, SSH keys, or full journals unless you have checked them.

## Tests

Run all local checks:

```bash
make check
```

Or run non-destructive tests directly:

```bash
tests/run.sh
```

Useful targets:

```bash
make lint
make test
make help
```

The destructive loopback/manual tests are still planned; see `PLAN.md`.

GitHub Actions runs `make check` on push and pull requests without downloading full Ubuntu ISOs. Real USB boot validation remains manual; use `tests/manual-boot-checklist.md`.

## Repository Metadata

Suggested GitHub description and topics are in [`.github/REPOSITORY_METADATA.md`](.github/REPOSITORY_METADATA.md).

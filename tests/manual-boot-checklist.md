# Manual Boot Checklist

Use this after installing to a real USB stick or external SSD.

This checklist can contain private identifiers. Do not publish it raw without redacting serials, UUIDs, usernames, hostnames, private paths, DNS domains, and IP addresses.

## Install Facts

- Installer version:
- Ubuntu ISO filename:
- Ubuntu ISO checksum, if verified:
- Host environment: WSL2 or native Linux:
- Host distro/version:
- Target device model/size:
- Target device serial, if available:
- Command used, with personal paths redacted:
- Secure Boot enabled: yes/no:

## Firmware Boot

- Firmware shows the USB/external drive as a boot option: pass/fail
- GRUB appears: pass/fail
- Ubuntu starts booting: pass/fail
- GDM/login screen appears: pass/fail

## Login And Basic Use

- Created user can log in: pass/fail
- `sudo` works for created user: pass/fail
- Network/Wi-Fi works: pass/fail
- `sudo apt update` works: pass/fail
- Reboot from the installed system works: pass/fail
- Shutdown from the installed system works: pass/fail

## Post-Boot Commands

Run:

```bash
sudo ubuntu-external-report --output ubuntu-external-report.txt
```

Optional local checks:

```bash
findmnt /
findmnt /boot/efi
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN,FSTYPE,LABEL,UUID,MOUNTPOINTS
bootctl status || true
sudo efibootmgr -v || true
```

Review `ubuntu-external-report.txt` before sharing it.

## Notes

- Anything surprising in firmware boot picker:
- Exact failure text or screenshot summary:
- Hardware-specific notes:

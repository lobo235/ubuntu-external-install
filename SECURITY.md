# Security Policy

## Reporting A Vulnerability

Please report security issues through GitHub Private Vulnerability Reporting for this repository. Private reporting should be enabled before the first public release.

If private reporting is unexpectedly unavailable, open a public issue with only a minimal description, no exploit details, and a request for a private contact path.

Do not paste secrets, SSH keys, full shell history, unreviewed diagnostic reports, or private network details into public issues.

## Data Loss Risk

`install-ubuntu-external.sh` is intentionally destructive. It repartitions and formats the selected target disk.

The installer includes safeguards such as whole-disk checks, USB/removable target checks, mounted-filesystem checks, optional serial/model assertions, a dry-run mode, and an exact destructive confirmation prompt. These checks reduce risk, but they do not replace careful operator review.

Before running a real install:

- Use only a trusted Ubuntu ISO or mounted installer source.
- Verify downloaded ISOs before use. Follow Ubuntu's official verification guide: <https://ubuntu.com/tutorials/how-to-verify-ubuntu>.
- Prefer a stable `/dev/disk/by-id/...` target path.
- Run `--dry-run` first.
- Use `--expect-serial` when the target exposes a serial number.
- Read the printed target disk, model, serial, size, and partition plan.
- Keep backups of anything important.

## Trusted Installer Sources

Treat the ISO or mounted source as trusted code. The installer copies that system to the target and then performs privileged chroot finalization with host `/dev`, `/proc`, `/sys`, and `/run` bindings. That is necessary to install boot packages and configure the installed system, but it means a malicious source can execute with root-level impact during installation.

Do not run this installer against ISOs from unknown mirrors, modified installer trees, or mounted sources you did not create or review. Prefer official Ubuntu release images and verify their checksums and signatures before use.

## Diagnostic Reports

The default `ubuntu-external-report` output redacts network addresses and raw hardware identifiers where practical, and avoids full journals by default. Review reports before sharing them publicly.

Only include these options when requested and after review:

```bash
sudo ubuntu-external-report --include-network-details --output report.txt
sudo ubuntu-external-report --include-hardware-ids --output report.txt
sudo ubuntu-external-report --include-full-journal --output report.txt
```

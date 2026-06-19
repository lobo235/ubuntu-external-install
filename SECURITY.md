# Security Policy

## Reporting A Vulnerability

Please report security issues through GitHub Private Vulnerability Reporting for this repository. Private reporting should be enabled before the first public release.

If private reporting is unexpectedly unavailable, open a public issue with only a minimal description, no exploit details, and a request for a private contact path.

Do not paste secrets, SSH keys, full shell history, unreviewed diagnostic reports, or private network details into public issues.

## Data Loss Risk

`install-ubuntu-external.sh` is intentionally destructive. It repartitions and formats the selected target disk.

The installer includes safeguards such as whole-disk checks, USB/removable target checks, mounted-filesystem checks, optional serial/model assertions, a dry-run mode, and an exact destructive confirmation prompt. These checks reduce risk, but they do not replace careful operator review.

Before running a real install:

- Prefer a stable `/dev/disk/by-id/...` target path.
- Run `--dry-run` first.
- Use `--expect-serial` when the target exposes a serial number.
- Read the printed target disk, model, serial, size, and partition plan.
- Keep backups of anything important.

## Diagnostic Reports

The default `ubuntu-external-report` output redacts network addresses and raw hardware identifiers where practical, and avoids full journals by default. Review reports before sharing them publicly.

Only include these options when requested and after review:

```bash
sudo ubuntu-external-report --include-network-details --output report.txt
sudo ubuntu-external-report --include-hardware-ids --output report.txt
sudo ubuntu-external-report --include-full-journal --output report.txt
```

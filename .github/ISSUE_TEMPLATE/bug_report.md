---
name: Bug report
about: Report an install or boot problem
title: ""
labels: bug
assignees: ""
---

## Summary

What failed?

## Environment

- Installer version:
- Ubuntu ISO filename/version:
- Host environment: WSL2 or native Linux:
- Host distro/version:
- Target type: USB stick, Sabrent enclosure, other external drive:
- Target model/size:
- Secure Boot enabled: yes/no/unknown:

## Command

Paste the command used. Redact personal paths and usernames if needed.

```bash

```

## Failure Phase

Choose one:

- dry-run
- partition/format
- extract
- finalize/chroot
- first boot
- login
- networking
- other

## Expected Behavior

What did you expect to happen?

## Actual Behavior

What happened instead?

## Diagnostic Report

If the installed system boots far enough, run:

```bash
sudo ubuntu-external-report --output ubuntu-external-report.txt
```

Review the report before attaching or pasting it. Do not include private paths, IP addresses, DNS domains, hardware serials, Wi-Fi SSIDs, SSH keys, or full journals unless you have checked them.

Attach or paste the report here:

```text

```

## Additional Notes

Any firmware, laptop, enclosure, or USB-stick details that seem relevant.

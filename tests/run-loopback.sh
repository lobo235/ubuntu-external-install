#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
Loopback destructive rehearsal is not implemented yet.

Planned behavior:
  - require root, losetup, truncate, and a real or generated squashfs source
  - create a sparse disk image
  - attach it with losetup
  - run install-ubuntu-external.sh with --allow-loop-target --yes
  - verify partition labels, fstab, metadata, and cleanup

For now, use tests/run.sh for non-destructive checks and
tests/manual-boot-checklist.md for real USB-stick validation.
EOF

exit 1

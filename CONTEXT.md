# Project Context

## Integration Surface & Consumers

Primary consumer: people running `install-ubuntu-external.sh` directly, or through a local coding agent using `AGENT_INSTALL_PROMPT.md`.

Public surfaces:

- CLI: `install-ubuntu-external.sh` options, prompts, exit behavior, and `--help` output.
- Installed target files: UEFI fallback boot files, GRUB configuration, `/etc/fstab`, installed user account, and `/usr/local/sbin/ubuntu-external-report`.
- Documentation: `README.md`, `AGENT_INSTALL_PROMPT.md`, `SECURITY.md`, and GitHub issue guidance.
- Tests and CI: `make check`, `tests/run.sh`, and `.github/workflows/synthetic-tests.yml`.

Compatibility expectations:

- Preserve safe defaults for destructive disk operations.
- Prefer additive CLI changes; do not remove or repurpose options without a major version.
- Keep agent-facing instructions aligned with `SECURITY.md`.
- Keep diagnostic reports privacy-conscious by default.
- Keep CI non-destructive; full device boot testing remains manual.

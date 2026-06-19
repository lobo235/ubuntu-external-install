# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v0.2.0] - 2026-06-19

### Added

- Add `--copy-progress periodic|detailed|never` to make the long filesystem copy step visibly active without flooding agent or automation logs by default.
- Document copy-progress behavior and update the agent install prompt so user-run final install commands use detailed progress while agent-run commands keep readable periodic output.

## [0.1.5] - 2026-06-18

### Documentation

- Clarify that Ubuntu's official USB installation media docs are the right tool for live installer USBs.
- Explain the project motivation: creating a full installed Ubuntu Desktop system on a fast external USB/NVMe drive for a portable development environment.

## [0.1.4] - 2026-06-18

### Fixed

- Force GRUB's timeout style to show the menu for the expected 10 second boot window instead of appearing as a blank delay on some systems.

## [0.1.3] - 2026-06-18

### Documentation

- Clarify that agents which cannot handle interactive terminal prompts must provide exact commands for the user to run manually.
- Document expected handoff for sudo authentication, destructive confirmation, and new-user password prompts.

## [0.1.2] - 2026-06-18

### Documentation

- Clarify that passwordless sudo is not required for agent-guided installs.
- Instruct agents to avoid asking users to reveal sudo passwords in chat and to fall back to user-run commands when interactive prompts are unsupported.

## [0.1.1] - 2026-06-18

### Fixed

- Fix the README GitHub Actions badge so it reports the `Synthetic tests` workflow status.

## [0.1.0] - 2026-06-18

### Added

- Initial public Ubuntu Desktop external-drive installer.
- UEFI removable bootloader setup for portable Secure Boot-compatible external installs.
- Target safety checks, dry-run planning, exact destructive confirmation, and serial/model guards.
- WSL2 guidance, post-boot diagnostics, synthetic tests, GitHub CI, and public issue-reporting guidance.

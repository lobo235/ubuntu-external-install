# Agent-Assisted Ubuntu External Drive Install Prompt

Use this prompt with Claude Code, Codex, OpenCode, or another local coding agent when you want a guided install of Ubuntu 26.04 Desktop amd64 onto an external USB drive, USB SSD, or USB NVMe enclosure.

```text
You are helping me install Ubuntu 26.04 Desktop amd64 onto an external drive using this repository:

https://github.com/lobo235/ubuntu-external-install

Act like a careful installer operator. Walk me through the install one decision at a time, and provide your recommended answer for every question. Do not run destructive commands until you have positively identified the target disk, shown me the dry-run plan, and received explicit confirmation.

Primary objective:
- Download or clone the repository above.
- Read README.md, SECURITY.md, AGENT_INSTALL_PROMPT.md, and ./install-ubuntu-external.sh --help.
- Help me install Ubuntu 26.04 Desktop amd64 to an external target using install-ubuntu-external.sh.
- Prefer the safest portable UEFI/Secure Boot-compatible install path.
- Assume the target drive will be erased.

Operating rules:
- Ask one question at a time.
- If a question can be answered from the machine, inspect the machine instead of asking.
- Prefer stable /dev/disk/by-id/... target paths over /dev/sdX.
- If multiple removable/USB disks exist, list them with size, model, serial, transport, filesystem labels, UUIDs, and mountpoints, then ask me to choose.
- Never select an internal OS disk. If there is any ambiguity, stop and ask.
- Always use --dry-run first.
- Use --expect-serial and, when useful, --expect-model for the real install.
- Do not use --yes by default. Prefer the script's exact destructive confirmation prompt. Only use --yes if I explicitly ask for a non-interactive destructive run after seeing the dry-run plan.
- Keep Secure Boot support unless I explicitly ask otherwise.
- Do not recommend --write-nvram for portable external drives unless I specifically want a firmware boot entry on this machine.
- Use --prompt-password for normal interactive installs. Use --password-hash only if there is a clear automation reason.
- Do not allow --no-user or --allow-locked-user for a normal desktop install.
- Do not use --allow-non-usb unless I explicitly identify a non-USB target and accept the added risk.
- Treat --post-install-script as advanced and risky; only use a script that I wrote, reviewed, and explicitly selected.
- Keep backups of anything important before destructive work.
- Review diagnostic reports before sharing them. Do not publish raw hardware identifiers, DNS domains, IP addresses, SSH keys, shell history, full journals, or unreviewed private configuration.
- Do not assume passwordless sudo. Never ask me to type, paste, or reveal my sudo password in chat.
- If your environment supports interactive sudo prompts, run sudo commands normally and let the terminal/UI prompt me directly.
- If your environment cannot handle interactive sudo, print the exact sudo command I should run in my own terminal, wait for me to paste back the output or confirm completion, and then continue.
- If sudo authentication times out mid-install, pause and ask me to rerun the exact command or re-authenticate in the terminal. Do not work around sudo by weakening system security.
- Determine whether your harness can support interactive terminal input before running commands that require it.
- Interactive commands include sudo authentication, the installer's exact destructive confirmation (`ERASE <target-disk>`), and `--prompt-password` password entry for the new Ubuntu user.
- If your harness cannot support interactive terminal input, do not start those commands yourself. Instead, print the exact command for me to run in my own terminal, explain what prompts I should expect, and ask me to report back whether it succeeded and paste any error output.
- For the real install command, choose copy progress based on who will run it. If I will run the final command in my own terminal, include `--copy-progress detailed` so I can see rsync's live progress during the long filesystem copy. If you will run the final command in your own agent terminal, include `--copy-progress periodic` or `--copy-progress never` to keep the transcript readable; prefer `periodic` unless I explicitly ask for quiet output.

Start by determining:
1. Am I on native Linux or WSL2?
2. Is the Ubuntu 26.04 Desktop amd64 ISO already present? If so, where?
3. What external target drive should be erased?
4. What username should be created?
5. Should the user set the password interactively with --prompt-password? Recommend yes.

If I am on native Linux:
- Run:
  lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN,RM,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
- Identify likely removable/USB whole disks.
- Ask me to choose the target if more than one plausible target exists.

If I am on WSL2:
- Explain that WSL2 must see the external device as a Linux block device before the installer can run.
- In an elevated PowerShell session, guide me through identifying the Windows disk:
  Get-Disk | Format-Table Number,FriendlyName,SerialNumber,Size,BusType,PartitionStyle,OperationalStatus
- For a whole external storage disk, recommend attaching the physical disk to WSL with:
  wsl --mount --bare \\.\PHYSICALDRIVE<N>
- Then in WSL, run:
  lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN,RM,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
- If wsl --mount is not suitable and USB passthrough is needed, explain the usbipd-win route:
  usbipd list
  usbipd bind --busid <BUSID>
  usbipd attach --wsl --busid <BUSID>
  Then verify in WSL with lsblk.
- Warn me not to choose the Windows system disk.
- At the end, remind me to detach with:
  wsl --unmount \\.\PHYSICALDRIVE<N>
  or:
  usbipd detach --busid <BUSID>
  depending on how it was attached.

Check dependencies before install:
- Run ./install-ubuntu-external.sh --help.
- Let the script report missing dependencies when possible.
- On Ubuntu/Debian hosts, the usual package set is:
  sudo apt install gdisk dosfstools e2fsprogs rsync util-linux udev coreutils findutils
- If tests are requested, shellcheck is optional.
- If installing dependencies needs sudo and sudo is not passwordless, either let the terminal prompt me directly or give me the exact apt command to run myself.

Once the basic required information is known, tell me:
"I have enough information to run a safe dry-run. Before I do, do you want to consider advanced options?"

If I say yes, present these advanced options and ask which, if any, I want:
- --hostname NAME: change the installed hostname.
- --profile desktop|minimal: choose desktop or minimal layered ISO profile when supported.
- --apt-mirror URL and --security-mirror URL: use local or regional mirrors.
- --esp-label LABEL and --root-label LABEL: customize filesystem labels.
- --esp-size SIZE: change EFI partition size.
- --rootdelay SECONDS: change USB root device wait time.
- --source DIR: use an already mounted Ubuntu installer filesystem instead of an ISO.
- --unmount-target: allow the script to unmount mounted target child filesystems.
- --offline: avoid apt installation and require boot packages to already exist.
- --keep-cloud-init: leave cloud-init enabled.
- --post-install-script PATH: run a custom chroot script near the end; explain that this is powerful and should only be used with reviewed local scripts.
- --write-nvram: write a firmware boot entry; explain that this is not recommended for portable external drives.
- --allow-non-usb: permit non-USB/non-removable targets; explain that this bypasses an important data-loss safeguard and should usually be avoided.

Dry-run flow:
- Build the dry-run command using the selected ISO/source, target by-id path, --user, --prompt-password, --expect-serial, and any selected advanced options.
- Run the dry-run if you can handle interactive sudo; otherwise show me the exact dry-run command and ask me to run it.
- Show me the install plan and explicitly identify the target disk that will be erased, including model, serial, size, transport, and current mountpoints if available.
- Ask for confirmation before the real install.

Real install flow:
- Run the same command without --dry-run only if you can handle all required interactive input, including sudo, the `ERASE <target-disk>` confirmation, and `--prompt-password`. When you run it in your agent terminal, add `--copy-progress periodic` unless I explicitly request `--copy-progress never`.
- If you cannot handle interactive input, show me the exact real install command and ask me to run it in my terminal. Add `--copy-progress detailed` to that user-run command. Tell me to expect the `ERASE <target-disk>` confirmation, the new-user password prompt, and live copy progress during the longest step, then report back whether it completed or paste any error output.
- Let the script's exact destructive confirmation protect the target unless I explicitly asked for --yes after reviewing the dry-run.
- Watch for errors.
- After install, verify from the host:
  lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN,FSTYPE,LABEL,UUID,MOUNTPOINTS
  fsck.vfat -n on the ESP partition
  e2fsck -fn on the root partition
- Mount the target read-only or carefully for inspection if needed, and confirm:
  /EFI/BOOT/BOOTX64.EFI exists
  /EFI/BOOT/grub.cfg exists
  /EFI/ubuntu/grub.cfg exists
  /EFI/ubuntu-external/grub.cfg exists
  /boot/grub/grub.cfg exists on the ESP
  /boot/grub/grub.cfg on the root has timeout lines set to 10 seconds
- Sync and unmount before telling me to unplug the drive.

First boot flow:
- Tell me to boot the target machine from the external drive with UEFI mode and Secure Boot enabled if desired.
- Expected behavior: GRUB menu appears with about a 10 second timeout, then Ubuntu boots to the desktop login.
- I should only need to type the user's password, not GRUB commands.
- If it drops to grub>, ask me for:
  ls
  set
  and whether configfile (hd0,gpt1)/EFI/BOOT/grub.cfg or configfile (hd0,gpt1)/boot/grub/grub.cfg works.

Post-boot report:
- Ask me to run:
  sudo ubuntu-external-report --output ubuntu-external-report.txt
- Ask me to review the file before sharing. The default report redacts network addresses and raw hardware identifiers where practical, but I still need to review it.
- Only request these options when they are needed and I agree after review:
  sudo ubuntu-external-report --include-network-details --output report.txt
  sudo ubuntu-external-report --include-hardware-ids --output report.txt
  sudo ubuntu-external-report --include-full-journal --output report.txt
- If we are in the same local network and I ask for convenience upload, you may run a temporary local HTTP receiver outside the installer. Do not add remote upload behavior to the installer itself.

Issue-reporting guidance:
- If something fails, collect the Ubuntu ISO filename/version, host environment, target model/serial if safe to share, exact command with private paths redacted, failure phase, Secure Boot state, and ubuntu-external-report output if available.
- Do not ask me to share SSH keys, shell history, full journals, Wi-Fi secrets, raw hardware serials, DNS domains, IP addresses, or unreviewed private configuration.
```

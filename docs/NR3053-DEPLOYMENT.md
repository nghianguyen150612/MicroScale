# NR3053 controlled deployment — NOT YET QUALIFIED

The router is OpenWrt 21.02-SNAPSHOT with a 116.6 MiB UBIFS overlay. Reported host SSH address: root@192.168.3.1. Actual `uname -m`, running Tailscale version, service name and local-LAN access still need live verification.

## Prerequisites

- Be physically on the router's LAN with Arch Linux and `root@192.168.3.1` SSH working *without* Tailscale.
- Confirm an alternate admin session and local recovery; keep original firmware, SSH configuration and NAND layout untouched.
- Have a tested binary and sufficient RAM/overlay.
- Never run this installer remotely through a Tailnet or from CI.

## Commands (on Arch)

```bash
bash scripts/deploy-openwrt.sh preflight root@192.168.3.1

# Only after checking the preflight and local rollback:
CONFIRM_LOCAL_LAN=YES bash scripts/deploy-openwrt.sh apply \
    root@192.168.3.1 dist/safe/linux-arm64/microscale safe

# If needed, use the backup directory printed by apply:
CONFIRM_LOCAL_LAN=YES bash scripts/deploy-openwrt.sh restore \
    root@192.168.3.1 "$HOME/.local/share/microscale/backups/<timestamp>"
```

The installer saves original CLI and daemon binary copies **on Arch**, stages backups in router RAM, checks upload SHA256 and ARM64 ELF format, installs the combined executable at `/usr/sbin/tailscaled`, replaces `/usr/bin/tailscale` with a symlink, restarts the existing init service and requires the backend to reach Running. It attempts an in-session rollback on health failure. This does **not** guarantee recovery from a power loss or lost SSH session; the host backup must be retained.

## Stop conditions

- Router reachable only through Tailscale (no LAN SSH).
- No known `/etc/init.d/tailscale` entrypoint or CPU/ABI mismatch.
- Tailscale not healthy before deploy.
- Inadequate NAND free space or missing backup.
- Candidate lacks login, `tailscale up`, Exit Node or Subnet Router functionality.
- Any remote health or upload checksum failure.

After basic health success, use a second tailnet device to test exit-node egress IP, subnet route, DNS/MagicDNS, Tailscale SSH, reconnect, and persistence after router reboot. No CI smoke test substitutes for this qualification. Small and Extreme are rejected by default unless explicitly enabled, and doing so does not certify them as stable.

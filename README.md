# Immutable Ubuntu via BTRFS Snapshots

## Overview

This system makes an Ubuntu installation effectively immutable. Every boot starts fresh from a read-only btrfs snapshot, and runtime state is discarded on the next reboot. Persistent changes are only made through a controlled staging pipeline that runs system updates and an Ansible playbook.

Ships as a `.deb` package (`immutable-ubuntu`) that can be installed during autoinstall via the `packages:` section or from a PPA.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  BTRFS top-level (subvolid=5)                                       │
│                                                                     │
│  @/                    ← original root subvolume (reference only)   │
│  @snapshots/                                                        │
│    root.20250314T120000  ← read-only snapshot (GRUB boots this)     │
│    root.20250314T160000  ← newer read-only snapshot after update    │
│  @rootfs               ← writable clone created by dracut at boot   │
│  @staging              ← transient writable clone for updates       │
│                                                                     │
│  @home, @log, @apt-cache, @tmp, @spool, @crash, @containers,        │
│  @flatpak, @snap, @libvirt, @AccountsService, @gdm3, @bluetooth,    │
│  @cups, @fwupd, @netmanager, @machine-id                            │
│    ← persistent subvolumes, survive reboots and rollbacks           │
└─────────────────────────────────────────────────────────────────────┘
```

### Boot flow

1. **GRUB** (`06_immutable`) selects the latest read-only snapshot and passes `rootflags=subvol=@snapshots/<timestamp>` plus `rd.immutable` on the kernel cmdline.
2. **dracut** (the `90immutable-ubuntu` module) uses a systemd generator to:
   - Create a setup service that runs before `sysroot.mount`.
   - Mount the btrfs top-level, delete the previous `@rootfs`, and create a new writable snapshot from the selected read-only snapshot.
   - Drop in an override for `sysroot.mount` so systemd mounts `@rootfs` as the real root.
3. **systemd** boots normally from the ephemeral writable root.

### Update flow

Runs manually or every 4 hours via the systemd timer:

1. Find the latest read-only snapshot.
2. Create a writable `@staging` clone.
3. Enter `@staging` with `systemd-nspawn`, bind-mounting `/boot` and `/boot/efi` so kernel and GRUB updates land on the real boot partition.
4. Inside the container: `apt full-upgrade`, then clone and run `./install.sh` from each repo listed in the config.
5. **On success:** snapshot `@staging` as a new read-only snapshot, delete `@staging`, prune old snapshots, and `update-grub`.
6. **On failure:** retain `@staging` for investigation, log the error.
7. The user reboots at their convenience to activate the new snapshot.

## Project layout

```
debian/                                                ← deb package scaffolding
  control, rules, postinst, prerm, changelog, ...

data/                                                    ← package install tree (maps to /)
  etc/
    immutable-update.conf                              ← update script configuration
    default/grub.d/
      immutable.cfg                                    ← GRUB defaults (timeout, cmdline)
    dracut.conf.d/
      immutable-ubuntu.conf                              ← enables dracut module
    grub.d/
      06_immutable                                     ← GRUB hook for snapshot boot entries
    systemd/system/
      immutable-update.service                         ← oneshot update service
      immutable-update.timer                           ← 4-hour periodic trigger
      machine-id-persist.service                       ← restores machine-id after rollback
  usr/
    lib/dracut/modules.d/90immutable-ubuntu/
      module-setup.sh                                  ← dracut module metadata
      immutable-ubuntu-generator                         ← systemd generator for boot-time setup
      immutable-ubuntu-setup.sh                          ← creates writable @rootfs from snapshot
    local/sbin/
      immutable-update                                 ← update/staging script (nspawn)
      immutable-ubuntu-setup                           ← autoinstall bootstrap script
```

## Building the package

```bash
# Install build dependencies
sudo apt install debhelper devscripts

# Build the .deb
dpkg-buildpackage -us -uc -b

# Result: ../immutable-ubuntu_0.1.0_all.deb
```

## Autoinstall

The user-data files are minimal — the `immutable-ubuntu` package is listed in `packages:` and a single late-command calls the bootstrap script:

```yaml
autoinstall:
  packages:
    - immutable-ubuntu
    - ubuntu-desktop-minimal
    # ...
  late-commands:
    - /target/usr/sbin/immutable-ubuntu-setup --bootstrap --repos "https://github.com/example/my-config.git"
```

The bootstrap script handles all 11 phases: btrfs subvolume restructuring, fstab/crypttab generation, data migration, first-boot tweaks, baseline snapshot, dracut regeneration, and GRUB configuration.

## Configuration

Edit `/etc/immutable-update.conf` after install:

| Variable | Purpose |
|---|---|
| `REPOS` | Bash array of git URLs; each repo is cloned and `./install.sh` is run after apt upgrades |
| `MAX_SNAPSHOTS` | Number of read-only snapshots to retain (oldest pruned first) |
| `BOOT_PARTITION` / `EFI_PARTITION` | Paths to bind-mount into the nspawn container |

## Usage

```bash
# Run an update manually
sudo immutable-update

# Interactive shell in staging (exit 0 to snapshot, non-zero to abort)
sudo immutable-update --shell

# Interactive shell with GUI passthrough (Wayland/X11, GPU, audio)
sudo immutable-update --gui

# Check timer status
systemctl status immutable-update.timer

# View logs
ls /var/log/immutable-update/
journalctl -u immutable-update.service
```

## Important notes

- **Persistent data** (home directories, logs, etc.) lives on separate btrfs subvolumes mounted independently via `/etc/fstab`. The update script and dracut module only touch `@rootfs`, `@staging`, and the snapshot directory.
- **Post-update scripts must be idempotent.** Each repo's `install.sh` runs on every update cycle against the latest snapshot, not against a running system.
- **`rd.immutable` kernel parameter** is the gate. Remove it from the GRUB config to disable immutable behavior and boot normally.
- **On upgrades** (`apt upgrade immutable-ubuntu`), the deb's postinst regenerates dracut and updates GRUB automatically.
- **Dracut replaces initramfs-tools.** The package declares `Conflicts: initramfs-tools` so dpkg handles the swap.

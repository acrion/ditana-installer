# Ditana Installer

The installer and ISO generator for [Ditana GNU/Linux](https://ditana.org) — a security-conscious, hardware-aware Arch derivative with four equally-supported desktop environments (XFCE, Wayfire, Niri, COSMIC).

This repository contains the **interpreter**. The data it interprets — every setting, every package, every script — lives in [ditana-config](https://github.com/acrion/ditana-config), which the installer downloads at runtime. If you're looking to contribute a new option, a hardware quirk fix, or a compositor tweak, that's almost certainly the repository you want.

## What this repository contains

- Raku source for the installer (`airootfs/root/`) — dialog logic, hardware detection, partitioning, mounting, pacstrap, chroot orchestration.
- An `archiso`-based ISO build configuration (`profiledef.sh`, `packages.x86_64`, `pacman.conf`, `efiboot/`, `grub/`, `syslinux/`).
- The `build.sh` ISO generator.
- A bundled snapshot of `ditana-config` (`airootfs/root/ditana-config.tar.gz`) used as a fallback when the runtime download fails.
- Sparrow6 tests under `tests/` covering automated configuration changes.
- `CONTRIBUTING.md` — the contributor guide, including how to run the installer in simulation mode without touching your system.

## How the pieces fit together

```
┌─────────────────────────┐    runtime download      ┌──────────────────┐
│  ditana-installer (ISO) │  ──────────────────────▶ │   ditana-config  │
│  - Raku dialog logic    │   (bundled fallback)     │   (KDL knowledge │
│  - archiso, GRUB, ...   │                          │    base)         │
└─────────────────────────┘                          └──────────────────┘
            │
            │ uses
            ▼
┌──────────────────────────┐
│  Sparrow6 (tests + tasks)│
│  by @melezhik            │
└──────────────────────────┘
```

When the installer boots, it downloads the current `ditana-config` archive from GitHub Releases, falls back to the bundled snapshot if offline, parses the KDL into runtime state, and drives the user through dialogs declared in `installation-steps.kdl`. The same configuration drives package selection, lifecycle scripts (chroot, early-chroot, root, login, autostart), file deployment, and MIME defaults.

This means: **improvements to defaults ship to users on their next install**, without re-spinning an ISO.

## Building the ISO

### Prerequisites

- An Arch-based system (Ditana itself is the smoothest, but any Arch derivative works).
- `archiso`, `git`, and a working `paru` or `yay`.

### Build

```bash
git clone https://github.com/acrion/ditana-installer.git
cd ditana-installer
./build.sh
```

The build script signs the output ISO with the GPG key configured for `s.zipproth@ditana.org` by default. To build with your own key, edit `build.sh` or override via environment. The output appears in `out/` as:

```
out/Ditana-<version>-x86_64.iso
out/Ditana-<version>-x86_64.iso.sha256
out/Ditana-<version>-x86_64.iso.sig
```

**Note:** If your current Git branch is not `main`, the build automatically switches to the Ditana Testing Arch repository — useful for testing Ditana package changes before promoting them.

## Testing the installer

You can run the installer in **simulation mode** on your live system without any risk of overwriting it:

```bash
cd airootfs/root
./run-ditana-installer.sh
```

This opens a `tmux` session with the installer dialogs on one pane and the live log on the other. Simulation mode is detected via `$USER ne 'root'`; you may still be asked for your sudo password to retrieve hardware information (`lspci`, `dmidecode`, etc.), but no partitioning, mounting, or `pacstrap` happens. The log is written to `/tmp/install_ditana.log`.

For a less distracting variant without `tmux`:

```bash
cd airootfs/root
./main.sh
```

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for details. The short version:

- **Bug reports and feature requests** → [issues](https://github.com/acrion/ditana-installer/issues).
- **Changes to settings, packages, or scripts** → almost always belong in [`ditana-config`](https://github.com/acrion/ditana-config), not here.
- **Changes to the installer engine itself** → here, but please open an issue first to discuss the approach.

## Acknowledgements

- **Alexey Melezhik** for [Sparrow6](https://github.com/melezhik/Sparrow6) and the migration from Ansible to Sparrow tasks.
- **Thomas Zipproth** for ongoing testing.
- The Arch maintainers for everything below the installer.

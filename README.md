# Ditana GNU/Linux

Ditana GNU/Linux is an Arch-based distribution that bridges the gap between user-friendly systems and highly customizable environments. It aims to empower Linux enthusiasts with unprecedented control over their computing experience while maintaining a strong focus on security and performance.

## About Ditana

The name "Ditana" draws inspiration from Ammi-Ditana, a king of ancient Babylon known for his long and peaceful reign. This historical connection reflects our philosophy in several ways:

1. **Stability and Longevity**: We aim to create a Linux distribution that provides long-term stability and support.
2. **Continuous Improvement**: We are committed to building upon the solid foundation of Arch Linux, continuously improving and optimizing the user experience.
3. **Cultural Heritage and Innovation**: Ditana GNU/Linux combines time-tested principles of Linux with modern innovations in security and customization.
4. **Detailed Documentation**: We emphasize comprehensive documentation and transparency in system operations.

## Ditana ISO Builder

This repository contains the Ditana ISO Builder, a core component of the Ditana GNU/Linux project. The Ditana ISO Builder is responsible for creating the installation media for Ditana GNU/Linux, integrating various packages and configurations to produce a cohesive and functional system.

### Key Features of the Ditana ISO Builder:

- **Unified ISO**: One image for both desktop and headless installations.
- **Flexible Installer**: A series of dialogs guides you through the installation process, considering complex dependencies based on your hardware and preferences.
- **Extensive Customization**: From selecting kernel parameters to configuring the desktop environment.
- **XFCE Desktop Environment**: For desktop installations, with pre-installed enhancements.
- **Modular Structure**: Many aspects of Ditana have been separated into individual Arch packages.
- **Hardware Optimization**: Automatic detection and adaptation to your hardware.
- **Enhanced Security**: Pre-configured security features and kernel settings.
- **Performance Tuning**: Intelligent system optimizations for peak performance.

## Repository Structure

This repository (`ditana-installer`) contains the Ditana installer and is based on the `/usr/share/archiso/configs/releng/` directory of the Arch `archiso` package.

- The `archiso` branch maintains the original state of the `archiso` package for easy merging of updates.
- The `build.sh` script in the root directory builds the Ditana ISO.
- Key installer scripts:
  - `airootfs/root/main.raku`: Main entry point for the installer.
  - `airootfs/root/folders/root/chroot-install.sh`: Chroot installation script.
- [Sparrow6](https://github.com/melezhik/Sparrow6) is used for robust and reliable configuration:
  - https://github.com/acrion/ditana-installer/airootfs/root/bind-mount/root/sparrow/tasks/pacman
  - `airootfs/root/bind-mount/root/configure-grub.yaml`
  - `airootfs/root/bind-mount/root/configure-mkinitcpio.yaml`
  - `airootfs/root/ansible/configure_locale.yaml`

## Ditana Package Management

Ditana follows a modular approach, with many components packaged as separate Arch packages. These packages are available through the official Ditana repository. For a detailed description of each package, please navigate to its GitHub repository.

### Ditana Packages

#### Core Ditana Components

- [ditana-filesystem](https://github.com/acrion/ditana-filesystem)
- [ditana-network](https://github.com/acrion/ditana-network)
- [ditana-assistant](https://github.com/acrion/ditana-assistant)
- [ditana-ramdisk](https://github.com/acrion/ditana-ramdisk)
- [ditana-config-shell](https://github.com/acrion/ditana-config-shell)
- [ditana-print-system-infos](https://github.com/acrion/ditana-print-system-infos)
- [ditana-update-from-skel](https://github.com/acrion/ditana-update-from-skel)
- [ditana-mirrorlist](https://github.com/acrion/ditana-mirrorlist)
- [ditana-testing-mirrorlist](https://github.com/acrion/ditana-testing-mirrorlist)

#### Ditana Desktop Enhancements

- [ditana-config-xfce](https://github.com/acrion/ditana-config-xfce)
- [xfce-display-config-observer](https://github.com/acrion/xfce-display-config-observer)
- [xfce-wallpaper-overlay](https://github.com/acrion/xfce-wallpaper-overlay)
- [ditana-print-system-load](https://github.com/acrion/ditana-print-system-load)

#### Configuration packages

- [ditana-koboldcpp](https://github.com/acrion/ditana-koboldcpp)
- [ditana-config-bash](https://github.com/acrion/ditana-config-bash)
- [ditana-config-zsh](https://github.com/acrion/ditana-config-zsh)
- [ditana-config-coredumps](https://github.com/acrion/ditana-config-coredumps)
- [ditana-config-kitty](https://github.com/acrion/ditana-config-kitty)
- [ditana-config-logseq](https://github.com/acrion/ditana-config-logseq)
- [ditana-config-micro](https://github.com/acrion/ditana-config-micro)
- [ditana-config-vscode](https://github.com/acrion/ditana-config-vscode)

#### Packaged External Sources

- [kora-yellow-icon-theme](https://github.com/acrion/kora-yellow-icon-theme)

#### Repackaged AUR Contributions

Unlike the packages in previous categories, the following do not have Ditana-specific GitHub repositories. These packages are built directly from the Arch User Repository (AUR) and are provided in the Ditana package repository for seamless installation via pacman:

- [kalu](https://github.com/Thulinma/kalu)
- [python-proxy_tools](https://github.com/jtushman/proxy_tools)
- [python-pywebview](https://github.com/r0x0r/pywebview)
- [stress-ng](https://github.com/ColinIanKing/stress-ng)

### Ditana Repository

Main server: https://ditana.org/ditana

The Ditana repository is powered by Cloudflare, which provides caching and content delivery network (CDN) services. This setup offers several advantages:

- Improved global accessibility and reduced latency
- Enhanced reliability and uptime
- Protection against DDoS attacks
- Automatic SSL/TLS encryption

### Using Ditana Packages Outside of Ditana

To use Ditana packages in a non-Ditana Arch-based system, follow these steps:

1. Add the following to the end of your `/etc/pacman.conf`:

   ```
   [ditana]
   Include = /etc/pacman.d/ditana-mirrorlist
   ```

2. Create a file named `/etc/pacman.d/ditana-mirrorlist` with the following content:

   ```
   Server = https://ditana.org/$repo/$arch
   ```

3. Update your package database:

   ```
   sudo pacman -Sy
   ```

You can now install Ditana packages using `pacman`.

## Contributing

We welcome contributions to Ditana GNU/Linux! If you'd like to contribute, please:

1. Fork the repository
2. Create a new branch for your feature
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

This repository, i.e. the Ditana installer itself, is licensed under FOSS GPL-3.0-or-later without dual licensing.
This license does not apply to the installed system and software packages.

In the installation dialogs, we categorize software as either `FOSS` (Free and Open
Source Software) or `CLOSED` (non-open source software). After this category, the specific
license identifier for each package is provided, see https://spdx.org/licenses for details.

Please note that some software, including FOSS, may be dual-licensed, but commercial use or
distribution is still permitted under the FOSS license as long as its terms are met. If you
plan to use dual-licensed software in a commercial setting, reviewing its full license details
may offer additional flexibility and benefits.

## Contact

For support and discussions, join our [Discord server](https://discord.gg/RgcdumdE9J).

For more information, visit our website at [https://ditana.org](https://ditana.org).

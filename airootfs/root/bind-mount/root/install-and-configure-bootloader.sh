#!/usr/bin/env bash

# Copyright (c) 2024, 2025 acrion innovations GmbH
# Authors: Stefan Zipproth, s.zipproth@acrion.ch
#
# This file is part of Ditana Installer, see
# https://github.com/acrion/ditana-installer and https://ditana.org/installer.
#
# Ditana Installer is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ditana Installer is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ditana Installer. If not, see <https://www.gnu.org/licenses/>.

# This script is called from chroot-install.sh

echo -e "\033[32m--- Installing and configuring Bootloader ---\033[0m"

NVIDIA_BUT_NO_NOUVEAU="n"
if [[ "$INSTALL_NVIDIA_PROPRIETARY" == "y" ]] || [[ "$INSTALL_NVIDIA_OPENSOURCE" == "y" ]]; then
    NVIDIA_BUT_NO_NOUVEAU="y"
fi


rm -rf .mkinitcpio.changed

raku -MSparrow6::DSL -e "
  my \$s = task-run 'sparrow/tasks/mkinitcpio', %(
    path => '/etc/mkinitcpio.conf',
    use_init_systemd => '$USE_INIT_SYSTEMD',
    encrypt_root_partition => '$ENCRYPT_ROOT_PARTITION',
    zfs_filesystem => '$ZFS_FILESYSTEM',
    nvidia_but_no_nouveau => '$NVIDIA_BUT_NO_NOUVEAU',
  );

  if \$s<changed> {
    '.mkinitcpio.changed'.IO.spurt('');
  }
";

# Append a path to FILES=(...) in a mkinitcpio.conf file if not already present.
# The conf path defaults to /etc/mkinitcpio.conf (the system initramfs config),
# but can be overridden for ZBM's own config at /etc/zfsbootmenu/mkinitcpio.conf.
#
# Drop-in files in /etc/mkinitcpio.conf.d/ would be ignored because the kernel
# preset files set ALL_config="/etc/mkinitcpio.conf" (passes -c to mkinitcpio,
# disables drop-in processing - see mkinitcpio(8)).
add_to_mkinitcpio_files() {
    local path="$1"
    local conf="${2:-/etc/mkinitcpio.conf}"
    if ! grep -qF "$path" "$conf"; then
        sed -i \
            -e 's|^FILES=(\(.*\))|FILES=(\1 '"$path"')|' \
            -e 's|^FILES=( |FILES=(|' \
            "$conf"
        # Only the system mkinitcpio.conf needs a deferred -P rebuild at the
        # end of this script. ZBM's mkinitcpio.conf is rebuilt by an explicit
        # generate-zbm call right after we finish modifying it.
        if [[ "$conf" == "/etc/mkinitcpio.conf" ]]; then
            touch .mkinitcpio.changed
        fi
    fi
}

# Embed the custom console keymap into the initramfs so that
# systemd-vconsole-setup can find it during the early udev-triggered service
# invocation, before /etc on the real root is fully visible to that context.
if [[ -f /etc/vconsole-ditana.map ]]; then
    echo -e "\033[32m--- Embedding /etc/vconsole-ditana.map into initramfs ---\033[0m"
    add_to_mkinitcpio_files /etc/vconsole-ditana.map
fi

if [[ "$ZFS_FILESYSTEM" == "y" ]]; then
    # If the root partition is encrypted, embed the key file into the
    # system initramfs. This allows the system initramfs to unlock the pool
    # after ZFSBootMenu has prompted once for the passphrase, avoiding a
    # redundant second prompt. The key file /etc/zfs/ditana-root.key
    # resides on the encrypted dataset itself and is therefore inaccessible
    # without the passphrase.
    if [[ "$ENCRYPT_ROOT_PARTITION" == "y" ]]; then
        echo -e "\033[32m--- Embedding ZFS key file into system initramfs for single-prompt boot ---\033[0m"
        add_to_mkinitcpio_files /etc/zfs/ditana-root.key
    fi

    echo -e "\033[32m--- Installing Kernel modules for the Zettabyte File System (zfs-dkms) ---\033[0m"

    PACMAN_LOG_FILE=$(mktemp)
    pacman -S --noconfirm zfs-dkms 2>&1 | tee "$PACMAN_LOG_FILE" # generates initramfs
    PACMAN_EXIT=${PIPESTATUS[0]}

    if grep -q "module not found: 'zfs'" "$PACMAN_LOG_FILE"; then
        echo -e "\033[31m--- ERROR: ZFS modules compilation failed ---\033[0m"
        echo -e "\033[31m--- This is likely due to kernel version incompatibility with OpenZFS ---\033[0m"
        echo -e "\033[31m--- Check selected kernel version compatibility with current OpenZFS version on https://github.com/openzfs/zfs/releases ---\033[0m"
        echo -e "\033[31m--- Installation cannot continue with ZFS filesystem ---\033[0m"
        rm -f "$PACMAN_LOG_FILE"
        exit 1
    fi

    if [[ $PACMAN_EXIT -ne 0 ]]; then
        echo -e "\033[31m--- ERROR: pacman failed to install zfs-dkms ---\033[0m"
        rm -f "$PACMAN_LOG_FILE"
        exit 1
    fi

    rm -f "$PACMAN_LOG_FILE"
    echo -e "\033[32m--- ZFS modules successfully installed and compiled ---\033[0m"

    echo -e "\033[32m--- Installing zfsbootmenu ---\033[0m"
    runuser -u builduser -- paru -S zfsbootmenu --noconfirm

    echo -e "\033[32m--- Content of /etc/zfsbootmenu/mkinitcpio.conf ---\033[0m"
    cat /etc/zfsbootmenu/mkinitcpio.conf
    echo -e "\033[32m--- End of content of /etc/zfsbootmenu/mkinitcpio.conf ---\033[0m"

    # ZFSBootMenu builds its own initramfs via mkinitcpio using
    # /etc/zfsbootmenu/mkinitcpio.conf. We extend that config so the same
    # precise keymap that the running system uses is also active when ZBM
    # prompts for the encryption passphrase: add the keymap hook (which
    # reads KEYMAP from /etc/vconsole.conf at build time and embeds it),
    # and additionally embed the map file itself so systemd-vconsole-setup
    # variants inside the ZBM image can resolve the absolute path.
    if ! grep -E '^HOOKS=.*\bkeymap\b' /etc/zfsbootmenu/mkinitcpio.conf > /dev/null; then
        echo -e "\033[32m--- Adding keymap hook to ZBM HOOKS ---\033[0m"
        sed -i '/^HOOKS=/ s/\<keyboard\>/keyboard keymap/' /etc/zfsbootmenu/mkinitcpio.conf
    fi

    if [[ -f /etc/vconsole-ditana.map ]]; then
        echo -e "\033[32m--- Embedding /etc/vconsole-ditana.map into ZBM initramfs ---\033[0m"
        add_to_mkinitcpio_files /etc/vconsole-ditana.map /etc/zfsbootmenu/mkinitcpio.conf
    fi

    echo -e "\033[32m--- Content of /etc/zfsbootmenu/mkinitcpio.conf after modification ---\033[0m"
    cat /etc/zfsbootmenu/mkinitcpio.conf
    echo -e "\033[32m--- End of content of /etc/zfsbootmenu/mkinitcpio.conf after modification ---\033[0m"

    if [[ "$UEFI" == "y" ]]; then
        cat <<EOF >/etc/zfsbootmenu/config.yaml
Global:
  ManageImages: true
  BootMountPoint: /boot/efi
  DracutConfDir: /etc/zfsbootmenu/dracut.conf.d
  PreHooksDir: /etc/zfsbootmenu/generate-zbm.pre.d
  PostHooksDir: /etc/zfsbootmenu/generate-zbm.post.d
  InitCPIO: true
  InitCPIOConfig: /etc/zfsbootmenu/mkinitcpio.conf
Components:
  ImageDir: /boot/efi/EFI/zbm
  Versions: 3
  Enabled: false
  syslinux:
    Config: /boot/syslinux/syslinux.cfg
    Enabled: false
EFI:
  ImageDir: /boot/efi/EFI/zbm
  Versions: false
  Enabled: true
Kernel:
  CommandLine: ro $KERNEL_OPTIONS
EOF

        echo -e "\033[32m--- Generating ZFS Boot Menu Image ---\033[0m"
        generate-zbm

        echo -e "\033[32m--- Contents of /boot/efi/EFI/zbm ---\033[0m"
        ls -l /boot/efi/EFI/zbm
        UEFI_IMAGE=$(find /boot/efi/EFI/zbm -type f -printf '%f\n' | head -n 1)
        echo -e "\033[32m--- UEFI image file name: $UEFI_IMAGE ---\033[0m"

        echo -e "\033[32m--- Installing ZFSBootMenu on EFI System Partition disk ${BOOTLOADER_PARENT_DISK}, partition number ${BOOTLOADER_PARTITION_INDEX} ---\033[0m"

        efibootmgr --create \
                   --disk "/dev/${BOOTLOADER_PARENT_DISK}" \
                   --part "${BOOTLOADER_PARTITION_INDEX}" \
                   --label "Ditana Boot Menu" \
                   --loader "\\EFI\\zbm\\${UEFI_IMAGE}" \
                   --unicode

        # Set boot menu timeout separately. Some firmware implementations lock
        # the Timeout EFI variable at runtime (SetVariable returns EFI_WRITE_PROTECTED),
        # which the kernel reports as "Read-only file system". The system boots
        # fine with the firmware's default timeout in that case.
        efibootmgr --timeout 20 || echo -e "\033[33m--- Warning: Could not set EFI boot timeout (firmware may lock this variable) ---\033[0m"

        # Install as fallback boot path for firmware compatibility. Some UEFI
        # implementations remove custom boot entries on reboot. The fallback
        # path /EFI/BOOT/BOOTX64.EFI is always recognized by compliant firmware.
        mkdir -p /boot/efi/EFI/BOOT
        cp "/boot/efi/EFI/zbm/${UEFI_IMAGE}" /boot/efi/EFI/BOOT/BOOTX64.EFI
    else # BIOS systems
        mkdir -p "/boot/syslinux"
        cp /usr/lib/syslinux/bios/*.c32 "/boot/syslinux"

        echo -e "\033[32m--- Installing syslinux boot loader ---\033[0m"
        extlinux --install "/boot/syslinux"

        if blkid -p "/dev/$BOOTLOADER_PARENT_DISK" 2>/dev/null | grep -q 'PTTYPE="gpt"'; then
            dd if=/usr/lib/syslinux/bios/gptmbr.bin of="/dev/$BOOTLOADER_PARENT_DISK" conv=notrunc
        else
            dd if=/usr/lib/syslinux/bios/mbr.bin of="/dev/$BOOTLOADER_PARENT_DISK" conv=notrunc
        fi

        cat >/etc/zfsbootmenu/config.yaml << EOF
Global:
  ManageImages: true
  BootMountPoint: /boot/syslinux
  PreHooksDir: /etc/zfsbootmenu/generate-zbm.pre.d
  PostHooksDir: /etc/zfsbootmenu/generate-zbm.post.d
  InitCPIO: true
  InitCPIOConfig: /etc/zfsbootmenu/mkinitcpio.conf
Components:
  ImageDir: /boot/syslinux/zfsbootmenu
  Versions: false
  Enabled: true
Kernel:
  CommandLine: ro $KERNEL_OPTIONS
EOF

        echo -e "\033[32m--- Generating ZFS Boot Menu Image ---\033[0m"
        generate-zbm

        echo -e "\033[32m--- Contents of /boot/syslinux/zfsbootmenu ---\033[0m"
        ls -l /boot/syslinux/zfsbootmenu
        BIOS_IMAGE=$(find /boot/syslinux/zfsbootmenu -type f -name '*bootmenu' -printf '%f\n' | head -n 1)
        echo -e "\033[32m--- BIOS image file name: $BIOS_IMAGE ---\033[0m"

        cat > "/boot/syslinux/syslinux.cfg" << EOF
UI menu.c32
PROMPT 0

MENU TITLE Ditana Boot Menu
TIMEOUT 20

DEFAULT zfsbootmenu

LABEL zfsbootmenu
  MENU LABEL Ditana GNU/Linux
  KERNEL /zfsbootmenu/$BIOS_IMAGE
  INITRD /zfsbootmenu/initramfs-bootmenu.img
  APPEND zfsbootmenu quiet
EOF
    fi # configured ZFSBootMenu for UEFI or BIOS

    zfs set org.zfsbootmenu:commandline="rw $KERNEL_OPTIONS" ditana-root/ROOT
    zfs get org.zfsbootmenu:commandline ditana-root/ROOT

    # For encrypted pools, tell ZFSBootMenu where to find the key file
    # so it can cache it after a single passphrase prompt and pass it
    # through to the booted environment.
    if [[ "$ENCRYPT_ROOT_PARTITION" == "y" ]]; then
        echo -e "\033[32m--- Configuring ZFSBootMenu key source for single-prompt unlock ---\033[0m"
        zfs set org.zfsbootmenu:keysource="ditana-root/ROOT/default" ditana-root
    fi

    echo -e "\033[32m--- Enabling ZFS services ---\033[0m"
    systemctl enable zfs.target
    systemctl enable zfs-import.target
    systemctl enable zfs-import-cache
    systemctl enable zfs-mount

else # GRUB (used for all non-zfs file systems)
    echo -e "\033[32m--- Installing and configuring GRUB ---\033[0m"
    s6 --task-run sparrow/tasks/grub@"path=/etc/default/grub,kernel_options=$KERNEL_OPTIONS,encrypt_root_partition=$ENCRYPT_ROOT_PARTITION,enable_os_prober=$ENABLE_OS_PROBER"
    if [[ -d /sys/firmware/efi ]]; then
      echo -e "\033[32m--- Installing and configuring GRUB (UEFI) ---\033[0m"

      grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Ditana

      mkdir -p /boot/efi/EFI/BOOT
      grub-mkstandalone -O x86_64-efi -o /boot/efi/EFI/BOOT/BOOTX64.EFI "boot/grub/grub.cfg=/boot/grub/grub.cfg"

      # Ensure compatibility with non-standard UEFI implementations
      cp /boot/efi/EFI/BOOT/BOOTX64.EFI /boot/efi/shellx64.efi


      efibootmgr --create --disk "/dev/$INSTALL_DISK" --part 1 --label "Ditana GNU/Linux" --loader /EFI/Ditana/grubx64.efi
    else
        grub-install --target=i386-pc "/dev/$INSTALL_DISK"
    fi

    grub-mkconfig -o /boot/grub/grub.cfg

    if [[ -f .mkinitcpio.changed ]]; then
        mkinitcpio -P
    fi
fi

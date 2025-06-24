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

ansible-playbook -i localhost, configure-mkinitcpio.yaml -e "use_init_systemd=$USE_INIT_SYSTEMD encrypt_root_partition=$ENCRYPT_ROOT_PARTITION zfs_filesystem=$ZFS_FILESYSTEM nvidia_but_no_nouveau=$NVIDIA_BUT_NO_NOUVEAU"

if [[ "$ZFS_FILESYSTEM" == "y" ]]; then
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
    runuser -u builduser -- pikaur -S zfsbootmenu --noconfirm
        
    echo -e "\033[32m--- Content of /etc/zfsbootmenu/mkinitcpio.conf ---\033[0m"
    cat /etc/zfsbootmenu/mkinitcpio.conf
    echo -e "\033[32m--- End of content of /etc/zfsbootmenu/mkinitcpio.conf ---\033[0m"
    
    if ! grep -E '^HOOKS=.*\bkeymap\b' /etc/zfsbootmenu/mkinitcpio.conf > /dev/null; then
        echo -e "\033[32m--- Adding keymap hook to HOOKS ---\033[0m"
        sed -i '/^HOOKS=/ s/\<keyboard\>/keyboard keymap/' /etc/zfsbootmenu/mkinitcpio.conf
        
        echo -e "\033[32m--- Content of /etc/zfsbootmenu/mkinitcpio.conf after modification ---\033[0m"
        cat /etc/zfsbootmenu/mkinitcpio.conf
        echo -e "\033[32m--- End of content of /etc/zfsbootmenu/mkinitcpio.conf after modification ---\033[0m"
    fi
        
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
                   --timeout 20 \
                   --unicode
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
    
    echo -e "\033[32m--- Enabling ZFS services ---\033[0m"
    systemctl enable zfs.target
    systemctl enable zfs-import.target
    systemctl enable zfs-import-cache
    systemctl enable zfs-mount

else # GRUB (used for all non-zfs file systems)
    echo -e "\033[32m--- Installing and configuring GRUB ---\033[0m"
    s6 --task-run sparrow/tasks/grub@"path=/etc/default/grub,kernel_options=$KERNEL_OPTIONS,encrypt_root_partition=$ENCRYPT_ROOT_PARTITION,enable_os_prober=$ENABLE_OS_PROBER"
    if [[ -d /sys/firmware/efi ]]; then
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Ditana

        # Ensure compatibility with non-standard UEFI implementations
        mkdir -p /boot/efi/EFI/BOOT
        cp /boot/efi/EFI/Ditana/grubx64.efi /boot/efi/EFI/BOOT/BOOTx64.EFI
        cp /boot/efi/EFI/Ditana/grubx64.efi /boot/efi/shellx64.efi
        grub-mkstandalone -O x86_64-efi -o /boot/efi/EFI/BOOT/BOOTx64.EFI "boot/grub/grub.cfg=/boot/grub/grub.cfg"

        efibootmgr --create --disk "/dev/$INSTALL_DISK" --part 1 --label "Ditana GNU/Linux" --loader /EFI/Ditana/grubx64.efi
    else
        grub-install --target=i386-pc "/dev/$INSTALL_DISK"
    fi

    grub-mkconfig -o /boot/grub/grub.cfg

    if [[ "$ENCRYPT_ROOT_PARTITION" == "y" ]] || [[ "$USE_INIT_SYSTEMD" == "y" ]] || [[ "$NVIDIA_BUT_NO_NOUVEAU" == "y" ]]; then
        mkinitcpio -P
    fi
fi

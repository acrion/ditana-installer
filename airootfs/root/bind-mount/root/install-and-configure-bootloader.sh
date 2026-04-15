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

if [[ "$ZFS_FILESYSTEM" == "y" ]]; then
    # If the root partition is encrypted, embed the key file into the
    # system initramfs. This allows the initramfs to unlock the pool
    # automatically after ZFSBootMenu has already prompted once for
    # the passphrase, avoiding a redundant second prompt. The key file
    # /etc/zfs/ditana-root.key resides on the encrypted dataset itself
    # and is therefore inaccessible without the passphrase.
    if [[ "$ENCRYPT_ROOT_PARTITION" == "y" ]]; then
        echo -e "\033[32m--- Embedding ZFS key file into initramfs for single-prompt boot ---\033[0m"
        sed -i 's|^FILES=()|FILES=(/etc/zfs/ditana-root.key)|' /etc/mkinitcpio.conf
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

    # Use the prebuilt ZFSBootMenu release image instead of building locally
    # with generate-zbm. The prebuilt image ships its own Void Linux kernel
    # and is therefore independent of the installed kernel. This avoids
    # issues with hardened kernels that disable kexec (which generate-zbm
    # built images would inherit).
    #
    # Because prebuilt ZFSBootMenu boots the target kernel via kexec, EFI
    # Runtime Services are not carried over to the kexec'd kernel. The UEFI
    # specification does not define behavior for runtime services after
    # kexec, and firmware implementations do not preserve the necessary
    # memory mappings. We therefore pass efi=noruntime on the target kernel
    # command line (see the zfs set org.zfsbootmenu:commandline below).
    # Without this, kernels that call into EFI runtime services early
    # (e.g. linux-hardened via load_uefi_certs) will dereference invalid
    # pointers and panic. The practical impact is negligible: efibootmgr
    # and other EFI variable access would fail regardless after a kexec
    # boot, since the underlying firmware calls are non-functional.
    ZBM_BASE_URL="https://get.zfsbootmenu.org"

    # Read the console keymap from vconsole.conf (written earlier by the
    # installer) so we can pass it to ZFSBootMenu's own kernel command
    # line. This ensures the correct keyboard layout is active when
    # ZFSBootMenu prompts for an encryption passphrase.
    CONSOLE_KEYMAP=$(grep '^KEYMAP=' /etc/vconsole.conf | cut -d= -f2)
    ZBM_CMDLINE=""
    if [[ -n "$CONSOLE_KEYMAP" ]]; then
        ZBM_CMDLINE="rd.vconsole.keymap=$CONSOLE_KEYMAP"
    fi

    if [[ "$UEFI" == "y" ]]; then
        echo -e "\033[32m--- Downloading prebuilt ZFSBootMenu EFI image ---\033[0m"
        mkdir -p /boot/efi/EFI/zbm
        if ! curl -L -o /boot/efi/EFI/zbm/vmlinuz.EFI "$ZBM_BASE_URL/efi"; then
            echo -e "\033[31m--- ERROR: Failed to download ZFSBootMenu EFI image ---\033[0m"
            exit 1
        fi

        echo -e "\033[32m--- Contents of /boot/efi/EFI/zbm ---\033[0m"
        ls -l /boot/efi/EFI/zbm

        echo -e "\033[32m--- Installing ZFSBootMenu on EFI System Partition disk ${BOOTLOADER_PARENT_DISK}, partition number ${BOOTLOADER_PARTITION_INDEX} ---\033[0m"

        efibootmgr --create \
                   --disk "/dev/${BOOTLOADER_PARENT_DISK}" \
                   --part "${BOOTLOADER_PARTITION_INDEX}" \
                   --label "Ditana Boot Menu" \
                   --loader "\\EFI\\zbm\\vmlinuz.EFI" \
                   --unicode "$ZBM_CMDLINE"

        # Set boot menu timeout separately. Some firmware implementations lock
        # the Timeout EFI variable at runtime (SetVariable returns EFI_WRITE_PROTECTED),
        # which the kernel reports as "Read-only file system". The system boots
        # fine with the firmware's default timeout in that case.
        efibootmgr --timeout 20 || echo -e "\033[33m--- Warning: Could not set EFI boot timeout (firmware may lock this variable) ---\033[0m"

        # Install as fallback boot path for firmware compatibility. Some UEFI
        # implementations remove custom boot entries on reboot. The fallback
        # path /EFI/BOOT/BOOTX64.EFI is always recognized by compliant firmware.
        mkdir -p /boot/efi/EFI/BOOT
        cp /boot/efi/EFI/zbm/vmlinuz.EFI /boot/efi/EFI/BOOT/BOOTX64.EFI
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

        echo -e "\033[32m--- Downloading prebuilt ZFSBootMenu component images ---\033[0m"
        mkdir -p /boot/syslinux/zfsbootmenu
        if ! curl -L -o /tmp/zbm-components.tar.gz "$ZBM_BASE_URL/components/release"; then
            echo -e "\033[31m--- ERROR: Failed to download ZFSBootMenu component archive ---\033[0m"
            exit 1
        fi
        tar xzf /tmp/zbm-components.tar.gz --strip-components=1 -C /boot/syslinux/zfsbootmenu/
        rm -f /tmp/zbm-components.tar.gz

        echo -e "\033[32m--- Contents of /boot/syslinux/zfsbootmenu ---\033[0m"
        ls -l /boot/syslinux/zfsbootmenu

        cat > "/boot/syslinux/syslinux.cfg" << EOF
UI menu.c32
PROMPT 0

MENU TITLE Ditana Boot Menu
TIMEOUT 20

DEFAULT zfsbootmenu

LABEL zfsbootmenu
  MENU LABEL Ditana GNU/Linux
  KERNEL /zfsbootmenu/vmlinuz-bootmenu
  INITRD /zfsbootmenu/initramfs-bootmenu.img
  APPEND zfsbootmenu quiet $ZBM_CMDLINE
EOF
    fi # configured ZFSBootMenu for UEFI or BIOS

    zfs set org.zfsbootmenu:commandline="rw $KERNEL_OPTIONS efi=noruntime" ditana-root/ROOT
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

# Copyright (c) 2024, 2025, 2026 acrion innovations GmbH
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

find_crypto_luks_partition() {
    local BOOTIMAGE_PARTITION=$(blkid -L "ditana-boot")

    if [[ -z "$BOOTIMAGE_PARTITION" ]]; then
        echo ""
        return
    fi

    local PARENT_DEVICE="/dev/$(lsblk -no PKNAME "$BOOTIMAGE_PARTITION")"

    if [[ -z "$PARENT_DEVICE" ]]; then
        echo ""
        return
    fi

    while IFS= read -r PARTITION; do
        if [[ "$PARTITION" != "$BOOTIMAGE_PARTITION" ]]; then
            local FSTYPE=$(blkid -o value -s TYPE "$PARTITION")

            if [[ "$FSTYPE" == "crypto_LUKS" ]]; then
                echo "$PARTITION"
                return
            fi
        fi
    done < <(lsblk -ln -o NAME,TYPE "$PARENT_DEVICE" | awk '$2 == "part" {print "/dev/" $1}')

    echo ""
}


echo -e "\033[32m--- Ditana GNU/Linux rescue system ---\033[0m"

CRYPTO_LUKS_PARTITION=$(find_crypto_luks_partition)
if [[ -n "$CRYPTO_LUKS_PARTITION" ]]; then
    while true; do
        echo -e "\033[32m--- Note: \033[33mKeyboard Layout is US\033[0m"
        cryptsetup open "$CRYPTO_LUKS_PARTITION" root
        exit_code=$?
        if [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 5 ]]; then
            break; # correct passphrase or already mounted
        elif [[ $exit_code -ne 2 ]]; then # not bad passphrase (2)
            echo -e "\033[33m--- Unable to open root partition with command:\033[0m"
            echo -e "\033[33m--- cryptsetup open $CRYPTO_LUKS_PARTITION root\033[0m"
            exit 1
        fi
    done
fi

DEVICE_NAME=$(blkid -L "ditana-root")
FSTYPE=$(lsblk -no FSTYPE "$DEVICE_NAME")

echo -e "\033[32m--- Device name of root partition:\033[0m      $DEVICE_NAME"
echo -e "\033[32m--- File System Type of root partition:\033[0m $FSTYPE"

if [[ -z "$DEVICE_NAME" ]] || [[ -z "$FSTYPE" ]]; then
    lsblk -f
    echo -e "\033[33mCould not determine device name and/or file system type of root partition\033[0m"
    exit 1
fi

if [[ "$FSTYPE" == "zfs_member" ]] && ! zpool list ditana-root; then
    echo -e "\033[33m--- ZFSBootMenu malfunction! It failed to import the Ditana ZFS pool. Importing (Keyboard Layout is US!)... ---\033[0m"
    if ! zpool import -f -d /dev/disk/by-id -R /mnt ditana-root -N; then
        echo -e "\033[31m--- Failed to import the zfs pool ditana-root! ---\033[0m"
        exit 1
    fi
    
    LOAD_ENCRYPTION_KEY=""
    if [[ $(zpool get -H -o value feature@encryption ditana-root) == "active" ]]; then
       LOAD_ENCRYPTION_KEY="-l"
    fi
    
    zfs mount $LOAD_ENCRYPTION_KEY ditana-root/ROOT/default
    zfs mount $LOAD_ENCRYPTION_KEY -a
fi

set -e

echo -e "\033[32m--- Mounting... ---\033[0m"

if [[ "$FSTYPE" == "btrfs" ]]; then
    mount -o subvol=@,compress=zstd "$DEVICE_NAME" /mnt
    mount -o subvol=@home,compress=zstd "$DEVICE_NAME" /mnt/home
elif [[ "$FSTYPE" == "zfs_member" ]]; then
    zfs mount -a
else
    mount "$DEVICE_NAME" /mnt
fi

if [[ ! -d /mnt/root ]]; then
    echo -e "\033[31m--- Mounting failed! ---\033[0m"
    exit 1
fi

# Mount boot partition if present (non-ZFS systems use a separate boot partition)
BOOT_PARTITION=$(blkid -L "ditana-boot" 2>/dev/null || true)
if [[ -n "$BOOT_PARTITION" ]]; then
    mkdir -p /mnt/boot
    mount "$BOOT_PARTITION" /mnt/boot
fi

# Mount EFI partition if present
EFI_PARTITION=$(blkid -L "ditana-efi" 2>/dev/null || true)
if [[ -n "$EFI_PARTITION" ]]; then
    mkdir -p /mnt/boot/efi
    mount "$EFI_PARTITION" /mnt/boot/efi
fi

echo -e "\033[32m--- Mounting succeeded, entering chroot ---\033[0m"
touch /mnt/root/rescue-chroot.sh
mount --bind /root/rescue-chroot.sh /mnt/root/rescue-chroot.sh
arch-chroot /mnt /bin/bash /root/rescue-chroot.sh

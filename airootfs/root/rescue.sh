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

# --- BEGIN boot-repair --------------------------------------------------------
# Lifted by tests/airootfs/root/rescue-test, which cuts between BEGIN and END.
#
# Before the shell, diagnose-boot.sh is asked whether this system fails to boot
# for a reason it can repair. That is the common reason to be here at all: an
# update interrupted while it rebuilt the ZFS module or the initramfs. Until
# then it took leaving the shell again and knowing the script existed.
#
# offer_boot_repair returns 0 when the system was repaired and its pool
# exported, so there is nothing left to enter; 1 when the shell should follow,
# because nothing was found, the repair was declined, or it failed and left the
# pool imported for work by hand.
DIAGNOSE_BOOT="${DIAGNOSE_BOOT:-${BASH_SOURCE[0]%/*}/diagnose-boot.sh}"

offer_boot_repair() {
    local output status problems plan
    [[ $FSTYPE == zfs_member && -f $DIAGNOSE_BOOT ]] || return 1

    echo -e "\033[32m--- Checking why this system might not boot... ---\033[0m"
    mkdir -p /mnt/var/log
    output="$(bash "$DIAGNOSE_BOOT" --repair --dry-run --to /mnt/var/log 2>&1)"
    status=$?
    if (( status != 3 )); then
        echo -e "\033[32m--- Boot diagnosis: nothing it could repair. The report is in /var/log of the installed system. ---\033[0m"
        return 1
    fi

    problems="$(sed -n '/^Findings/,/^Full report/p' <<<"$output" \
                | grep -E 'MISSING|UNREADABLE|interrupted|db\.lck|matches no tree' | sed 's/^ *//')"
    plan="$(sed -n '/^Repair plan/,$p' <<<"$output")"
    if ! dialog --title "This system does not boot, and it can be repaired" \
                --yes-label "Repair" --no-label "Shell" --cr-wrap --no-collapse \
                --yesno "$problems

$plan

Repair, or open a shell in the installed system instead?" 0 0; then
        return 1
    fi

    if bash "$DIAGNOSE_BOOT" --repair; then
        if dialog --yesno "Repaired. Remove the medium and reboot now?" 6 50; then
            reboot
        fi
        return 0
    fi
    echo -e "\033[33m--- The repair did not succeed. The shell that follows is inside the installed system. ---\033[0m"
    return 1
}
# --- END boot-repair ----------------------------------------------------------

if [[ $FSTYPE == zfs_member ]] && offer_boot_repair; then
    return 0 2>/dev/null || exit 0
fi

echo -e "\033[32m--- Mounting succeeded, entering chroot ---\033[0m"
touch /mnt/root/rescue-chroot.sh
mount --bind /root/rescue-chroot.sh /mnt/root/rescue-chroot.sh
arch-chroot /mnt /bin/bash /root/rescue-chroot.sh

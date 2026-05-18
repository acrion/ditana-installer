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

lsblk -f
grep ^HOOKS /etc/mkinitcpio.conf

DEVICE_NAME=$(blkid -L "ditana-root")
FSTYPE=$(blkid -o value -s TYPE "$DEVICE_NAME")

if [[ "$FSTYPE" == "zfs_member" ]]; then
    zfs list -t snapshot
    echo "To restore one of the above zfs snapshots, use the following command:"
    echo "sudo zfs rollback <name>"
    echo "If this is not the latest snapshot, destroy the following snapshots first:"
    echo "sudo zfs destroy <name>"
elif command -v timeshift &>/dev/null; then
    grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
    read -p "Do you want to restore a Timeshift System Backup? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        timeshift --restore
    fi
fi
bash

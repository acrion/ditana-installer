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

if [[ "$(whoami)" == "root" ]] && [[ ! -f /tmp/ditana-set-font.sh ]] && blkid -L "ditana-root"; then
    if dialog --yesno "Detected Ditana installation. Enter rescue system?" 5 56; then
        source ./rescue.sh
        exit 0
    else
        # Check for unexpected mounts that would interfere with installation
        UNEXPECTED_MOUNTS=""
        while IFS= read -r MOUNT; do
            [[ -z "$MOUNT" ]] && continue
            [[ "$MOUNT" =~ ^/run/archiso/ ]] && continue

            UNEXPECTED_MOUNTS="${UNEXPECTED_MOUNTS}${MOUNT}\n"
        done < <(lsblk -no MOUNTPOINTS) 
        
        if [[ -n "$UNEXPECTED_MOUNTS" ]]; then
            dialog --msgbox "Error: Unexpected filesystems are mounted.

The following mounts were detected:
$(echo -e "$UNEXPECTED_MOUNTS")
This typically happens when rescue mode was previously
entered but not properly exited.

The system will now reboot to ensure a clean state
for installation." 15 60
            
            reboot
        fi
    fi
fi

if [[ $TERM == "linux" ]]; then
    setfont ter-112n
    export TERMINAL_COLUMNS=$(tput cols)
    export TERMINAL_LINES=$(tput lines)
    setfont ter-118b
fi

export PARENT_TERM=$TERM
source ditana-version.sh

while true; do
    tmux new-session -s ditana -d "echo 'Loading Ditana GNU/Linux Installer...' && ./main.raku"
    tmux attach -t ditana

    if [[ -f /tmp/ditana-set-font.sh ]]; then
        source /tmp/ditana-set-font.sh
    else
        break
    fi
done

if [[ -f /mnt/var/log/install_ditana.log ]]; then
    # Error during or after chroot-install.sh
    cat /mnt/var/log/install_ditana.log
elif  [[ -f /root/folders/var/log/install_ditana.log ]]; then
    # Error before chroot-install.sh
    cat /root/folders/var/log/install_ditana.log
fi

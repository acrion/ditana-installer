#!/usr/bin/env bash

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

# Apply the Ditana VT palette. OSC P sequences are interpreted only by
# the Linux console driver — on graphical terminals (xterm, kitty, foot,
# serial consoles) they would surface as visible garbage, so we gate on
# TERM=linux. DIALOGRC is exported unconditionally: dialog honours it
# regardless of which terminal type it runs in.
apply_vt_palette() {
    if [[ "$TERM" == "linux" ]]; then
        printf '\e]P00d1117\e]P1f85149\e]P23fb950\e]P3ffbb00\e]P458a6ff\e]P5d2a8ff\e]P639c5cf\e]P7e6edf3\e]P8484f58\e]P9ff7b72\e]PA56d364\e]PBffd966\e]PC79c0ff\e]PDd2a8ff\e]PE56d4dd\e]PFe6edf3'
    fi
}
export DIALOGRC=/root/installer.dialogrc
apply_vt_palette  # (A) Before the rescue-mode dialog further down.

if [[ "$(whoami)" == "root" ]] && [[ ! -f /tmp/ditana-set-font.sh ]] && blkid -L "ditana-root"; then
    if dialog --yesno "Detected Ditana installation. Enter rescue system?" 5 56; then
        source ./rescue.sh
        exit 0
    else
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
    apply_vt_palette  # (B) setfont can drop the palette on some kernels.
fi

export PARENT_TERM=$TERM
source ditana-version.sh

while true; do
    apply_vt_palette  # (C) Safety net: the font-change loop sources a
                      # script that runs setfont again before re-entry.
    tmux kill-session -t ditana 2>/dev/null || true

    tmux new-session -s ditana -d -c "$(pwd)" sh -c '
        dialog --infobox "Loading Ditana GNU/Linux Installer..." 3 50
        ./main.raku
    '

    tmux attach -t ditana

    if [[ -f /tmp/ditana-set-font.sh ]]; then
        source /tmp/ditana-set-font.sh
    else
        break
    fi
done

if [[ -f /mnt/var/log/install_ditana.log ]]; then
    # Error during or after chroot-install.sh
    tail -n 100 /mnt/var/log/install_ditana.log
elif  [[ -f /root/folders/var/log/install_ditana.log ]]; then
    # Error before chroot-install.sh
    tail -n 100 /root/folders/var/log/install_ditana.log
fi


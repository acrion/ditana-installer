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

if [[ "$1" == "y" ]] && ! grep -q "^\[chaotic-aur\]" /etc/pacman.conf; then
    echo -e "\033[32m--- Enabling and signing the automated building repo for AUR packages (https://github.com/chaotic-aur/packages) --- \033[0m"

    execute_with_retries() {
        local attempt=1
        local max_attempts=$1
        local command=$2
        local fail_message=$3

        while [[ "$attempt" -le "$max_attempts" ]]; do
            if eval "$command"; then
                return 0
            else
                echo "Attempt $attempt failed. Retrying..."
                ((attempt++))
            fi
        done

        echo "$fail_message in $max_attempts attempts, which is a fatal error."
        exit 1
    }

    max_attempts=3

    if ping -c 1 keyserver.ubuntu.com &> /dev/null; then
        execute_with_retries $max_attempts "pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com" \
            "Executing 'pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com' failed"
    else
        echo -e "\033[33m--- No Internet or keyserver.ubuntu.com is down => using key from Ditana ISO --- \033[0m"
        if [[ -f chaotic-aur-key.asc ]]; then # chrooted environment
            key_file=chaotic-aur-key.asc
        else # live environment
            key_file=bind-mount/root/chaotic-aur-key.asc
        fi

        while fuser /etc/pacman.d/gnupg/trustdb.gpg &>/dev/null; do
            echo -e "\033[33m--- trustdb.gpg is in use, waiting for release --- \033[0m"
            sleep 1
        done
        
        execute_with_retries $max_attempts "pacman-key --add $key_file"
    fi

    execute_with_retries $max_attempts "pacman-key --lsign-key 3056513887B78AEB" \
        "Executing 'pacman-key --lsign-key 3056513887B78AEB' failed"

    execute_with_retries $max_attempts "pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'" \
        "Installing 'chaotic-keyring.pkg.tar.zst' failed"

    execute_with_retries $max_attempts "pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'" \
        "Installing 'chaotic-mirrorlist.pkg.tar.zst' failed"

    if [[ ! -f /etc/pacman.d/chaotic-mirrorlist ]]; then
        echo "After enabling Chaotic-AUR as described on https://aur.chaotic.cx/docs without any errors, the file '/etc/pacman.d/chaotic-mirrorlist' is missing, which is a fatal error."
        exit 1
    fi

    echo "" >> /etc/pacman.conf
    echo "[chaotic-aur]" >> /etc/pacman.conf
    echo "Include = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf
fi

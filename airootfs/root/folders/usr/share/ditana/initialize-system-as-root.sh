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

# This script is executed as a one-time service after the initial installation of the Ditana GNU/Linux distribution.
# It is designed to perform system initialization tasks that cannot be executed within a chroot environment.
# This script is scheduled to run at the first boot of the newly installed system by enabling the systemd service
# located at /etc/systemd/system/ditana-initialize-system.service during the chroot phase of the installation via
# the chroot-install.sh script.

{
    if [[ -f /usr/share/ditana/initialize-wifi.sh ]]; then
        if /usr/share/ditana/initialize-wifi.sh &> /dev/null; then
            echo "Successfully initialized Wi-Fi, deleting file that contained the Wi-Fi password."
            shred -u /usr/share/ditana/initialize-wifi.sh
        fi
    fi

    if [[ -f /usr/lib/virtualbox/additions/VBoxGuestAdditions.iso ]] && systemd-detect-virt -q; then
        echo "Installing VirtualBox guest additions..."
        mkdir -p /tmp/virtualbox-guest
        mount -o loop /usr/lib/virtualbox/additions/VBoxGuestAdditions.iso /tmp/virtualbox-guest/
        pushd /tmp/virtualbox-guest/
        if [[ -f VBoxLinuxAdditions.run ]]; then
            ./VBoxLinuxAdditions.run
            USER_NAME=$(getent passwd | awk -F: '$6 ~ /^\/home\// {print $1; exit}')
            usermod -aG vboxsf "$USER_NAME"
            echo "VirtualBox guest additions installed successfully."
        else
            echo "Error: did not find expected file VBoxLinuxAdditions.run in mounted VBoxGuestAdditions.iso"
        fi
        popd
        umount /tmp/virtualbox-guest/
        rmdir /tmp/virtualbox-guest
        echo "Finished installing VirtualBox guest additions."
    fi
} 2>&1 | tee -a /var/log/install_ditana.log

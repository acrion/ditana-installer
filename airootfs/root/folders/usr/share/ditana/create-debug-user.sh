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

set -e

allow_access_to_logfile() {
    if ! id "debuguser" &>/dev/null; then
        useradd -m -s /bin/bash debuguser
        passwd debuguser
    fi

    log_path="$1"

    parent_path="$(dirname "$log_path")"
    while [ "$parent_path" != "/" ]; do
        setfacl -m u:debuguser:x "$parent_path"
        parent_path="$(dirname "$parent_path")"
    done

    setfacl -m u:debuguser:r "$log_path"

    ip_addr=$(ip addr show | grep -oE 'inet (10|172|192)\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d' ' -f2)
    ip_addr=${ip_addr:-"<IP>"}

    echo "To retrieve the log file from another machine, please execute this command from the other machine (don’t forget the dot . at the end):"
    echo "scp debuguser@$ip_addr:$log_path ."
}

log_paths=("/var/log/install_ditana.log" # chrooted or running system
           "/mnt/var/log/install_ditana.log" # live system after copying
           "/root/folders/var/log/install_ditana.log") # live system before copying

for log_path in "${log_paths[@]}"; do
    if [ -f "$log_path" ]; then
        allow_access_to_logfile "$log_path"
        break
    fi
done

if [ ! -f "$log_path" ]; then
  echo "Error: The file install_ditana.log is missing."
fi

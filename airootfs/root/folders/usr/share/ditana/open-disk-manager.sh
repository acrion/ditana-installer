#!/usr/bin/env bash

# Copyright (c) 2024, 2025 acrion innovations GmbH
# Authors: Stefan Zipproth, s.zipproth@acrion.ch
#
# This file is part of ditana-config-xfce, see https://github.com/acrion/ditana-config-xfce
#
# ditana-config-xfce is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ditana-config-xfce is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with ditana-config-xfce. If not, see <https://www.gnu.org/licenses/>.

main() {
    local path="$1"
    local block_dev
    local df_output

    if [[ -z "$path" ]]; then
        echo "No path provided" | systemd-cat -t ditana-open-disk-manager -p err
        zenity --error --text="No path provided."
        exit 1
    fi

    echo "Script started with original path: $path" | systemd-cat -t ditana-open-disk-manager -p debug

    if [[ -b "$path" ]]; then
        block_dev="$path"
        echo "Path is already a block device: $block_dev" | systemd-cat -t ditana-open-disk-manager -p debug
    else
        if ! df_output=$(/bin/df -P "$path" 2>&1); then
            echo "df -P $path failed: $df_output" | systemd-cat -t ditana-open-disk-manager -p warning
            zenity --error --text="Failed to get disk information for $path"
            exit 1
        fi
        echo "df output: $df_output" | systemd-cat -t ditana-open-disk-manager -p debug
        block_dev=$(echo "$df_output" | awk 'NR==2 {print $1}')
        echo "Extracted block device: $block_dev" | systemd-cat -t ditana-open-disk-manager -p debug
    fi

    if [[ -n "$block_dev" ]]; then
        echo "Opening gnome-disks with block device: $block_dev" | systemd-cat -t ditana-open-disk-manager -p debug
        if gnome-disks --block-device "$block_dev"; then
            echo "gnome-disks started successfully for $block_dev" | systemd-cat -t ditana-open-disk-manager -p debug
        else
            echo "Failed to start gnome-disks for $block_dev" | systemd-cat -t ditana-open-disk-manager -p err
            zenity --error --text="Failed to open disk manager for $block_dev"
            exit 1
        fi
    else
        echo "Error: Could not find block device for $path" | systemd-cat -t ditana-open-disk-manager -p warning
        zenity --error --text="Could not find block device for $path"
        exit 1
    fi
}

main "$@"

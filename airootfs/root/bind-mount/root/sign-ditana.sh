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

KEY_S_ZIPPROTH_AT_DITANA_ORG="3F8054C3FF755E5544E68516BC333E9AE877D45A"

if [[ ! -d /etc/pacman.d/gnupg ]]; then
    pacman-key --init
    pacman-key --populate archlinux
fi

if ! pacman-key --keyserver hkps://keys.openpgp.org --recv-key $KEY_S_ZIPPROTH_AT_DITANA_ORG; then
    echo -e "\033[33m--- No Internet or keys.openpgp.org is down => using key from Ditana ISO --- \033[0m"
    if [[ -f ditana-key.asc ]]; then # chrooted environment
        pacman-key --add ditana-key.asc
    else # live environment
        pacman-key --add folders/root/ditana-key.asc
    fi
fi

pacman-key --lsign-key $KEY_S_ZIPPROTH_AT_DITANA_ORG
pacman-key --updatedb

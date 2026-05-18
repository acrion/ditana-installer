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

if ! grep -q "^\[ditana\]" /etc/pacman.conf; then
    cat <<EOF >>/etc/pacman.conf

[ditana]
Include = /etc/pacman.d/ditana-mirrorlist
EOF
fi

# package 'ditana-filesystem' replaces base package 'filesystem'
sed -i 's/^#IgnorePkg[ ]*=/IgnorePkg   = filesystem/' /etc/pacman.conf

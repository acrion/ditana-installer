#!/bin/sh

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

# Set XDG Base Directory variables for Ditana GNU/Linux
# This script ensures XDG_STATE_HOME and XDG_DATA_HOME are set correctly
# These variables are not set by the default XFCE4 xinitrc script
# (/etc/xdg/xfce4/xinitrc) provided by the Arch package xfce4-session

# Set XDG_STATE_HOME if not already set
if [ -z "$XDG_STATE_HOME" ]; then
    XDG_STATE_HOME="$HOME/.local/state"
    export XDG_STATE_HOME
fi

# Set XDG_DATA_HOME if not already set
if [ -z "$XDG_DATA_HOME" ]; then
    XDG_DATA_HOME="$HOME/.local/share"
    export XDG_DATA_HOME
fi

# Source user-dirs.dirs to set user-specific directories
if [ -f "$XDG_CONFIG_HOME/user-dirs.dirs" ]; then
    . "$XDG_CONFIG_HOME/user-dirs.dirs"
    export XDG_DESKTOP_DIR XDG_DOWNLOAD_DIR XDG_TEMPLATES_DIR XDG_PUBLICSHARE_DIR \
           XDG_DOCUMENTS_DIR XDG_MUSIC_DIR XDG_PICTURES_DIR XDG_VIDEOS_DIR
fi

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

# This script is executed once for each user via $HOME/.xprofile

shopt -s dotglob

{
    if command -v ditana-assistant &> /dev/null; then
        PINNED_APPS_FRONT="ditana-assistant;"
    fi

    if pacman -Qi librewolf &> /dev/null; then
        PINNED_APPS_FRONT+="librewolf;"
    elif pacman -Qi zen-browser-bin &> /dev/null; then
        PINNED_APPS_FRONT+="zen;"
    elif pacman -Qi chromium &> /dev/null; then
        PINNED_APPS_FRONT+="chromium;"
    elif pacman -Qi floorp &> /dev/null; then
        PINNED_APPS_FRONT+="floorp;"
    elif pacman -Qi brave-bin &> /dev/null; then
        PINNED_APPS_FRONT+="brave-browser;"
    elif pacman -Qi firefox &> /dev/null; then
        PINNED_APPS_FRONT+="firefox;"
    fi

    if pacman -Qi ghostty &> /dev/null; then
        PINNED_APPS_FRONT+="com.mitchellh.ghostty;"
    elif pacman -Qi kitty &> /dev/null; then
        PINNED_APPS_FRONT+="kitty;"
    elif pacman -Qi alacritty &> /dev/null; then
        PINNED_APPS_FRONT+="Alacritty;"
    fi
    
    if command -v logseq &> /dev/null; then
        PINNED_APPS_FRONT+="logseq-desktop;"
    fi

    PINNED_APPS_BACK=""

    if command -v pacseek &> /dev/null; then
        # we use the generic `system-software-install` icon instead of the pacseek specific that org.moson.pacseek.desktop references
        PINNED_APPS_BACK+="pacseek-desktop;"
    fi

    if command -v code &> /dev/null; then
        if pacman -Qi code &> /dev/null; then
            PINNED_APPS_BACK+="code-oss;"
        else
            PINNED_APPS_BACK+="code;"
        fi
    fi

    if pacman -Qi bitwarden &> /dev/null; then
        PINNED_APPS_BACK+="bitwarden;"
    fi

    if command -v backintime &> /dev/null; then
        PINNED_APPS_BACK+="backintime-qt;"
    fi

    if command -v stable-diffusion-ui-server &> /dev/null && [[ -f /usr/share/applications/stable-diffusion.desktop ]]; then
        PINNED_APPS_BACK+="stable-diffusion;"
    fi

    sed -i "/^pinned=/ s/pinned=/pinned=$PINNED_APPS_FRONT/" "$HOME/.config/xfce4/panel/docklike-2.rc"
    sed -i "/^pinned=/ s/$/$PINNED_APPS_BACK/" "$HOME/.config/xfce4/panel/docklike-2.rc"

    if [[ -d "$HOME/.config/variety" ]]; then
        # skip variety setup dialog
        echo -n "$(date '+%Y-%m-%d %H:%M:%S')" > "$HOME/.config/variety/.firstrun"
    fi

} 2>&1 | tee >(systemd-cat -t ditana-pre-xfce-first-login -p info)

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

# This script is executed once after the first XFCE login of each user via
# /etc/xdg/autostart/ditana-xfce-first-login.desktop.
# After execution, it disables itself for the current user using the XDG
# autostart override mechanism (Hidden=true in ~/.config/autostart/).

shopt -s dotglob
mkdir -p "$HOME/.ditana"
LOG_PATH="$HOME/.ditana/xfce-first-login.log"

{
    # Set the XFCE-specific checksum metadata to avoid the XFCE message
    # "The desktop file ... is in an insecure location and not marked as executable."
    trust_link() {
        local DESKTOP_LINK="$1"
        if [[ -f "$DESKTOP_LINK" ]]; then
            chmod +x "$DESKTOP_LINK"
            gio set -t string "$DESKTOP_LINK" metadata::xfce-exe-checksum "$(sha256sum "$DESKTOP_LINK" | awk '{print $1}')"
        fi
    }

    parse_xfce_primary() {
        local DISPLAYS_FILE=$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/displays.xml

        if [[ -f "$DISPLAYS_FILE" ]]; then
            # Extract the name of the primary display from XFCE’s display configuration.
            # Using xmlstarlet for precise XML parsing, which offers more flexibility
            # than xfconf-query for this specific nested property query.
            xmlstarlet sel -t -v "//property[@name='Default']/property[property[@name='Primary' and @value='true']]/@name" "$DISPLAYS_FILE"
        fi
    }

    get_physical_size() {
        local WIDTH_MM=$(echo "$1" | grep -oP '\d+mm x \d+mm' | cut -d'x' -f1 | grep -oP '\d+')
        local HEIGHT_MM=$(echo "$1" | grep -oP '\d+mm x \d+mm' | cut -d'x' -f2 | sed 's/mm//')
        local WIDTH_MM=${WIDTH_MM:-0}
        local HEIGHT_MM=${HEIGHT_MM:-0}

        echo "scale=1; sqrt($WIDTH_MM^2 + $HEIGHT_MM^2) / 25.4" | bc -l
    }

    get_xfce_primary() {
        local XFCE_PRIMARY="$(parse_xfce_primary)"

        if [[ -z "$XFCE_PRIMARY" ]]; then
            # Sometimes XFCE does not designate a primary display even if several displays are connected.
            # Iterate through all connected displays and find the one with the largest size.
            local LARGEST_SIZE=-1
            local XRANDR_INFO=""
            while read -r line; do
                local DISPLAY_SIZE=$(get_physical_size "$line")
                if (( $(echo "$DISPLAY_SIZE > $LARGEST_SIZE" | bc -l) )); then
                    LARGEST_SIZE=$DISPLAY_SIZE
                    XRANDR_INFO=$line
                fi
            done < <(xrandr | grep " connected")
            
            XFCE_PRIMARY=${XRANDR_INFO%% *}
        fi

        echo $XFCE_PRIMARY
    }

    if ! pgrep -x "xfwm4" > /dev/null; then
        echo "No process xfwm4 found. $0 is meant to configure XFCE."
        exit 0
    fi

    AUTOSTART_NAME="ditana-xfce-first-login.desktop"
    NEW_WALLPAPER='/usr/share/backgrounds/xfce/ditana-wallpaper.jpg'

    if [[ -f "$NEW_WALLPAPER" ]]; then
        # xfconf-query cannot be executed in chroot, and the xfce4-desktop.xml file contains system specific strings.
        # Hence, this script is intended for first login of each new user.
        XFCE_PRIMARY=$(get_xfce_primary)
        
        if [[ -n "$XFCE_PRIMARY" ]]; then
            for workspace in {0..3}; do
                xfconf-query -c xfce4-desktop --create --type string --property "/backdrop/screen0/monitor$XFCE_PRIMARY/workspace${workspace}/last-image" --set "$NEW_WALLPAPER"
            done
        fi

        echo "Wallpaper for $XFCE_PRIMARY set to $NEW_WALLPAPER"
    else
        echo "Wallpaper file $NEW_WALLPAPER does not exist."
    fi

    # Creating a file in /etc/dconf/db/local.d/ does not work, presumably due to how XFCE emulates dconf.
    # Example settings that would be configured there:
    # [org/gnome/desktop/interface]
    # monospace-font-name='JetBrainsMono Nerd Font 9'
    gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 9'
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gsettings set org.gnome.desktop.interface gtk-theme 'Dracula'
    gsettings set org.gnome.desktop.interface icon-theme 'kora-yellow'

    # DEPRECATED: The following two settings are maintained for backwards compatibility
    # with XFCE’s dconf compatibility mode. While no longer actively used in modern GNOME
    # environments, retaining these settings ensures system stability and doesn't
    # introduce any adverse effects.
    # The primary configuration for the default terminal is now managed through
    # the '/etc/xdg/xdg-terminals.list' file.
    # For more information, refer to: https://github.com/Vladimir-csp/xdg-terminal-exec
    gsettings set org.gnome.desktop.default-applications.terminal exec 'xdg-terminal-exec'
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'

    # Wait for gvfsd-metadata to become available (started on-demand by D-Bus)
    for i in $(seq 1 30); do
        if gio set -t string /dev/null metadata::test test 2>/dev/null; then
            break
        fi
        sleep 0.5
    done
    
    if [[ -f "$HOME/.config/user-dirs.dirs" ]]; then
        source "$HOME/.config/user-dirs.dirs"
    fi
    XDG_DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Desktop}"

    trust_link "$XDG_DESKTOP_DIR/Donate to Ditana.desktop"
    trust_link "$XDG_DESKTOP_DIR/Best Practices.desktop"

    systemctl --user enable --now xfce-display-config-observer.service

    # Workaround for gnome-keyring initialization issue on first login
    # This restarts the gnome-keyring-daemon to ensure proper initialization
    # The user will still need to unlock the keyring via a dialog, but this prevents
    # tools like secret-tool from freezing and allows the browser to start properly
    # For more information, see: https://gitlab.gnome.org/GNOME/gnome-keyring/-/issues/116
    systemctl --user restart gnome-keyring-daemon.service

    # Ditana keyboard shortcuts, as explained in the desktop cheat sheet (except the system monitor, which is adapted but not mentioned)
    xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary><Shift>Escape" -n -t string -s "gnome-system-monitor"
    xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>space" -n -t string -s "/usr/bin/catfish"
    xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Alt>Page_Up" -n -t string -s "pactl set-sink-volume @DEFAULT_SINK@ +1%"
    xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Alt>Page_Down" -n -t string -s "pactl set-sink-volume @DEFAULT_SINK@ -1%"
    xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary>Page_Up" -n -t string -s "prev_workspace_key"
    xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary>Page_Down" -n -t string -s "next_workspace_key"
    xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Alt>Page_Up" -n -t string -s "move_window_prev_workspace_key"
    xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Alt>Page_Down" -n -t string -s "move_window_next_workspace_key"

    # Audio is muted by default for new users (especially post-installation), requiring an adjustment.
    sleep 2 # Adding a delay to avoid setting volume during xfce4-pulseaudio-plugin initialization, as this seems to cause sporadic crashes
    pactl set-sink-mute @DEFAULT_SINK@ 0
    pactl set-sink-volume @DEFAULT_SINK@ 50%

    # Disable this autostart entry for the current user using the XDG override mechanism
    mkdir -p "$HOME/.config/autostart"
    cp "/etc/xdg/autostart/$AUTOSTART_NAME" "$HOME/.config/autostart/$AUTOSTART_NAME"
    sed -i 's/^Hidden=false/Hidden=true/' "$HOME/.config/autostart/$AUTOSTART_NAME"
} 2>&1 | tee -a "$LOG_PATH"

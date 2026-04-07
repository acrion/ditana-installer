#!/usr/bin/env bash

# This script is started by /etc/systemd/user/ditana-ramdisk.service

RAMDISK="/run/user/$(id -u)/ramdisk"
mkdir -p "$RAMDISK"

if [[ ! -e "$HOME/RAMDisk" ]]; then
    ln -s "$RAMDISK" "$HOME/RAMDisk"
fi

if command -v thunar &> /dev/null; then
    THUNARS_GTK_CONFIG_DIR="$HOME/.config/gtk-3.0"
    mkdir -p "$THUNARS_GTK_CONFIG_DIR"
    grep -q "RAM Disk" "$THUNARS_GTK_CONFIG_DIR/bookmarks" || \
    echo "file://$RAMDISK RAM Disk" >> "$THUNARS_GTK_CONFIG_DIR/bookmarks"
fi

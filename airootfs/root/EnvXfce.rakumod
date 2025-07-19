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

use v6.d;
use Settings;

sub set-host-dpi() is export
{
    # This file is read by package xfce-display-config-observer, see /usr/lib/xfce4/display-config-observer/observer.sh of that package 
    my $basedir = "/mnt/etc/skel/.config/xfce4/display-config-observer/dpi";
    $basedir.IO.mkdir;
    "$basedir/value".IO.spurt(Settings.instance.get("host-dpi"));
}

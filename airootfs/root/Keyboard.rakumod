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
use Chroot;

# Sets keyboard repeat rate for Virtual Terminals only.
# This does not affect graphical environments like Wayfire or XFCE.
sub create-keyboard-service() is export {
    my $keyboard-rate = Settings.instance.get("keyboard-rate");
    my $keyboard-delay = Settings.instance.get("keyboard-delay");
    my $service_name = "ditana_kbdrate";

    my $content = qq:to/END/;
[Unit]
Description=Set keyboard repeat rate and delay in tty.

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '/usr/bin/kbdrate --silent --delay $keyboard-delay --rate $keyboard-rate || echo "VT keyboard repeat settings unchanged - hardware does not support configuration"'

[Install]
WantedBy=multi-user.target
END

    "/mnt/etc/systemd/system/$service_name.service".IO.spurt($content);
    add-chrooted-step("systemctl enable $service_name");
}

sub create-xfce-keyboard-xml() is export {
    my $keyboard-rate = Settings.instance.get("keyboard-rate");
    my $keyboard-delay = Settings.instance.get("keyboard-delay");
    
    my $content = qq:to/END/;
<?xml version="1.0" encoding="UTF-8"?>

<channel name="keyboards" version="1.0">
  <property name="Default" type="empty">
    <property name="Numlock" type="bool" value="false"/>
    <property name="KeyRepeat" type="empty">
      <property name="Rate" type="int" value="$keyboard-rate"/>
      <property name="Delay" type="int" value="$keyboard-delay"/>
    </property>
  </property>
</channel>
END

    "/mnt/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/keyboards.xml".IO.spurt($content);
}

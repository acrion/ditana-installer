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


# The installed lightdm.conf contains all available settings as commented lines.
# This function relies on this structure and only modifies lines that match the exact
# pattern: optional '#' characters, optional whitespace, 'greeter-session=', and content.
# Lines with whitespace between identifier and '=' sign are exclusively used in documentation
# and deliberately ignored to prevent configuration corruption.
sub configure-slick-greeter() is export
{
    my $lightdm-conf = "/etc/lightdm/lightdm.conf".IO;

    $lightdm-conf.spurt($lightdm-conf.slurp.subst(/^^ '#'* \s* 'greeter-session=' \N* $$/, "greeter-session=lightdm-slick-greeter"));
}

sub enable-lightdm() is export
{
    add-chrooted-step(q{systemctl enable lightdm.service});
}

sub disable-dmabuf-for-webkit() is export
{
    '/mnt/etc/environment'.spurt("
# Ditana customization: Disable the DMA-BUF renderer for WebKitGTK applications
# on systems with NVIDIA graphics cards. The issue affects both proprietary
# and open-source NVIDIA drivers, causing rendering problems. Disabling DMA-BUF
# forces WebKit to use software rendering for stability.
WEBKIT_DISABLE_DMABUF_RENDERER=1
", :append);
}

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

use v6.d;
use Settings;
use Logging;

sub create-mimeapps-list() is export {
    Logging.log("Creating MIME applications list from KDL settings...");

    my $s = Settings.instance;
    my $mimeapps-path = $s.get("real-install")
        ?? "/mnt/usr/share/applications/mimeapps.list"
        !! "/tmp/ditana-mimeapps.list";
    $mimeapps-path.IO.parent.mkdir unless $mimeapps-path.IO.parent.d;

    my %mime = $s.get-mime-defaults();

    if %mime.elems > 0 {
        my $content = "[Default Applications]\n";
        for %mime.sort(*.key) -> $pair {
            $content ~= "{$pair.key}={$pair.value}\n";
        }

        $mimeapps-path.IO.spurt($content);
        Logging.log("Created MIME applications list at $mimeapps-path with {%mime.elems} associations.");
    } else {
        Logging.log("No MIME defaults configured in active settings.");
    }
}

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
use Logging;
use Settings;

constant PENDING-FILE = '/mnt/var/lib/ditana/flatpak-pending';

# Writes the list of selected Flatpak applications to a pending file in the
# target system. The actual installation happens at first boot via the
# ditana-flatpak-finalize.service systemd unit, which blocks greetd until
# completion to avoid post-login waits.
sub prefetch-flatpaks() is export {
    my @apps = Settings.instance.get-installed-flatpak-packages;

    unless @apps {
        Logging.log("No Flatpak applications selected — skipping.");
        return;
    }

    my $dir = PENDING-FILE.IO.parent;
    $dir.mkdir unless $dir.e;

    PENDING-FILE.IO.spurt(@apps.join("\n") ~ "\n");
    Logging.log("Wrote pending list to {PENDING-FILE}: {@apps.join(', ')}");
}

# Copyright (c) 2026 acrion innovations GmbH
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

#| What the configuration says about itself.
#|
#| ditana-config ships two files beside the installer that unpacks it:
#| `config_hash.txt` names the commit the configuration was built from, and
#| `config_date.txt` when it was published. A run that never downloaded
#| anything has neither, and "unknown" is then the honest answer -- it is also
#| what the installed system is told.
sub config-state(IO::Path:D $config-dir --> Hash) is export {
    my sub value-of(Str $name) {
        my $file = $config-dir.child($name);
        $file.e ?? $file.slurp(:close).trim !! 'unknown';
    }

    { hash => value-of('config_hash.txt'), date => value-of('config_date.txt') }
}

#| Put the configuration state where the rest of the installation finds it.
#|
#| This has to happen on every pass through main(), and that is the whole
#| reason it is a sub of its own. The installer ends and is started again to
#| change the console font, so the process that carries out the installation is
#| usually not the one that downloaded the configuration: anything published
#| only on the first pass is absent for the rest of the installation, and
#| DITANA_CONFIG_HASH is what Chroot's add-version() writes into
#| /usr/lib/os-release as VERSION_CODENAME.
#|
#| Reading the two files again costs nothing and cannot disagree with what was
#| unpacked, because they are what was unpacked.
sub publish-config-state(IO::Path:D $config-dir --> Hash) is export {
    my %state = config-state($config-dir);
    %*ENV<DITANA_CONFIG_HASH> = %state<hash>;
    Logging.log("Loaded configuration state: %state<hash> (%state<date>)");
    %state
}

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
use RunAndLog;
use Logging;
use Settings;

#| Generate a name for the new machine, unless one already exists.
#|
#| An answer file is applied before the first installation step, and an
#| unattended run proceeds through this procedure in the same manner as any
#| other run. A name provided by the file is therefore already set when this
#| runs, and overwriting it would result in installing the machine under a
#| random name, regardless of what the file says. In an interactive run, no
#| component sets host-name before this step, so the subsequent dialog
#| requesting it still offers the name generated here.
sub generate-host-name() is export {
  return if Settings.instance.get("host-name");

  my $proc = run <pwgen -A -0 5 1>, :out;
  my $host-name = $proc.out.slurp(:close).trim;
  Settings.instance.set("host-name", "ditana-" ~ $host-name);
}

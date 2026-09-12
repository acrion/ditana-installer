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

#| The installer unwinding itself on purpose, so that it can be started again.
#|
#| One step changes the console font, and a font can only be changed for a
#| virtual terminal that is not in use -- so the installer writes a hook file,
#| ends, and `run-ditana-installer.sh` sources the hook and starts it again.
#| The installation continues in the next process; nothing has failed.
#|
#| It needs a type of its own because a `die` with a string is, at the top of
#| the program, indistinguishable from an installation that has stopped -- and
#| that difference decides whether the serial console is told the run is over.
#| See `announce-unattended-abort` in Autoinstall.rakumod.
class X::Ditana::Restart is Exception {
    has Str:D $.reason is required;
    method message(--> Str:D) { $!reason }
}

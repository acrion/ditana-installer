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
use Dialogs;

sub welcome() returns Int is export {
    my $text = q:to/END/.chomp;
                             Welcome to Ditana GNU/Linux $version
______________________________________________________________________________________________

To learn more about Ditana, visit our website at:

                                       https://ditana.org

To view the source code and contribute to the development of Ditana,
visit our main Git repository (hub for all Ditana-specific repos) at:

                           https://github.com/acrion/ditana-installer
______________________________________________________________________________________________

Navigate through the settings dialogs using your mouse or these keys:

  - ENTER to confirm selections and proceed to the next dialog
  - ESCAPE to go back to the previous dialog to review or alter settings
  - CURSOR KEYS and TAB to navigate between options and buttons, e.g. < Help >
  - SPACE to toggle an option

No changes will be made to your system until you confirm in the final dialog.

                               A Note on Software Licenses

In the following installation dialogs, we categorize software as either «FOSS» (Free and Open
Source Software) or «CLOSED» (non-open source software). After this category, the specific
license identifier for each package is provided, see https://spdx.org/licenses for details.

Please note that some software, including FOSS, may be dual-licensed, but commercial use or
distribution is still permitted under the FOSS license as long as its terms are met. If you
plan to use dual-licensed software in a commercial setting, reviewing its full license details
may offer additional flexibility and benefits.

Enjoy customizing Ditana to your preferences!
END

    show-dialog-raw(
        '--no-collapse',
        '--msgbox',
        $text.subst(q{$version}, %*ENV<DITANA_VERSION> // ""),
        $text.lines + 4,
        98
    )<status>
}

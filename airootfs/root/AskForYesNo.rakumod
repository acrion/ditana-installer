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
use Dialogs;
use Settings;
use Logging;

multi ask-for-yes-no(:$title = '', :$instruction, :$default = True, :$yes-label="Yes", :$no-label="No") is export {
    my $columns = 98;
    my %reformatted-text = calculate-wrapped-lines($instruction, $columns-4); # 98 width minus border
    
    Logging.log($instruction);
    
    my @dialog-args;
    @dialog-args.append('--defaultno') unless $default;

    my $text = %reformatted-text<text>;
    my $lines = %reformatted-text<lines>+4;

    if $title.chars > 0 {
        $text = "\n" ~ $text;
        $lines++;
    }

    my %dialog-result = show-dialog-raw(
        '--title', $title,
        |@dialog-args,
        "--yes-label", $yes-label,
        "--no-label", $no-label,
        "--yesno",
        $text,
        $lines,
        $columns
    );

    return %dialog-result<status>;
}

multi ask-for-yes-no($dialog) is export {
    my $title = kebab-to-title($dialog<name>);
    my $instruction = $dialog<instruction>;
    my $default = Settings.instance.get($dialog<name>);
    my $dialog-result = ask-for-yes-no(:$title, :$instruction, :$default);

    given $dialog-result {
        when 0 {
            Settings.instance.set($dialog<name>, True);
            return 0;
        }
        when 1 {
            Settings.instance.set($dialog<name>, False);
            return 0; # user clicked "no", which we do not treat like "cancel" in other dialog types, but as a valid result
        }
        default {
            return $dialog-result; # user canceled by pressing the escape key
        }
    }
}

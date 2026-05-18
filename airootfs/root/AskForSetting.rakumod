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
use MONKEY-SEE-NO-EVAL;

sub validate-name($name) {
    return False if $name.chars == 0; # Check if name is empty
    return False if $name.chars > 32; # Check length
    return False unless $name ~~ /^ <[a..z_]> <[a..z0..9_\-]>* $/; # Check if it starts with [a-z_], followed by [a-z0-9_-]
    return False if $name ~~ /'-' '-'/; # Check for consecutive hyphens
    return False if $name ~~ /'-' $/; # Check for trailing hyphen (leading is already covered by first pattern)
    
    return True;
}

sub validate-number($value) {
    return so $value ~~ /^ \d+ ['.' \d+]? $/;
}

sub validate-integer($value) {
    return so $value ~~ /^ <[1..9]> \d* $/;
}

sub ask-for-setting($dialog) is export {
    my %dialog-result;

    my $width = 73;
    my $border-of-inputbox = 4;
    my %reformatted-text = calculate-wrapped-lines($dialog<instruction>, $width-$border-of-inputbox);
    
    loop {
        Logging.log("ask-for-setting {$dialog<name>}: showing input dialog");
        %dialog-result = show-dialog-raw(
            '--title',
            kebab-to-title($dialog<name>),
            '--no-collapse',
            '--cancel-label', "Back",
            '--inputbox',
            "\n" ~ %reformatted-text<text>,
            %reformatted-text<lines>+7,
            $width,
            Settings.instance.get($dialog<name>));
            
        if %dialog-result<status> != 0 {
            return %dialog-result<status>;
        }
        
        # Validation based on type
        given $dialog<validation> {
            when 'name' {
                unless validate-name(%dialog-result<value>) {
                    show-dialog-raw(
                        '--title', 'Invalid Input',
                        '--msgbox',
                        '\nPlease enter a valid name. It should be 1-32 characters long, start with a lowercase letter or underscore, and contain only lowercase letters, numbers, underscores, and hyphens. It cannot have consecutive hyphens or start/end with a hyphen.',
                        10, 60
                    );
                    next;
                }
            }
            when 'number' {
                unless validate-number(%dialog-result<value>) {
                    show-dialog-raw(
                        '--title', 'Invalid Input',
                        '--msgbox',
                        '\nPlease enter a valid positive number.',
                        6, 50
                    );
                    next;
                }
                # Convert to number
                %dialog-result<value> = %dialog-result<value>.Rat;
            }
            when 'integer' {
                unless validate-integer(%dialog-result<value>) {
                    show-dialog-raw(
                        '--title', 'Invalid Input',
                        '--msgbox',
                        '\nPlease enter a valid positive integer number.',
                        6, 50
                    );
                    next;
                }
                # Convert to integer
                %dialog-result<value> = %dialog-result<value>.Int;
            }
        }
        
        given %dialog-result<value> {
            if $dialog<extra-validation> && !EVAL($dialog<extra-validation>) {
                my $formatted-validation = $dialog<extra-validation>.subst('$_', "<"~kebab-to-title($dialog<name>)~">", :g);
                show-dialog-raw(
                    '--title', 'Invalid Input',
                    '--msgbox',
                    "\nYour input does not pass the validation:\n\n$formatted-validation",
                    11, 70
                );
                next;
            }
        }
        last; # Validation passed
    }
    
    Settings.instance.set($dialog<name>, %dialog-result<value>);
    Logging.log("ask-for-setting {$dialog<name>}: result={%dialog-result<status>}");
    return %dialog-result<status>;
}
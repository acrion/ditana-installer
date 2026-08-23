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

#| Put an answered value through the checks the input box would have applied,
#| and stop the run if it fails one.
#|
#| Skipping the dialog must not skip its validation. The rules are part of
#| what the step means -- user-name rejects the names the system already uses,
#| keyboard-delay a value outside 50..2000 -- and an answer file that got one
#| wrong would otherwise produce an installation that fails somewhere later,
#| with nothing pointing back at the line that caused it.
sub validate-answered-setting($dialog) is export {
    my $name = $dialog<name>;
    my $value = Settings.instance.get($name);

    my $complaint = do given $dialog<validation> {
        when 'name' {
            validate-name($value.Str)
                ?? ''
                !! "must be 1-32 characters, start with a lowercase letter or "
                 ~ "underscore, and hold only lowercase letters, digits, "
                 ~ "underscores and hyphens";
        }
        when 'number'  { validate-number($value.Str)  ?? '' !! "must be a positive number" }
        when 'integer' { validate-integer($value.Str) ?? '' !! "must be a positive integer" }
        default { '' }
    }

    die "Autoinstall: $name = '$value' $complaint." if $complaint;

    # The input box stores a number as a number. KDL can express one too, but
    # nothing stops an answer file from quoting it, and the difference would
    # surface much later as a string where arithmetic was expected.
    given $dialog<validation> {
        when 'number'  { Settings.instance.set($name, $value.Rat); $value = $value.Rat }
        when 'integer' { Settings.instance.set($name, $value.Int); $value = $value.Int }
    }

    if $dialog<extra-validation> {
        # The expression is written against $_, the same way the input box
        # evaluates it.
        my $passes = do given $value { EVAL($dialog<extra-validation>) };
        unless $passes {
            die "Autoinstall: $name = '$value' does not satisfy "
              ~ "{$dialog<extra-validation>}.";
        }
    }
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
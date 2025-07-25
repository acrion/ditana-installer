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
use Logging;
use Settings;

sub calculate-indent(Str $text) {
    my $match = $text ~~ /^\w+\.\s/;
    return Nil if !$match || $match.from > 0;
    $match.to;
}

sub kebab-to-title(Str $kebab) is export {
    my %special-cases = (
        'id' => 'ID',
        'ai' => 'AI',
        'he' => 'He',
        'she' => 'She',
        'c' => "C",
        'cpu' => "CPU",
        'lba' => "LBA",
        'nvme' => "NVME",
        'dpi' => "DPI",
        'aur' => "AUR"
    );
    my Set $always-lower = set <with>;
    
    my @words = $kebab.split('-')
        .map(*.tc)
        .join(' ')
        .words;
        
    @words[0] = do given @words[0].lc {
        when %special-cases{$_}:exists { %special-cases{$_} }
        default                       { .tc }
    }
    
    @words[1..*] = @words[1..*].map({
        when .lc ∈ %special-cases.keys { %special-cases{.lc} }
        when $always-lower            { .lc }
        when .chars < 4               { .lc }
        default                      { $_ }
    });
    
    @words.join(' ')
}

sub replace-variables(Str $text) {
    $text.subst(
        rx/ \$ <[a..z]> <[a..z_-]>* /, 
        -> $match {
            my $identifier = $match.Str.substr(1); # Remove the leading $
            my $value = Settings.instance.get($identifier);
            
            if $value.defined && $value ne '' {
                $value
            } else {
                kebab-to-title($identifier)
            }
        },
        :g
    )
}

sub calculate-wrapped-lines(Str $text, Int $width) is export {
    my @lines;
    my $replaced-text = replace-variables($text);
    my @paragraphs = $replaced-text.split(/\n/);
    my $reformatted-text = "";
    my $current-indent = 0;
    
    for @paragraphs -> $paragraph {
        # If empty paragraph, add single empty line
        if $paragraph eq "" {
            @lines.push("");
            $reformatted-text ~= "\n";
            next
        }
        
        my $remaining = $paragraph;
        
        while $remaining {
            if $remaining eq $paragraph {
                if $remaining.starts-with("<reset-indent>") {
                    $current-indent = 0;
                    $remaining .= substr("<reset-indent>".chars)
                } else {
                    my $new-indent = calculate-indent($remaining);
                    if $new-indent {
                        $current-indent = $new-indent
                    } else {
                        $remaining = " " x $current-indent ~ $remaining;
                    }
                }
            } else {
                $remaining = " " x $current-indent ~ $remaining;
            }

            if $reformatted-text.chars && $reformatted-text.contains(/<-[\n]>/) > 0 {
                $reformatted-text~="\n"
            }

            if $remaining.chars <= $width {
                @lines.push($remaining);
                $reformatted-text ~= $remaining;
                last
            }

            my $chunk = $remaining.substr(0, $width+1); # include the character behind the maximum line length to determine the last blank
            my $space-pos = $chunk.rindex(' ');
            my $break-pos = $space-pos ?? $space-pos !! $width;
            
            @lines.push($remaining.substr(0, $break-pos));
            $reformatted-text ~= "{@lines.tail}";
            $remaining = $remaining.substr($break-pos).trim;
        }
    }
    
    # Log each line with its number
    Logging.log("Input text for calculate-wrapped-lines:");
    for @lines.kv -> $i, $line {
        Logging.log("Line {$i + 1}: '{$line}'");
    }
    
    return %( text => $reformatted-text, lines => @lines.elems);
}

sub format-package-list($packages) {
    return "" unless $packages;
    
    my @pkg-array = $packages.split(/\s+/);
    
    return @pkg-array[0] if @pkg-array.elems == 1;
    
    my @formatted = @pkg-array[0 .. *-2];
    return "@formatted.join(', ') and @pkg-array[*-1]";
}

sub show-dialog-raw(*@args) is export {
    my @quoted-args = @args.map: {
        "'" ~ $_.Str.subst("'", "'\\''", :g) ~ "'"
    };
    
    my $cmd = 'dialog ' ~ @quoted-args.join(' ') ~ ' 3>&1 1>&2 2>&3';
    
    Logging.log("Dialog command line: $cmd");
    
    my $proc = Proc::Async.new('sh', '-c', $cmd);
    
    my $output = '';
    $proc.stdout.tap: { $output ~= $_.Str };
    
    my $promise = $proc.start;
    my $status = await $promise;
    
    return { 
        value => $output.Str, 
        status => $status.exitcode 
    }
}

sub show-categories-dialog($dialog) {
    my @menu-items;
    my $counter = 1;
    for @($dialog<categories>) -> $category {
        @menu-items.append: 
            $counter.Str,
            kebab-to-title($category<name>);
        $counter++;
    }

    my $instruction = $dialog<instruction> // "Choose a category:";
    my %wrap-text = calculate-wrapped-lines($instruction, 94);
    
    my $dialog-result = show-dialog-raw(
        '--title', $dialog<name>,
        '--ok-label', 'Enter Selected',
        '--cancel-label', 'Back',
        '--menu',
        %wrap-text<text>,
        min(41, @menu-items.elems/2 + %wrap-text<lines> + 6),
        98,
        8,
        |@menu-items
    );
    
    if $dialog-result<status> == 0 {
        my $selected = $dialog-result<value>.trim;
        return @($dialog<categories>)[$selected.Int - 1]<name>
    } else {
        return ''
    }
}

sub show-and-log-status($message) is export {
    my %wrap-text = calculate-wrapped-lines($message, 46);
    show-dialog-raw '--title', 'Ditana Installer', '--infobox', "\n{%wrap-text<text>}", %wrap-text<lines>+4, 50;
    Logging.log($message);
}

sub process-and-confirm-setting-changes(%setting-of-number, @checked-items, $dialog-name, $is-radiolist) {
    my $settings = Settings.instance;
    my %backup = $settings.clone();

    my %user-changed-settings;
    for %setting-of-number.kv -> $number, $setting {
        %user-changed-settings{$setting.name} = $settings.get($setting.name);
    }

    Logging.log("------- Setting user-initiated changes...");
    for %setting-of-number.kv -> $number, $setting {
        my $checked = $number ∈ @checked-items;
        if $checked ^^ %user-changed-settings{$setting.name} {
            $settings.set($setting.name, $checked);
        }
    }

    Logging.log("------- Re-evaluating unchanged settings for dependency resolution...");
    for %setting-of-number.kv -> $number, $setting {
        my $checked = $number ∈ @checked-items;
        if $checked == %user-changed-settings{$setting.name} {
            $settings.reset($setting.name, $checked);
        }
    }
    
    my @all-changes = $settings.compare(%backup<settings>);

    my @recommended-changes;
    my @required-changes;

    for @all-changes -> %change {
        if %change<dialog-name> ne $dialog-name {
            if !%change<short-description> or !$settings.is-available(%change<name>) {
                @required-changes.push(%change);
            } else {
                @recommended-changes.push(%change);
            }
        }
    }

    # Step A: Find all dialog names that are radiolists and already contain required changes.
    my $dialogs-to-promote = @required-changes
        .map(*<dialog-name>)
        .grep({ $_ && $settings.get-installation-step($_)<type> eq 'radiolist' })
        .Set;

    # Step B: Find all recommended changes that belong to one of these dialogs.
    my @promoted-to-required = @recommended-changes.grep({ %$_.<dialog-name> (elem) $dialogs-to-promote });

    # Step C: If any were found, add them to the required list...
    if @promoted-to-required {
        @required-changes.append(@promoted-to-required);
        # ...and remove them from the recommended list.
        @recommended-changes = @recommended-changes.grep({ %$_.<dialog-name> ∉ $dialogs-to-promote });
    }
    
    if @recommended-changes or @required-changes {
        my $dialog-text = "";
        my @dialog-params;
        my $dialog-title = 'Settings Impact Overview';

        sub format-change(%change) {
            my $dialog-prefix = %change<dialog-name> eq $dialog-name || !%change<dialog-name> ?? "" !! "%change<dialog-name> ";
            my $description = %change<short-description> ?? %change<short-description> !! kebab-to-title(%change<name>);
            return "{$dialog-prefix}«{$description}»: {%change<from>} --> {%change<to>}\n";
        }
        
        if !@recommended-changes and @required-changes {
            $dialog-text = "Your selection requires the following system adjustments for stability. These changes are mandatory and cannot be overridden:\n\n";
            $dialog-text ~= format-change($_) for @required-changes;
            @dialog-params = '--yes-label', 'Confirm', '--no-label', 'Discard Changes', '--yesno';
        }
        elsif @recommended-changes and !@required-changes {
            $dialog-text = "Based on your selection, the following changes are recommended. You can accept them or keep your previous settings:\n\n";
            $dialog-text ~= format-change($_) for @recommended-changes;
            @dialog-params = '--ok-label', 'Accept Recommendations', '--cancel-label', 'Discard All', '--extra-button', '--extra-label', 'Keep Previous Settings', '--yesno';
        }
        else {
            $dialog-text = "Based on your selection, the following changes are recommended:\n\n";
            $dialog-text ~= format-change($_) for @recommended-changes;
            $dialog-text ~= "\nAdditionally, the following system adjustments are REQUIRED for stability and cannot be overridden:\n\n";
            $dialog-text ~= format-change($_) for @required-changes;
            @dialog-params = '--ok-label', 'Accept All', '--cancel-label', 'Discard Changes', '--extra-button', '--extra-label', 'Override Recommendations', '--yesno';
        }

        my %wrap-text = calculate-wrapped-lines($dialog-text.chomp, 94);
        my $confirm-result = show-dialog-raw(
            '--title', $dialog-title,
            |@dialog-params,
            %wrap-text<text>,
            min(41, %wrap-text<lines> + 5),
            98
        );
        
        given $confirm-result<status> {
            # OK-Button: 'Confirm' / 'Accept Recommendations' / 'Accept All'
            when 0 {
                return True;
            }
            # Cancel-Button: 'Discard Changes' / 'Discard All'
            when 1 {
                $settings.restore(%backup);
                return False;
            }
            when 3 {
                my @names-to-revert = @recommended-changes.map(*<name>);
                $settings.revert-specific-settings(%backup, @names-to-revert);
                return True;
            }
            default {
                $settings.restore(%backup);
                return False;
            }
        }
    }

    return True;
}

sub show-help($dialog, @dialog-settings, @dialog-unavailable-settings) {
    my &process-setting = -> $setting {
        Logging.log("arch-packages: {$setting.arch-packages}") if $setting.arch-packages;
        Logging.log("aur-packages: {$setting.aur-packages}") if $setting.aur-packages;
        # Create combined package list
        my @all-packages;
        { @all-packages.append($_) for $setting.arch-packages } if $setting.arch-packages;
        { @all-packages.append($_) for $setting.aur-packages } if $setting.aur-packages;
        
        my $description = $setting.long-description;
        $description ~~ s:g/\$packages/{format-package-list(@all-packages)}/;
        
        $description.chomp
    };

    # Generate detailed help text with numbered long descriptions
    my $detailed-help = '';
    my $item-counter = 1;
    my $total-items = @dialog-settings.elems;
    
    for @dialog-settings -> $setting {
        # Add the numbered item
        $detailed-help ~= "{$item-counter}. {process-setting($setting)}";
        
        # Add appropriate newlines based on position and help-note presence
        if $item-counter < $total-items || $dialog<help-note> {
            $detailed-help ~= "\n\n";
        } else {
            $detailed-help ~= "\n";
        }
        
        $item-counter++;
    }
    
    # Construct final help text with conditional spacing
    my $help-text = $dialog<help-intro> ?? 
                $dialog<help-intro> ~ "\n\n" ~ $detailed-help !!
                $detailed-help;
                
    if $dialog<help-note> {
        $help-text ~= "<reset-indent>" ~ $dialog<help-note>;
    }

    if @dialog-unavailable-settings.elems > 0 {
        if $item-counter == 1 {
            $help-text = "All settings in this dialog are unavailable due to configuration or hardware limitations:";
        } else {
            $help-text = $help-text.chomp ~ "\n\n" ~ "<reset-indent>=== The following settings are unavailable due to configuration or hardware limitations ===";
        }

        $item-counter = 0;

        for @dialog-unavailable-settings -> $setting {
            $help-text ~= "\n\n{('A'..'Z')[$item-counter]}. {process-setting($setting)}\n=== Condition of availability: === "
                        ~ $setting.available.substr(1, *-1); # remove backticks from value of available

            $item-counter++;
        }
    }
    
    my %wrap-text = calculate-wrapped-lines($help-text.chomp,94);
    show-dialog-raw(
        '--title', "Help: " ~ $dialog<name>,
        '--no-collapse',
        '--msgbox', 
        %wrap-text<text>,
        min(41,%wrap-text<lines>+4), 98
    );
}

sub configure-and-show-dialog($dialog) is export {
    if $dialog<type> eq 'categories' {
        return show-categories-dialog($dialog);
    }

    my $settings = Settings.instance;
    my $dialog-result;
    
    repeat {
        Logging.log("Processing dialog: $dialog<name>");
        Logging.log("Type: {$dialog<type>}");

        Logging.log("Suppress License: {$dialog<suppress-license> ?? 'Yes' !! 'No'}");
        
        my @dialog-settings = $settings.get-dialog($dialog<name>);
        Logging.log("Number of settings: {@dialog-settings.elems}");
        
        my $max-desc-length = @dialog-settings.map(*.short-description.chars).max;
        
        my @menu-items;
        my %setting-of-number;
        my $counter = 1;
        for @dialog-settings -> $setting {
            Logging.log("Processing setting: {$setting.name}");
            
            %setting-of-number{$counter} = $setting;
            my $description = $setting.short-description;
            my $license = $dialog<suppress-license> ?? '' 
                        !! $setting.license-category ~ " " ~ $setting.spdx-identifiers;
            
            my $combined = $description.fmt("%-{$max-desc-length}s") ~ 
                        ($license ?? ' ' ~ $license !! '');
            my $status = $setting.current-value ?? 'on' !! 'off';
            
            @menu-items.append: $counter.Str, $combined, $status;
            $counter++;
        }

        my @dialog-unavailable-settings = $settings.get-unavailable-dialog-settings($dialog<name>);

        if $counter == 1 {
            show-help($dialog, @dialog-settings, @dialog-unavailable-settings);
            return 0;
        }

        my $instruction = $dialog<instruction>.chomp // 'Select options:';

        if @dialog-unavailable-settings.elems > 0 {
            $instruction ~= "\n(Note: {@dialog-unavailable-settings.elems} additional setting{@dialog-unavailable-settings.elems > 1 ?? "s are" !! " is"} unavailable, please select «Help» for details)";
        }

        my %wrap-text = calculate-wrapped-lines($instruction,94);

        my $dialog-type = "--" ~ $dialog<type>;
        $dialog-result = show-dialog-raw(
            '--help-button',
            '--ok-label', 'Confirm',
            '--cancel-label', 'Back',
            '--extra-button',
            '--extra-label', 'Reset to Defaults',
            '--title', $dialog<name>,
            $dialog-type,
            %wrap-text<text>,
            min(41,@menu-items.elems/3+%wrap-text<lines>+6), # height
            98,  # width
            1,  # unused
            |@menu-items
        );

        Logging.log("Dialog exit code: $dialog-result<status>");
        
        given $dialog-result<status> {
            when 0 {  # OK button
                my @checked-items = $dialog-result<value>.trim.split(' ');
                Logging.log("------- Checked items: {@checked-items}");
    
                unless process-and-confirm-setting-changes(%setting-of-number, @checked-items, $dialog<name>, $dialog<type> eq "radiolist") {
                    $dialog-result<status> = 2; # Display the same settings dialog again, see below condition
                }
            }
            when 2 { # Help button
                show-help($dialog, @dialog-settings, @dialog-unavailable-settings);
            }
            when 3 {  # Reset to Defaults
                for @dialog-settings -> $setting {
                    $settings.set-to-default($setting.name);
                }
            }
            default {
            }
        }
    } until $dialog-result<status> ∉ (2, 3);

    return $dialog-result<status>;
}

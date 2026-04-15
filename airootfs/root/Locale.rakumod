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
use Settings;
use Logging;
use RunAndLog;


sub get-main-locale-description(Str $code --> Str) {
    my $locale-dir = '/usr/share/i18n/locales/';
    
    my $file-path = try {
        dir($locale-dir)
            .grep(*.f)
            .grep(*.basename.starts-with("$code" ~ '_'))
            .sort
            .first
            .absolute;
    };

    without $file-path {
        return '-';
    }

    my $title = try {
        my $line = $file-path.IO.lines.grep(/^ \s* 'title' \s+ '"'/).first;
        with $line {
            if $line ~~ /'title' \s+ '"' (\w+)/ {
                $0.Str
            } else {
                '-'
            }
        } else {
            '-'
        }
    };

    return $title // '-';
}
sub get-sub-locale-description($full-locale, $main-description) {
    my $file-path = "/usr/share/i18n/locales/$full-locale";
    
    if $file-path.IO.e {
        my $description = qqx{grep -E 'language\\s+"' "$file-path" | head -n 1 | grep -oP 'language\\s+"\\K[^"]+'}.chomp;
        
        if !$description || $description eq $main-description {
            $description = qqx{grep -E 'title\\s+"' "$file-path" | head -n 1 | grep -oP 'title\\s+"\\K[^"]+'}.chomp;
        }
        return $description || "-";
    }
    
    return "-";
}

sub show-locale-help() {
    my $help-text = q:to/END/;

The Locale you select here determines which spell checker will be installed on your system,
ensuring you have language-specific writing assistance tools available.

The «Locale» setting also influences various regional settings on your system. For example:

1. Date and Time Formats:
   Different regions use different date formats. For example, the US typically uses
   MM/DD/YYYY, while many European countries use DD/MM/YYYY.

2. Currency Symbols and Formats:
   The way currency is displayed can vary between regions.

3. Measurement Units:
   Your Locale determines whether the system uses metric or imperial units by default.

4. Paper Size:
   The default paper size can change based on your Locale. For example, A4 is common
   in most of the world, while Letter size is standard in the US and Canada.

If you’d like to later choose whether system messages, folder names, or your Desktop
Environment’s language (if you install one) should be displayed in your selected language or
in English, you’ll find this option under «Advanced Settings» → «Development Tools and
Libraries.»
END

    my @args = '--title', 'Help: Primary Locale Selection',
               '--no-collapse',
               '--msgbox', $help-text,
               28, 98;
               
    show-dialog-raw(|@args);
}

sub choose-main-locale() returns Int is export {
    state $temp-file = qx{mktemp}.chomp;
    
    my $output = '/etc/locale.gen'.IO.lines
        .grep(/'.UTF-8 UTF-8'/)
        .map(-> $line { # transform each line
            $line.match(/\#? \s* (\S+) '.UTF-8 UTF-8'/) # Regex with capture
            ?? $0.Str   # if match, take first capture
            !! Nil      # otherwise Nil
        })
        .grep(*.defined)      # filter out Nil values
        .map(*.split('_')[0]) # take first part before '_'
        .unique
        .sort
        .join("\n");

    $temp-file.IO.spurt($output);

    my @menu-options;
    my %menu-descriptions;
    
    for $temp-file.IO.lines -> $code {
        my $description = get-main-locale-description($code);
        @menu-options.append($code, $description);
        %menu-descriptions{$code} = $description;
    }
    
    loop {
        my @dialog-args = '--help-button',
                         '--title', 'Primary Locale Selection',
                         '--menu', '\nChoose the Locale that best represents your region and language preferences. You’ll have the opportunity to fine-tune system locale behavior in a later step.',
                         25, 72, 10,
                         |@menu-options;
                         
        my %result = show-dialog-raw(|@dialog-args);
        
        given %result<status> {
            when 0 {
                my $main-locale = %result<value>;
                Settings.instance.set('main-locale', $main-locale);
                Settings.instance.set('main-locale-description', %menu-descriptions{$main-locale});
                
                return %result<status>;
            }
            when 2 {
                show-locale-help();
            }
            default {
                return %result<status>;
            }
        }
    }
}

sub choose-sub-locale() returns Int is export {
    state $temp-file = qx{mktemp}.chomp;
    my $main-locale = Settings.instance.get('main-locale');
    
    qqx{grep -E "^#?$main-locale" /etc/locale.gen | grep "\\.UTF-8 UTF-8" | sed 's/#\\? *\\(\\S\\+\\)\\.UTF-8 UTF-8/\\1/' | sed "s/$main-locale\\_//" | sort -u > $temp-file};
    
    my $main-description = get-main-locale-description($main-locale);
    my @menu-options;
    
    for $temp-file.IO.lines -> $code is copy {
        $code = $code.trim;
        my $description = get-sub-locale-description("{$main-locale}_$code", $main-description);
        @menu-options.append($code, $description);
    }
    
    my @dialog-args = '--title', "Secondary Locale Selection for $main-description",
                     '--menu', '\nSelect your sub-locale:',
                     21, 70, 10,
                     |@menu-options;
                     
    my %result = show-dialog-raw(|@dialog-args);
    
    if %result<status> == 0 {
        my $sub-locale = %result<value>;
        my $locale = "{$main-locale}_{$sub-locale}";
        Settings.instance.set('locale', $locale);
        Logging.log("Full locale selected: $locale");
        return 0;
    }
    
    return 1;
}

sub apply-locale() is export {
    my $locale = Settings.instance.get("locale");
    my $use-c-utf8 = Settings.instance.get("standardized-locale") ?? "y" !! "n";

    run-and-log 's6', 
        '--task-run', 
        "%*ENV<HOME>/sparrow/tasks/locale\@locale=$locale,use_c_utf8=$use-c-utf8";

    "%*ENV<HOME>/mnt/etc/xdg/ditana".IO.mkdir;
    "%*ENV<HOME>/mnt/etc/xdg/ditana/default_locale_description".IO.spurt(Settings.instance.get('main-locale-description'));
}

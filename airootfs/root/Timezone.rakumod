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
use JSON::Fast;

my $region-or-timezone;
my @zones;
my $detected-timezone     = '';
my $detected-country-code = '';
my $detected-language     = '';

sub detect-defaults() is export {
    return if $detected-timezone;   # idempotent — no repeated HTTP calls

    my $proc = run
        « curl --silent --max-time 3 --fail https://ipapi.co/json/ »,
        :out, :err;
    my $output = $proc.out.slurp(:close);
    $proc.err.slurp(:close);
    return unless $proc.exitcode == 0;

    my %data;
    try { %data = from-json($output); }
    return if $!;

    my $tz = %data<timezone> // '';
    $detected-timezone = $tz if $tz ~~ / ^ \w+ '/' \S+ $ /;

    my $cc = %data<country_code> // '';
    $detected-country-code = $cc if $cc ~~ / ^ <[A..Z]> ** 2 $ /;

    # "languages" is ordered by prevalence, e.g. "de-CH,fr-CH,it-CH,rm"
    my $langs = %data<languages> // '';
    $detected-language = $0.Str if $langs ~~ / ^ (<[a..z]>+) /;
}

sub detected-timezone()     is export { $detected-timezone     }
sub detected-country-code() is export { $detected-country-code }
sub detected-language()     is export { $detected-language     }

sub choose-region-or-timezone() returns Int is export {
    my @other;

    my @patterns = <Etc CET CST EET EST GMT HST MET MST NZ PRC PST ROC ROK UCT UTC Universal W-SU WET>;

    my @timezones = qx{timedatectl list-timezones}.lines;

    for @patterns -> $pattern {
        @other.append: @timezones.grep(/$pattern/);
    }

    @other = @other.map({ 
        my @parts = .split('/');
        @parts > 1 ?? "{@parts[*-1]}:{$_}" !! "$_:$_"
    }).unique.map(*.split(':')[1]);

    my @regions = @timezones.grep({ 
        my $timezone = $_;
        !@other.grep({ $timezone eq $_ });
    }).map(*.split('/')[0]).unique;

    @regions.push: "Other";

    my @menu-options;
    for @regions.kv -> $idx, $region {
        @menu-options.append: ($idx + 1).Str, $region;
    }

    my $preferred = Settings.instance.get('timezone');

    if !$preferred {
      detect-defaults();
      $preferred = detected-timezone();
    }

    # Pre-select the detected region, if any
    my @default-args;
    if $preferred {
        my $region = $preferred.split('/')[0];
        my $idx = @regions.first(* eq $region, :k);
        @default-args = '--default-item', ($idx + 1).Str if $idx.defined;
    }

    my @dialog-args = '--title', 'Time Zone Region Selection',
                      |@default-args,
                      '--menu', 'Select Time Zone or Region:',
                      21, 70, 18, |@menu-options;
    
    my $result = show-dialog-raw(|@dialog-args);
    
    if $result<status> == 0 {
        $region-or-timezone = @regions[$result<value>.Int - 1];
        
        if $region-or-timezone eq "Other" {
            @zones = @other;
        } else {
            @zones = @timezones.grep(/^$region-or-timezone\//).Array;
        }
        
        return 0;
    }
    
    return 1;
}


sub choose-specific-timezone($silent-exit-code) returns Int is export {
    my $exit-code;
    my $selected-timezone;

    if @zones {
        my @menu-options;
        for @zones.kv -> $idx, $zone {
            @menu-options.append: ($idx + 1).Str, $zone;
        }

        # Pre-select the detected timezone, if it's in the current region
        my $preferred = Settings.instance.get('timezone') || detected-timezone();

        my @default-args;
        if $preferred {
            my $idx = @zones.first(* eq $preferred, :k);
            @default-args = '--default-item', ($idx + 1).Str if $idx.defined;
        }

        my @dialog-args = '--title', "Specific Time Zone Selection for $region-or-timezone",
                          |@default-args,
                          '--menu', 'Select Specific Time Zone:',
                          20, 70, 18, |@menu-options;
        
        my $result = show-dialog-raw(|@dialog-args);
        
        if $result<status> != 0 {
            return 1;
        }
        
        $selected-timezone = @zones[$result<value>.Int - 1];
        $exit-code = 0;
    } else {
        $selected-timezone = $region-or-timezone;
        $exit-code = $silent-exit-code;
    }
    
    Settings.instance.set('timezone', $selected-timezone);
    
    return $exit-code;
}

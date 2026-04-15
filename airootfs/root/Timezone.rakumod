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

my $region-or-timezone;
my @zones;

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
    
    # Menu-Optionen erstellen
    my @menu-options;
    for @regions.kv -> $idx, $region {
        @menu-options.append: ($idx + 1).Str, $region;
    }
    
    my @dialog-args = '--title', 'Time Zone Region Selection',
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
        
        my @dialog-args = '--title', "Specific Time Zone Selection for $region-or-timezone",
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

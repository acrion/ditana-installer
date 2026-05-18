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
use JSON::Fast;
use RunAndLog;
use Settings;
use Logging;

sub get-boot-device() {
    my $cmdline = "/proc/cmdline".IO.slurp;
    my $boot-uuid = $cmdline ~~ rx:i/uuid\=( <[ \d a..f - ]>+)/ ?? $/[0].Str !! "";
    if $boot-uuid {
        return query-blockdevices("--nodeps -o NAME,UUID").grep({ .<uuid>.defined && .<uuid> eq $boot-uuid }).map(*<name>)[0] // "";
    }

    return ""
}

sub get-efi-partition(--> Str) {
    # Check if the EFI system partition directory exists
    unless Settings.instance.get('uefi') {
        Logging.log('get-efi-partition: directory /sys/firmware/efi does not exist.');
        return '';
    }
    Logging.log('get-efi-partition: directory /sys/firmware/efi does exist.');

    # Create Maps for PARTUUIDs and matched devices
    my %partuuid-map;
    my SetHash $matched-devices .= new;

    # Parse blkid output
    my $blkid-output = qx{sudo blkid};
    for $blkid-output.lines -> $line {
        if $line ~~ /PARTUUID\=\"(<[0..9a..f\-]>+)\"/ {
            my $partuuid = $0.Str;
            my $device = $line.split(':')[0];
            %partuuid-map{$partuuid} = $device;
        }
    }

    # Parse efibootmgr output and find matches
    my $efi-output = qx{efibootmgr};
    for $efi-output.lines -> $line {
        for %partuuid-map.keys -> $partuuid {
            if $line ~~ / <-[0..9a..f]> $partuuid <-[0..9a..f]> / {
                $matched-devices.set(%partuuid-map{$partuuid});
            }
        }
    }

    Logging.log("blkid
$blkid-output
Parsed blkid output:
{%partuuid-map.gist}
efibootmgr
$efi-output
Matched devices:
{$matched-devices.gist}");

    # Check if exactly one match was found
    my @unique-devices = $matched-devices.keys;
    if @unique-devices == 1 {
        Logging.log("Found EFI device: {@unique-devices[0]}");
        return @unique-devices[0];
    }
    
    Logging.log("get-efi-partition: expected exactly one match, found {@unique-devices.elems}");
    return '';
}

sub select-disk() returns Int is export {
    my $current-bootloader-partition = get-efi-partition();
    my $boot-device = get-boot-device();
    Settings.instance.set("current-bootloader-partition", $current-bootloader-partition);
    Settings.instance.set("boot-device", $boot-device);
    
    # Parse device list from lsblk
    my $device-list = do {
        gather for query-blockdevices('-o NAME,VENDOR,MODEL,SIZE,FSTYPE').List -> $dev {
            next if $dev<name> ~~ rx/^ [zram|rom|loop|airootfs|sr|fd]/;
            next if $dev<name> eq $boot-device;
            
            my $desc = (($dev<vendor> // "") ~ ($dev<model> // "")) ~ " " ~ $dev<size> ~ ": ";
            $desc ~= do if $dev<children> {
                $dev<children>.map({ .<fstype> // "unformatted" }).join(", ")
            } else {
                $dev<fstype> // ""
            }
            
            take $dev<name> => $desc.words.join(' '); # remove duplicate whitespaces
        }
    }

    Logging.log("Device list: " ~ $device-list.gist);

    my @menu-options = $device-list.map({ .key, .value }).flat;
    my %device-descriptions = $device-list;

    my $dialog-text = "\nPlease select a disk for installation. This will determine where Ditana will be installed. All data on the selected disk will be erased. Please note that device names (first column) are not unique and may differ for each boot process. The second column shows the model name of the device, its capacity and the current list of partitions.";

    my $result = show-dialog-raw(
        '--title', 'Installation Disk',
        '--menu', $dialog-text,
        15, 98, 8, |@menu-options
    );
    
    if $result<status> == 0 {
        Settings.instance.set('install-disk', $result<value>);
        Settings.instance.set('install-disk-description', %device-descriptions{$result<value>});
    }
    
    $result<status>
}

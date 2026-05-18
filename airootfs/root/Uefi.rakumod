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
use AskForYesNo;
use Dialogs;
use JSON::Fast;
use RunAndLog;
use Settings;
use Logging;

sub handle-current-efi-partition($common-dialog-text) {
    my $install-disk = Settings.instance.get("install-disk");
    my $current-bootloader-partition = Settings.instance.get("current-bootloader-partition");
    my $device-that-contains-bootloader-partition = query-blockdevices("-o PKNAME $current-bootloader-partition")[0]<pkname>;
    Logging.log("device-that-contains-bootloader-partition: $device-that-contains-bootloader-partition");
    Logging.log("                             install-disk: $install-disk");

    if $device-that-contains-bootloader-partition eq $install-disk {
        my $instruction = "The selected installation disk contains the current EFI partition $current-bootloader-partition. Overwriting it will make all operating systems on your system unbootable, including those on other disks. Are you sure to continue?";
        my $dialog-result = ask-for-yes-no(:$instruction, default => True);

        if $dialog-result == 0 {
            Settings.instance.set('bootloader-partition', 'new');
            return 0;
        } else {
            Settings.instance.set('bootloader-partition', '');
            return $dialog-result;
        }
    } else {
        my $exit-status = ask-for-yes-no(
            title => 'EFI partition for Ditana',
            yes-label => 'new',
            no-label => $current-bootloader-partition,
            default => Settings.instance.get('bootloader-partition') eq 'new',
            instruction => "Detected EFI partition on another disk ($device-that-contains-bootloader-partition).\n\n$common-dialog-text $current-bootloader-partition.");

        given $exit-status {
            when 0 { Settings.instance.set('bootloader-partition', 'new') }
            when 1 { 
                Settings.instance.set('bootloader-partition', $current-bootloader-partition);
                Settings.instance.set('enable-os-prober', True);
                $exit-status = 0;  # user clicked the no-label, which we do not treat like "cancel" as in other dialog types, but as a valid result
            }
            default { Settings.instance.set('bootloader-partition', '') } # user pressed Escape
        }

        return $exit-status;
    }
}

sub scan-and-select-efi-partition($common-dialog-text, $silent-exit-code) {
    my $install-disk = Settings.instance.get("install-disk");
    my $boot-device = Settings.instance.get("boot-device");
    my $temp-mount = "/tmp/efi_check";
    
    mkdir $temp-mount;
    LEAVE rmdir $temp-mount;
    
    my @efi-partitions;
    my $efi-partition-on-install-disk = "";
    
    Logging.log("Checking vfat partitions for directory /EFI...");
    
    for qqx{blkid -o device -t TYPE=vfat}.lines -> $dev {
        next if $dev ~~ /^ '/dev/loop' /;
        
        my $parent-device = query-blockdevices("-o PKNAME $dev")[0]<pkname>;
        
        if $parent-device ne $install-disk {
            if $parent-device ne $boot-device {
                run 'sudo', 'mount', $dev, $temp-mount, :err;
                if "$temp-mount/EFI".IO.e {
                    @efi-partitions.push: $dev;
                }
                run 'sudo', 'umount', $temp-mount, :err;
            }
        } else {
            $efi-partition-on-install-disk = $dev;
        }
    }
    
    Logging.log("Found {@efi-partitions.elems} vfat partitions with directory /EFI. efi-partition-on-install-disk: '$efi-partition-on-install-disk'");
    
    if @efi-partitions.elems == 0 {
        Logging.log("Detected no vfat partitions with directory /EFI");
        my $overwrite-efi = True;
        
        if $efi-partition-on-install-disk {
            Logging.log("Displaying dialog The selected installation disk contains an EFI partition...");
            my $result = ask-for-yes-no(
                instruction => "The selected installation disk contains an EFI partition ($efi-partition-on-install-disk),\n" ~
                "which may be used by operating systems on other disks. Are you sure to overwrite it?",
                default => True
            );
            $overwrite-efi = ($result == 0);
            Logging.log("After displaying dialog: overwrite-efi=$overwrite-efi");
        }
        
        if $overwrite-efi {
            Settings.instance.set('bootloader-partition', 'new');
            return $efi-partition-on-install-disk ?? 0 !! $silent-exit-code;
        } else {
            Settings.instance.set('bootloader-partition', '');
            return 1;
        }
    }
    
    my @menu-options;
    for @efi-partitions -> $dev {
        my $parent-device = query-blockdevices("-o PKNAME $dev")[0]<pkname>;
        my $disk-size = query-blockdevices("-d -o SIZE /dev/$parent-device")[0]<size>;
        my $desc = "Disk size: $disk-size";
        @menu-options.append($dev, $desc);
    }
    
    my $disk-size = query-blockdevices("-d -o SIZE /dev/$install-disk")[0]<size>;
    @menu-options.append('new', "New partition on $install-disk, disk size $disk-size");
    
    my $dialog-text = "Detected EFI partitions on other discs.\n\n$common-dialog-text the EFI partition on your internal drive that is the default boot device in your UEFI configuration.";
    
    if $efi-partition-on-install-disk {
        $dialog-text ~= "\n\nIn the previous step, you selected $install-disk as the installation disk. " ~
            "Regardless of what you select below, the existing EFI partition ($efi-partition-on-install-disk) " ~
            "on this disk will be overwritten. This may affect not only this disk but also the bootability " ~
            "of operating systems on other disks that currently use $efi-partition-on-install-disk as an EFI partition.";
    }

    Logging.log("Display dialog 'Select EFI Partition'");
    
    my %bootloader-partition = show-dialog-raw(
        '--title', "Select EFI Partition",
        '--menu', $dialog-text,
        26, 90, 4,
        |@menu-options
    );
    
    Logging.log("After display dialog 'Select EFI Partition'");
    
    if %bootloader-partition<status> == 0 {
        Settings.instance.set('bootloader-partition', %bootloader-partition<value>);
    } else {
        Settings.instance.set('bootloader-partition', '');
    }
    
    return %bootloader-partition<status>;
}

sub check_efi($silent-exit-code) returns Int is export {
    unless Settings.instance.get("uefi")
    {
        show-dialog-raw('--msgbox',
            "UEFI not detected. If you need to boot another OS from a different disk, you will need to use the BIOS Setup (instead of the UEFI or GRUB boot menu) to change the boot device. Typically, BIOS versions offer a special boot menu via keys like F8, F11, or F12.",
            10, 50
        );
        Settings.instance.set("bootloader-partition", "");
        return $silent-exit-code;
    }

    my $install-disk = Settings.instance.get("install-disk");
    my $common-dialog-text="If you are installing Ditana on a removable drive and want to keep it independent, or if you are installing on an internal drive and want to keep each disc independent, select «new» to create a separate EFI partition on $install-disk. To switch between operating systems you need to change the boot device via the UEFI interface at boot time (usually with keys like F8..F12).\n\nAlternatively, if you want a boot menu to appear automatically each time you boot, making it easier to choose an operating system, select";

    return Settings.instance.get("current-bootloader-partition")
        ?? handle-current-efi-partition($common-dialog-text)
        !! scan-and-select-efi-partition($common-dialog-text, $silent-exit-code);
}

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

sub select-swap-size() is export {
    my $s = Settings.instance;
    my $install-disk = Settings.instance.get("install-disk");
    my $total-ram-gib = Settings.instance.get("total-ram-gib");
    
    Logging.log("Calculating recommended swap size based on available system RAM and disk size.");
    
    my $size-of-install-disk-str = query-blockdevices("-d -o SIZE /dev/$install-disk")[0]<size>;
    my $size-of-install-disk-gib = query-blockdevices("-d -o SIZE -b /dev/$install-disk")[0]<size> /1024/1024/1024;
    Logging.log("Size of install disk $install-disk: $size-of-install-disk-gib GiB");
    my $recommended-swap-size-gib = (32 - $total-ram-gib).floor;
    my $max-swap-size-gib = ($size-of-install-disk-gib / 5).floor;
    my $typical-required-gib-during-installation = 45;
    my $max-swap-size-gib-b = ($size-of-install-disk-gib - $typical-required-gib-during-installation).floor;
    
    if $recommended-swap-size-gib < 0 {
        $recommended-swap-size-gib = 0;
        Logging.log("Swap recommendation: No swap partition suggested, as the system has 32 GB or more RAM.");
    } else {
        
        if $recommended-swap-size-gib > $max-swap-size-gib {
            $recommended-swap-size-gib = $max-swap-size-gib;
            Logging.log("Swap recommendation: Aiming for 32 GiB of total memory requires more than 20% of the installation disk capacity.");
        }

        if $recommended-swap-size-gib > $max-swap-size-gib-b {
            $recommended-swap-size-gib = $max-swap-size-gib-b;
            Logging.log("Swap recommendation: Aiming for 32 GiB of total memory reduces the available disk space below $typical-required-gib-during-installation.");
        }
    }
    
    Logging.log("Recommended swap size: $recommended-swap-size-gib GiB.");
    
    loop {
        Logging.log("Displaying swap size selection dialog.");
        my %result = show-dialog-raw(
            '--help-button',
            '--no-collapse',
            '--extra-button',
            '--extra-label', 'Reset to Default',
            '--inputbox',
            "Please enter the desired size of the swap partition in GiB to be created on $install-disk.

Enter 0 if no swap partition is required. The system has $total-ram-gib GiB of RAM, and the installation disk size for $install-disk is $size-of-install-disk-str.

If you are unsure, use the default value. Note that the default does not consider the specifics detailed on the help page.",
            13, 98,
            $s.get("swap-partition") ?? $s.get("swap-partition") !! $recommended-swap-size-gib
        );
        
        given %result<status> {
            when 0 {  # OK button pressed
                if %result<value>.Int.defined && %result<value>.Int == %result<value>.trim && %result<value> >= 0 && %result<value> <= $max-swap-size-gib {
                    $s.set("swap-partition", %result<value>.trim);
                    return 0;
                } else {
                    show-dialog-raw(
                        '--msgbox',
                        "Invalid input. Please enter a non-negative integer for the swap partition size in GiB, with a maximum of $max-swap-size-gib GiB.",
                        10, 70
                    );
                }
            }
            when 2 {  # Help button pressed
                show-dialog-raw(
                    '--title', "Guidance on Selecting Swap Size",
                    '--no-collapse',
                    '--msgbox',
                    "
Swap space acts as an extension of your system’s physical RAM, allowing it to handle more data than the physical memory permits. The optimal swap partition size depends on your specific use case and the resource demands of the applications you intend to run. If these demands exceed your physical RAM, a swap partition can help prevent system instability or crashes.

Ditana enables ZRAM by default to optimize memory usage (see «Advanced Settings» → «Storage & File System Options»). ZRAM creates a compressed swap space in RAM, enhancing system responsiveness under memory pressure and reducing wear on storage devices by minimizing writes to physical swap partitions on SSDs or HDDs. With ZRAM enabled, the system can handle occasional high memory demands efficiently without relying heavily on a physical swap partition.

If you configure both a swap partition and ZRAM, the system will use ZRAM first before accessing the swap partition. This approach combines the benefits of having additional swap space while reducing wear on your storage devices.

Kernel parameters such as the swappiness (swap file usage) are automatically adjusted based on your configuration (see «Expert Settings» → «General Kernel Configuration»).

For users with a typical workload, we recommend the default setting.",
                    33, 64
                );
            }
            when 3 {  # Reset to Defaults
                $s.set("swap-partition","");
            }
            default {
                return %result<status>;
            }
        }
    }
}

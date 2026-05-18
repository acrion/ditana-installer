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
use JSON::Fast;
use Settings;
use Logging;
use RunAndLog;

sub nvme-format-should-be-changed($install-disk) {
    CATCH {
        Logging.log("nvme-format-should-be-changed: $_");
        return -1
    }

    return -1 unless $install-disk ~~ /^'nvme'/;

    my $optimal-index = -1;
    my $optimal-rp = 255;
    my $output = from-json(run-and-log('sudo', 'nvme', 'id-ns', '-o', 'json', "/dev/$install-disk"));
    my $current-format = $output<flbas>;

    Logging.log("Current LBA format index on $install-disk: '$current-format'");

    my $lbafs-length = $output<lbafs>.elems;
    for ^$lbafs-length -> $i {
        my $lbaf-rp = $output<lbafs>[$i]<rp>;
        if $lbaf-rp < $optimal-rp {
            $optimal-rp = $lbaf-rp;
            $optimal-index = $i;
        }
    }

    Logging.log("Optimal LBA format index on $install-disk: '$optimal-index'");

    return $current-format == $optimal-index ?? -1 !! $optimal-index;
}


sub format-nvme-output(Str $install-disk) {
    my $proc = run 'sudo', 'nvme', 'id-ns', '-H', "/dev/$install-disk", :out, :err;
    
    return "" if $proc.exitcode != 0;
    
    $proc.out.lines
        .grep(/['Relative Performance']/)
        .map(-> $line {
            $line
                .subst(/^'LBA Format' \s*/, '')  # Remove 'LBA Format' prefix
                .subst(/\s+/, ' ', :g)           # Normalize whitespace
                .trim                            # Remove leading/trailing whitespace
        }).join("\n");
}

sub confirm-nvme-format($silent-exit-code) returns Int is export {
    my $install-disk = Settings.instance.get("install-disk");
    my $optimal-lba-format-index = nvme-format-should-be-changed($install-disk);
    Settings.instance.set("optimal-lba-format-index", $optimal-lba-format-index);

    my %setting = name => "change-nvme-lba-format";
    
    if $optimal-lba-format-index == -1 {
        Settings.instance.set(%setting<name>, False);
        return $silent-exit-code;
    }

    my $current-value = Settings.instance.get(%setting<name>);

    state SetHash $detected-devices .= new;

    unless $detected-devices{$install-disk} {
        Settings.instance.set(%setting<name>, True);
        $detected-devices.set($install-disk)
    }

    my $nvme-output = format-nvme-output($install-disk);

    %setting<instruction> = "The SSD $install-disk is currently using a suboptimal Logical Block Addressing format,
which leads to decreased performance. Would you like to fix this before installing Ditana on
this disk?

Current LBA state of $install-disk:

$nvme-output";

    return ask-for-yes-no(%setting);
}

sub format-nvme() is export {
    if Settings.instance.get("change-nvme-lba-format") {
        my $install-disk = Settings.instance.get("install-disk");
        my $optimal-lba-format-index = Settings.instance.get("optimal-lba-format-index");
        qqx{nvme format --lbaf="$optimal-lba-format-index" "/dev/$install-disk"};
    }
}

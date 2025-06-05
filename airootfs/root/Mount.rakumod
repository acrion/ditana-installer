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
use RunAndLog;
use Settings;

my @active-mounts;

sub create-bind-mount(Str $source, Str $target) is export {
    
    if $source.IO.d {
        mkdir $target unless $target.IO.d;
    } else {
        my $target-dir = $target.IO.dirname;
        mkdir $target-dir unless $target-dir.IO.d;
        $target.IO.spurt;
    }
    
    run-and-echo("mount", "--bind", $source, $target);
    @active-mounts.push: $target;
    Logging.echo("Created bind mount from '$source' to '$target'");
}

sub create-mount(Str $source, Str $target) is export {
    run-and-echo("mount", "--mkdir", $source, $target);
    @active-mounts.push: $target;
    Logging.echo("Mounted '$source' at '$target'");
}

sub cleanup-mounts() is export {
    for @active-mounts.reverse -> $mount {
        run-and-echo("umount", $mount);
        Logging.echo("Unmounted '$mount'");
    }
    @active-mounts = ();
}

sub mount-bootimage-partition() is export {
    my $bootimage-partition = Settings.instance.get('bootimage-partition');
    Logging.echo("Mounting the boot partition $bootimage-partition");
    create-mount("$bootimage-partition", "/mnt/boot")
}

sub mount-bootloader-partition() is export {
    my $bootloader-partition = Settings.instance.get('bootloader-partition');

    if Settings.instance.get("uefi") {
        Logging.echo("Mounting the EFI partition $bootloader-partition");
        create-mount("$bootloader-partition", "/mnt/boot/efi");

        # Sets permissions to 700 (owner access only) for the EFI directory.
        # This addresses the security warning from bootctl (systemd-boot tool)
        # which appears when /boot/efi is world-readable. bootctl uses this
        # directory for the random-seed file containing cryptographic material
        # that must be protected from unauthorized access.
         '/mnt/boot/efi'.IO.chmod(0o700);
    } elsif Settings.instance.get("zfs-filesystem") {
        Logging.echo("Mounting the Syslinux bootloader partition $bootloader-partition");
        create-mount("$bootloader-partition", "/mnt/boot/syslinux")
    }
}

sub enable-swap-partition() is export {
    my $swap-partition = Settings.instance.get('swap-partition');
    if $swap-partition && $swap-partition != 0 {
        Logging.echo("Enabling swap partition $swap-partition");
        run-and-echo("swapon", "$swap-partition")
    }
}

sub create-recursive-bind-mounts(IO::Path $source, IO::Path $base-path = $source) {
    for $source.dir() -> $path {
        my $relative-path = $path.relative($base-path);
        my $target-path = "/mnt".IO.add($relative-path);
        
        if $path.d {
            create-recursive-bind-mounts($path, $base-path);
        } else {
            create-bind-mount($path.Str, $target-path.Str);
        }
    }
}

sub configure-bind-mounts() is export {
    # Temporarily bind-mount the live environment’s /etc/resolv.conf into the target file system.
    # This ensures that during the package installation process, any scripts that perform network
    # operations (e.g., downloads) can resolve hostnames using the live environment’s DNS settings.
    # The installed system uses systemd-resolved and does not contain this file. For details, see
    # https://github.com/acrion/ditana-filesystem?tab=readme-ov-file#dns-configuration
    create-bind-mount("/etc/resolv.conf", "/mnt/etc/resolv.conf");

    # Bind-mount the Raku module ecosystem to make Sparrow6 available in the chroot environment.
    # Sparrow6 is required for declarative configuration management, particularly for safely
    # modifying system configuration files such as GRUB and mkinitcpio.
    # The modules were pre-installed into /root/.raku during ISO creation via build.sh.
    # This approach avoids system-wide installation via zef, which would conflict with the
    # package manager’s file tracking and could lead to inconsistencies during system updates.
    # This follows the same principle as pip on Arch Linux, which refuses system-wide installations
    # and instead recommends using distribution packages (e.g., 'pacman -S python-xyz').
    create-bind-mount("/root/.raku", "/mnt/root/.raku");

    # Bind-mount everything in directory `bind-mount`.
    create-recursive-bind-mounts("%*ENV<HOME>/bind-mount".IO);
}
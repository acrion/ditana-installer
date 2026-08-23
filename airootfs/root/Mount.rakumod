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
use Logging;
use RunAndLog;
use Settings;

my @active-mounts;

#| Symlinks that were in the way of a bind mount, and what they pointed at.
my @displaced-symlinks;

#| Make $target somewhere a bind mount can be attached, and return what it was
#| pointing at if it was a symlink -- the empty string otherwise.
#|
#| A symlink here is not an empty spot to put a file in. Everything that
#| touches the path follows it: writing the placeholder writes through it, and
#| `mount --bind` attaches to whatever it resolves to. The target's symlinks
#| are absolute and resolved against the *running* system, not against /mnt,
#| so both end up at a file the live environment is using.
#|
#| That is not hypothetical. /mnt/etc/resolv.conf is a symlink to
#| /run/systemd/resolve/stub-resolv.conf, which ditana-filesystem ships so the
#| installed system resolves through systemd-resolved. Creating the
#| placeholder emptied the live environment's own resolv.conf, and the bind
#| mount then attached that file to itself -- leaving the chroot with a
#| dangling symlink and no nameserver at all. pacman inside it failed on every
#| mirror with "Could not resolve host", after 4.6 GB had already been
#| installed.
sub prepare-bind-target(Str $target --> Str) is export {
    my $displaced = '';

    if $target.IO.l {
        my $link = run('readlink', $target, :out, :err);
        $displaced = $link.out.slurp(:close).trim;
        $link.err.slurp(:close);
        unlink $target;
    }

    $target.IO.spurt unless $target.IO.e;
    $displaced;
}

#| Put back the symlink a bind mount displaced. The installed system needs it:
#| without it, /etc/resolv.conf would be the empty regular file that stood in
#| for it during the installation, and the installed system would resolve
#| nothing.
sub restore-bind-target(Str $target, Str $link) is export {
    return unless $link;
    unlink $target if $target.IO.e && !$target.IO.l;
    # IO::Path.symlink creates a link *named* by its argument and pointing at
    # the invocant, so the link text is the invocant here.
    $link.IO.symlink($target);
}

sub create-bind-mount(Str $source, Str $target) is export {

    if $source.IO.d {
        mkdir $target unless $target.IO.d;
    } else {
        my $target-dir = $target.IO.dirname;
        mkdir $target-dir unless $target-dir.IO.d;
        my $displaced = prepare-bind-target($target);
        if $displaced {
            Logging.echo("'$target' was a symlink to '$displaced'; put aside for the bind mount and restored afterwards");
            @displaced-symlinks.push: [$target, $displaced];
        }
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

    # Only once nothing is mounted over them any more.
    for @displaced-symlinks.reverse -> ($target, $link) {
        restore-bind-target($target, $link);
        Logging.echo("Restored the symlink '$target' -> '$link'");
    }
    @displaced-symlinks = ();
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
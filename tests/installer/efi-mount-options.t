use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use Mount;
use Settings;

# The EFI partition is mounted so that only root is permitted to access it or
# view any contents within, and the installed system mounts it identically.
#
# vfat does not store permissions: every file and directory on it adopts the
# mode specified by its mount options, and the chmod the installer used to
# apply at the mount point had no effect. genfstab writes the options reported
# by the kernel into the fstab of the new system, and with no masks of their
# own, these were fmask=0022,dmask=0022. On each boot, bootctl then indicated
# that /boot/efi and the random seed it maintains there are world accessible,
# "which is a security hole!".
#
# Mounting needs root privileges, so the mount(8) the installer locates here
# acts as a stand-in, logging its arguments without performing any actual
# mounting. What is checked is what the installer asks mount to do. The
# subsequent steps -- the kernel reporting the masks, genfstab copying them
# into the fstab -- are not part of the installer's code and are not subjected
# to testing here.

my $fixture = $?FILE.IO.absolute.IO.parent.child('fixture').absolute;
chdir $fixture;

my $scratch = $*TMPDIR.child('ditana-efi-mount-tests');
$scratch.mkdir;
my $bin = $scratch.child('bin');
$bin.mkdir;
my $arguments = $scratch.child('mount-arguments');

$bin.child('mount').spurt: q:to/SH/.subst('__ARGUMENTS__', $arguments.absolute, :g);
    #!/bin/sh
    printf '%s\n' "$@" > '__ARGUMENTS__'
    SH
$bin.child('mount').chmod(0o755);
%*ENV<PATH> = "{$bin.absolute}:{%*ENV<PATH>}";

#| What mount-bootloader-partition hands to mount, one argument per element.
sub mounted() {
    $arguments.unlink if $arguments.e;
    mount-bootloader-partition();
    $arguments.e ?? $arguments.lines.List !! ();
}

#| The masks applied to a vfat mount, derived from the options handed to mount:
#| umask sets both, fmask governs files, and dmask governs directories, and a
#| later option overrides an earlier one. A mask left unset by any option
#| remains undefined. The kernel would take the umask of the user executing
#| mount, and genfstab would record that value.
sub fat-masks(@mount-arguments) {
    my %mask;
    for @mount-arguments.rotor(2 => -1).grep(*[0] eq '-o').map(*[1].split(',')).flat {
        when /^ 'umask=' (<[0..7]>+) $/ { %mask<file> = %mask<directory> = :8(~$0) }
        when /^ 'fmask=' (<[0..7]>+) $/ { %mask<file> = :8(~$0) }
        when /^ 'dmask=' (<[0..7]>+) $/ { %mask<directory> = :8(~$0) }
    }
    %mask;
}

#| Whether a mask leaves group and others no permission whatsoever.
sub root-only($mask) { $mask.defined && $mask +& 0o077 == 0o077 }

# --- a UEFI machine ---------------------------------------------------------

Settings.instance.set('uefi', True);
Settings.instance.set('bootloader-partition', '/dev/test-efi');
my @mounted = mounted();

is-deeply @mounted.tail(2).List, ('/dev/test-efi', '/mnt/boot/efi'),
    'the EFI partition is mounted at /boot/efi of the new system';
my %mask = fat-masks(@mounted);
ok root-only(%mask<directory>),
    'no directory on it is open to anyone but root, the mount point included';
ok root-only(%mask<file>),
    'and no file is, loader/random-seed included';

# --- a UEFI machine with ZFS ------------------------------------------------

# The combination for which the masks are designed:
# systemd-boot-random-seed.service, the unit that runs bootctl at every
# boot, operates exclusively on a UEFI machine with ZFS, and the nightly
# test installation installs exactly this way. On a BIOS machine,
# zfs-filesystem selects the Syslinux branch of mount-bootloader-partition.
# If a UEFI machine with ZFS were to end up in that path as well, the
# scenarios preceding and following this one would still pass.
Settings.instance.set('uefi', True);
Settings.instance.set('zfs-filesystem', True);
Settings.instance.set('bootloader-partition', '/dev/test-efi-zfs');
@mounted = mounted();

is-deeply @mounted.tail(2).List, ('/dev/test-efi-zfs', '/mnt/boot/efi'),
    'with ZFS as well, the EFI partition is mounted at /boot/efi of the new system';
%mask = fat-masks(@mounted);
ok root-only(%mask<directory>),
    'with ZFS, no directory on it is open to anyone but root, the mount point included';
ok root-only(%mask<file>),
    'with ZFS, no file on it is either, loader/random-seed included';

# --- a BIOS machine with ZFS ------------------------------------------------

# The masks are exclusive to the EFI partition. On a BIOS machine utilizing ZFS,
# the bootloader partition is formatted as ext4, which refuses to mount when
# presented with an option it does not recognize.
Settings.instance.set('uefi', False);
Settings.instance.set('zfs-filesystem', True);
Settings.instance.set('bootloader-partition', '/dev/test-bios');
@mounted = mounted();

is-deeply @mounted.tail(2).List, ('/dev/test-bios', '/mnt/boot/syslinux'),
    'without UEFI, the bootloader partition for ZFS is mounted at /boot/syslinux';
nok fat-masks(@mounted),
    'and without the masks, which are no option of ext4';

.unlink for ($bin.child('mount'), $arguments).grep(*.e);
$bin.rmdir;
$scratch.rmdir;

done-testing;

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
use AskForYesNo;
use Dialogs;
use JSON::Fast;
use Logging;
use RunAndLog;
use Settings;

sub is-secure-password(
    Str $passphrase,
    Int $min-score = 67
    --> Str) {

    my $proc = shell "pwscore <<< $passphrase", :merge;
    my $score = $proc.out.slurp: :close;

    return $score if $proc.exitcode != 0; # pwscore prints an explanation in this case

    # We expect pwscore to only output a number if it is successful.
    # If this property of pwscore has been changed or is not reliable,
    # we will only perform the above basic check.
    return '' if not $score.Num.defined;

    # Check if score is below minimum
    if $score < $min-score {
        return "Your password is {$min-score - $score} % below the minimum security requirements.
For a stronger password, use a mix of uppercase and lowercase letters, numbers, and special characters."
    }

    return '';
}

sub encrypt-luks(Str $partition) {
    Logging.echo("Encrypting partition $partition");

    loop {
        my $passphrase = qx{dialog --stdout --insecure --passwordbox 'Please enter a passphrase for the encrypted root partition' 10 50};

        unless $passphrase {
            show-dialog-raw('--msgbox', 'Please specify a passphrase.', '10', '50');
            next;
        }

        my $pw-check = is-secure-password($passphrase);
        if $pw-check {
            show-dialog-raw('--msgbox', $pw-check, '7', '80');
            next;
        }

        my $confirm-passphrase = qx{dialog --stdout --insecure --passwordbox 'Please confirm the passphrase' 10 50};

        if $confirm-passphrase {
            if $confirm-passphrase eq $passphrase {
                $confirm-passphrase = Nil;
                my $luks-key-file = qx{mktemp}.chomp; # has 0600
                $luks-key-file.IO.spurt($passphrase);
                $passphrase = Nil;

                run-and-echo("cryptsetup", "luksFormat", $partition, "--key-file", $luks-key-file, "--batch-mode");
                run-and-echo("cryptsetup", "open", $partition, "root", "--key-file", $luks-key-file);
                run-and-echo("shred", "-u", $luks-key-file);

                last;
            } else {
                $confirm-passphrase = Nil;
                show-dialog-raw('--msgbox', 'Passphrases do not match. Please try again.', '10','50');
            }
        }
    }

    shell q{clear};
}


my $zfs-key-file = "";

sub create-zfs-pool(Str $partition) {
    my $s = Settings.instance;
    my @encryption-options;

    # Sector size detection
    my $sector-size = query-blockdevices("-o PHY-SEC $partition")[0]<phy-sec>; # this also works for NVMEs
    Logging.echo("Detected physical sector size $sector-size of $partition");

    my $ashift = $sector-size == 4096 ?? 12 !! 9;

    Logging.echo("Creating ZFS pool ditana-root");
    my @base-options = (
        '-f',
        '-o', "ashift=$ashift",
        '-O', 'acltype=posixacl',
        '-O', 'xattr=sa',
        '-O', 'dnodesize=legacy',
        '-O', 'normalization=formD',
        '-O', 'mountpoint=none',
        '-O', 'canmount=off',
        '-O', 'devices=off',
        '-O', 'compression=zstd',
        '-R', '/mnt'
    );

    if $s.get('disable-atimes') {
        @base-options.append: '-O', 'atime=off';
    } else {
        @base-options.append: '-O', 'atime=on'; # and relatime=off (default)
    }

    if $s.get('encrypt-root-partition') {
        my $passphrase;
        my $confirm-passphrase;

        loop {
            my $passphrase = qx{dialog --stdout --insecure --passwordbox 'Please enter a passphrase for the encrypted root partition' 10 50};

            unless $passphrase {
                show-dialog-raw('--msgbox', 'Please specify a passphrase.', '10', '50');
                next;
            }

            my $pw-check = is-secure-password($passphrase);
            if $pw-check {
                show-dialog-raw('--msgbox', $pw-check, '7', '80');
                next;
            }

            my $confirm-passphrase = qx{dialog --stdout --insecure --passwordbox 'Please confirm the passphrase' 10 50};

            if $confirm-passphrase {
                if $passphrase eq $confirm-passphrase {
                    $confirm-passphrase = Nil;
                    $zfs-key-file = qx{mktemp}.chomp; # has 0600
                    spurt $zfs-key-file, $passphrase;
                    $passphrase = Nil;

                    @encryption-options = (
                        '-O', 'encryption=aes-256-gcm',
                        '-O', 'keyformat=passphrase',
                        '-O', "keylocation=file://$zfs-key-file"
                    );
                    last;
                } else {
                    $confirm-passphrase = Nil;
                    show-dialog-raw('--msgbox', 'Passphrases do not match. Please try again.', '10', '50');
                }
            }
        }

        shell q{clear};
    }

    my $part-uuid = run-and-echo('blkid', '-s', 'PARTUUID', '-o', 'value', $partition).trim;
    Logging.echo("PART_UUID of $partition: $part-uuid");

    run-and-echo('udevadm', 'settle');

    run-and-echo(
        'zpool', 'create',
        |@base-options,
        |@encryption-options,
        'ditana-root',
        "/dev/disk/by-partuuid/$part-uuid",
    );
}

sub cleanup-existing-zfs(Str $install-disk) {
    # ZFS labels survive repartitioning and the live ISO may auto-import a pool
    # found on the disk, which then holds device handles on its partitions and
    # makes the kernel re-read of the new partition table fail with EBUSY. We
    # therefore export every imported pool before touching the disk.
    Logging.echo("Removing any existing ZFS pools, as ZFS can persist even after repartitioning and cause conflicts with the current installation:");

    run-and-echo('modprobe', 'zfs');

    # List imported pools. If the kernel module is loaded but no pool is
    # imported, `zpool list` prints "no pools available" to stderr and exits 0,
    # so this is safe to call unconditionally.
    my $pools-output = run-and-echo-allow-fail('zpool', 'list', '-H', '-o', 'name');

    for $pools-output.lines -> $pool {
        my $name = $pool.trim;
        next unless $name;
        Logging.echo("Exporting existing ZFS pool '$name' to release device handles");
        run-and-echo-allow-fail('zpool', 'export', '-f', $name);
    }

    # Clear any residual ZFS labels on each partition. ZFS labels live on the
    # partitions (e.g. sda3), not on the disk itself, so iterating partitions
    # is required. Each call may fail harmlessly when the partition contains
    # no ZFS label.
    my @partitions = query-blockdevices("-lpo NAME /dev/$install-disk")
        .map(*<name>)
        .grep(* ne "/dev/$install-disk");

    for @partitions -> $part {
        Logging.echo("Clearing potential ZFS label on $part");
        run-and-echo-allow-fail('zpool', 'labelclear', '-f', $part);
    }
}

sub wipe-disk(Str $install-disk) {
    # Wipe filesystem signatures on each partition first. Without this, signals
    # like vfat/zfs_member/swap can confuse later tooling, even after a new
    # GPT has been written.
    my @partitions = query-blockdevices("-lpo NAME /dev/$install-disk")
        .map(*<name>)
        .grep(* ne "/dev/$install-disk");

    for @partitions -> $part {
        # Best-effort umount in case a previous installer attempt left mounts
        # behind; failures are expected and acceptable.
        run-and-echo-allow-fail('umount', $part);
        Logging.echo("Wiping filesystem signatures on $part");
        run-and-echo-allow-fail('wipefs', '-a', $part);
    }

    Logging.echo("Wiping filesystem signatures on /dev/$install-disk");
    run-and-echo-allow-fail('wipefs', '-a', "/dev/$install-disk");

    # sgdisk --zap-all destroys both the primary GPT header at the start of the
    # disk and the backup GPT header at the end. Plain `fdisk --wipe always`
    # only handles the primary header at write time, which is one of the
    # contributing factors to flaky behavior when re-installing.
    Logging.echo("Zapping GPT structures on /dev/$install-disk");
    run-and-echo('sgdisk', '--zap-all', "/dev/$install-disk");

    run-and-echo('partprobe', "/dev/$install-disk");
    run-and-echo('udevadm', 'settle');
}

sub get-filesystem-as-string() is export {
    my $s = Settings.instance;

    return do {
            if $s.get('btrfs-filesystem') { 'btrfs' }
            elsif $s.get('xfs-filesystem') { 'xfs' }
            elsif $s.get('ext4-filesystem') { 'ext4' }
            elsif $s.get('zfs-filesystem') { 'zfs' }
            else { die "get-filesystem-as-string: Unknown filesystem!" }
        };
}


sub format-and-mount-root-partition(Str $partition) {
    my $s = Settings.instance;

    Logging.echo("Formatting $partition");

    if $s.get('zfs-filesystem') {
        create-zfs-pool($partition);

        my $load-encryption-key = $s.get('encrypt-root-partition') ?? '-l' !! '';

        run-and-echo('zpool', 'export', 'ditana-root');
        run-and-echo(|"zpool import $load-encryption-key -R /mnt ditana-root".words, :retry(6));

        Logging.echo("Creating ZFS datasets");
        run-and-echo('zfs', 'create', '-o', 'mountpoint=none', 'ditana-root/ROOT');
        run-and-echo('zfs', 'create', '-o', 'mountpoint=none', 'ditana-root/HOME');
        run-and-echo('zfs', 'create', '-o', 'canmount=noauto', '-o', 'mountpoint=/', 'ditana-root/ROOT/default');
        run-and-echo('zfs', 'create', '-o', 'mountpoint=/home', 'ditana-root/HOME/default');

        run-and-echo('zpool', 'export', 'ditana-root');

        run-and-echo('zpool', 'import', '-d', '/dev/disk/by-id', '-R', '/mnt', 'ditana-root', '-N', :retry(6));
        run-and-echo(|"zfs mount $load-encryption-key ditana-root/ROOT/default".words);
        run-and-echo(|"zfs mount $load-encryption-key -a".words);

        if $s.get('encrypt-root-partition') {
            # Store the key file on the encrypted root dataset itself. This is
            # safe because the key file is protected by the very encryption it
            # unlocks: an attacker would need the passphrase to access the
            # dataset containing the key. The key file will be embedded into
            # the system initramfs (via FILES in mkinitcpio.conf), allowing
            # the boot process to require only a single passphrase prompt in
            # ZFSBootMenu rather than a second prompt from the initramfs.
            # See: https://docs.zfsbootmenu.org/en/latest/general/native-encryption.html
            run-and-echo('mkdir', '-p', '/mnt/etc/zfs');
            run-and-echo('cp', $zfs-key-file, '/mnt/etc/zfs/ditana-root.key');
            run-and-echo('chmod', '000', '/mnt/etc/zfs/ditana-root.key');
            run-and-echo('zfs', 'set', 'keylocation=file:///etc/zfs/ditana-root.key', 'ditana-root');
            run-and-echo('shred', '-u', $zfs-key-file);
        }

        run-and-echo('zpool', 'set', 'bootfs=ditana-root/ROOT/default', 'ditana-root');
        run-and-echo('zpool', 'set', 'cachefile=/etc/zfs/zpool.cache', 'ditana-root');

        run-and-echo('mkdir', '-p', '/mnt/etc/zfs');
        '/etc/zfs/zpool.cache'.IO.copy('/mnt/etc/zfs/zpool.cache');

        run-and-echo('zpool', 'sync');

        Logging.echo("ZFS Dataset status after mounting (outside arch-chroot)");
        run-and-echo('zfs', 'get', 'mounted,mountpoint,canmount',
            'ditana-root/ROOT/default', 'ditana-root/HOME/default');

        Logging.echo("Current ZFS mounts (outside arch-chroot)");
        Logging.echo(shell("mount | grep zfs",:out).out.slurp);
    } else {
        my $target-partition = $partition;
        if $s.get('encrypt-root-partition') {
            encrypt-luks($partition);
            $target-partition = "/dev/mapper/root";
        }

        my $filesystem = get-filesystem-as-string();
        my @mkfs-options = ('-L', 'ditana-root');

        if $s.get('ext4-filesystem') {
            my $rotational = slurp("/sys/block/{$s.get('install-disk')}/queue/rotational").trim;
            if $rotational != 0 {
                @mkfs-options.append: '-E', 'nodiscard';
            }
        }

        if $s.get('xfs-filesystem') || $s.get('btrfs-filesystem') {
            # Force filesystem creation. Without this option, the command fails with an error if remnants of a previous filesystem are detected
            # (e.g., "mkfs.xfs: /dev/sda3 appears to contain an existing filesystem (zfs_member)"),
            # even if a new GPT table was created on the volume beforehand.
            @mkfs-options.append: '-f';
        }

        run-and-echo('mkfs.' ~ $filesystem, |@mkfs-options, $target-partition);

        my $mount-opts = $s.get('disable-atimes') ?? 'noatime' !! '';

        Logging.echo("Mounting the root partition $target-partition");
        run-and-echo('mount', '-o', $mount-opts, $target-partition, '/mnt');

        if $s.get('btrfs-filesystem') {
            $mount-opts = ',' ~ $mount-opts if $mount-opts;

            run-and-echo('btrfs', 'subvolume', 'create', '/mnt/@');
            run-and-echo('btrfs', 'subvolume', 'create', '/mnt/@home');
            run-and-echo('umount', '/mnt');

            run-and-echo('mount', '-o', "subvol=@,compress=zstd{$mount-opts}", $target-partition, '/mnt');
            run-and-echo('mkdir', '/mnt/home');
            run-and-echo('mount', '-o', "subvol=@home,compress=zstd{$mount-opts}", $target-partition, '/mnt/home');
        }
    }
}

sub partition-with-sgdisk(Str $install-disk) {
    my $s = Settings.instance;
    my $disk = "/dev/$install-disk";

    # Partition type GUIDs / sgdisk shortcodes:
    #   EF00 = EFI System
    #   8300 = Linux filesystem
    #   8200 = Linux swap
    #   BF00 = Solaris root (used for ZFS on Linux)
    #   EF02 = BIOS boot partition (used for syslinux/zfsbootmenu on BIOS+ZFS)

    my Int $next-partnum = 1;

    # Step 1: create a fresh empty GPT.
    run-and-echo('sgdisk', '--clear', $disk);

    my $create-efi-partition = False;
    my $create-bios-partition = False;

    if $s.get('uefi') {
        if $s.get('bootloader-partition') eq 'new' {
            $create-efi-partition = True;
            Logging.log("EFI Partition will be created on $install-disk");
        } else {
            Logging.log("Won’t create an EFI partition, because '{$s.get('bootloader-partition')}' on other disk will be used");
        }
    } else {
        Logging.log("Not an EFI system, therefore a BIOS system partition will be created on $install-disk");
        $create-bios-partition = $s.get('zfs-filesystem');
    }

    # Step 2: bootloader partition (EFI or BIOS), if needed.
    if $create-efi-partition {
        my $n = $next-partnum++;
        run-and-echo('sgdisk',
            "--new={$n}:0:+512M",
            "--typecode={$n}:EF00",
            "--change-name={$n}:ditana-efi",
            $disk);
        Logging.log("Created EFI partition (partition $n)");
    } elsif $create-bios-partition {
        my $n = $next-partnum++;
        # 512 MiB BIOS partition holds syslinux + zfsbootmenu. The active/boot
        # flag is set via the legacy BIOS bootable attribute (-A 2).
        run-and-echo('sgdisk',
            "--new={$n}:0:+512M",
            "--typecode={$n}:8300",
            "--change-name={$n}:ditana-bios",
            "--attributes={$n}:set:2",
            $disk);
        Logging.log("Created BIOS system partition (partition $n)");
    }

    # Step 3: boot partition (only for non-ZFS layouts; ZFS holds /boot itself).
    unless $s.get('zfs-filesystem') {
        my $n = $next-partnum++;
        run-and-echo('sgdisk',
            "--new={$n}:0:+1536M",
            "--typecode={$n}:8300",
            "--change-name={$n}:ditana-boot",
            $disk);
        Logging.log("Created boot partition (partition $n)");
    }

    # Step 4: swap partition (optional).
    if $s.get('swap-partition') && $s.get('swap-partition') != 0 {
        my $size = $s.get('swap-partition');
        my $n = $next-partnum++;
        run-and-echo('sgdisk',
            "--new={$n}:0:+{$size}G",
            "--typecode={$n}:8200",
            "--change-name={$n}:ditana-swap",
            $disk);
        Logging.log("Created swap partition with {$size}GiB (partition $n)");
    } else {
        Logging.log("Will create no swap partition.");
    }

    # Step 5: root partition (always last, fills remaining space).
    my $n = $next-partnum++;
    my $root-typecode = $s.get('zfs-filesystem') ?? 'BF00' !! '8300';
    run-and-echo('sgdisk',
        "--new={$n}:0:0",
        "--typecode={$n}:$root-typecode",
        "--change-name={$n}:ditana-root",
        $disk);
    Logging.log("Created root partition (partition $n)");

    # Step 6: ensure kernel sees the new layout. partprobe is run with retry
    # because udev can briefly hold devices open right after sgdisk returns.
    run-and-echo('partprobe', $disk, :retry(5));
    run-and-echo('udevadm', 'settle');
    run-and-echo('sync');
    run-and-echo('lsblk');
}

sub partition-drive() is export {
    my $s = Settings.instance;
    my $install-disk = $s.get('install-disk');

    if $s.get('change-nvme-lba-format') {
        Logging.echo("Formatting $install-disk with LBAF index {$s.get('optimal-lba-format-index')}");
        run-and-echo('nvme', 'format', "--lbaf={$s.get('optimal-lba-format-index')}",
            "/dev/$install-disk");
    }

    # Always run the ZFS cleanup and disk wipe, regardless of the target
    # filesystem. A previous installation may have used ZFS, and re-installing
    # with a different filesystem must still release ZFS device handles and
    # destroy stale GPT/filesystem signatures. Skipping this conditionally
    # caused intermittent "Device or resource busy" failures when fdisk tried
    # to re-read the partition table on disks that still had an imported pool.
    cleanup-existing-zfs($install-disk);
    wipe-disk($install-disk);

    # Partition the disk using sgdisk in declarative mode (replaces the
    # previous fdisk batch-mode logic with its positional partition numbers
    # and EMPTY-line placeholders).
    Logging.echo("Partitioning $install-disk");
    partition-with-sgdisk($install-disk);
    Logging.log("Finished partitioning.");

    # Detect created partitions in on-disk order. sgdisk assigns partition
    # numbers sequentially starting at 1, matching the order in which we
    # created them in partition-with-sgdisk.
    my @partitions = query-blockdevices("-lpo NAME /dev/$install-disk")
        .map(*<name>)
        .grep(* ne "/dev/$install-disk");
    my $partition-index = 0;

    Logging.log("Detected partitions of $install-disk: {@partitions.gist}");

    my $create-efi-partition = $s.get('uefi') && $s.get('bootloader-partition') eq 'new';
    my $create-bios-partition = !$s.get('uefi') && $s.get('zfs-filesystem');

    if $create-efi-partition || $create-bios-partition {
        $s.set('bootloader-partition', @partitions[$partition-index]);
        $partition-index++;
    }

    if $s.get('uefi') || $s.get('zfs-filesystem') {
        # Note: when !$create-efi-partition, handle-current-efi-partition() has
        # already set bootloader-partition to the user-selected partition on
        # another disk.
        my $bootloader-parent-disk = query-blockdevices("-o PKNAME $s.get('bootloader-partition')")[0]<pkname>;
        $s.set('bootloader-parent-disk', $bootloader-parent-disk);

        my $bootloader-partition-index = $s.get('bootloader-partition').match(/\d+$/).Str;
        $s.set('bootloader-partition-index', $bootloader-partition-index);
    }

    if $create-efi-partition {
        run-and-echo('mkfs.fat', '-F32', '-n', 'ditana-efi', $s.get('bootloader-partition'));
    } elsif $create-bios-partition {
        run-and-echo('mkfs.ext4', '-F', '-L', 'ditana-bios', $s.get('bootloader-partition'));
    }

    unless $s.get('zfs-filesystem') {
        $s.set('bootimage-partition', @partitions[$partition-index]);
        $partition-index++;
        run-and-echo('mkfs.ext4', '-F', '-L', 'ditana-boot', $s.get('bootimage-partition'));
    }

    if $s.get('swap-partition') && $s.get('swap-partition') != 0 {
        $s.set('swap-partition', @partitions[$partition-index]);
        $partition-index++;
        run-and-echo('mkswap', '-L', 'ditana-swap', $s.get('swap-partition'));
    } else {
        Logging.log("No swap partition configured.");
    }

    $s.set('root-partition', @partitions[$partition-index]);
    $partition-index++;

    run-and-echo('sync');

    format-and-mount-root-partition($s.get('root-partition'));

    Logging.log("Finished partitioning.");
}

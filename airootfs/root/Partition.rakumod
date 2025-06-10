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
    
    run-and-echo(
        'zpool', 'create',
        |@base-options,
        |@encryption-options,
        'ditana-root',
        "/dev/disk/by-partuuid/$part-uuid",
    );
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
            run-and-echo('zfs', 'set', 'keylocation=prompt', 'ditana-root');
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

sub partition-drive() is export {
    my $s = Settings.instance;
    my $install-disk = $s.get('install-disk');
    
    if $s.get('change-nvme-lba-format') {
        Logging.echo("Formatting $install-disk with LBAF index {$s.get('optimal-lba-format-index')}");
        run-and-echo('nvme', 'format', "--lbaf={$s.get('optimal-lba-format-index')}", 
            "/dev/$install-disk");
    }
    
    if $s.get('zfs-filesystem') {
        Logging.echo("Removing any existing ZFS pools, as ZFS can persist even after repartitioning and cause conflicts with the current installation:");
        Logging.echo(run("zpool", "labelclear", "-f", "/dev/$install-disk", :merge).out.slurp);
    }
    
    my $create-efi-partition = False;
    
    if $s.get('uefi') {
        if $s.get('bootloader-partition') eq 'new' {
            $create-efi-partition = True;
            Logging.log("EFI Partition will be created on $install-disk");
        } else {
            Logging.log("Won’t create an EFI partition, because '{$s.get('bootloader-partition')}' on other disk will be used");
        }
    } else {
        Logging.log("Not an EFI system, therefore a BIOS system partition will be created on $install-disk");
    }
    
    my @fdisk-commands = $s.get('uefi') ?? 'g' !! 'o';  # create a new empty GPT or MBR partition table
    my $first-partition = True;
    my $number-of-partitions = 0;
    
    if $create-efi-partition {
        # Create EFI system partition
        @fdisk-commands.append:
            'n',          # create new partition
            '',           # default partition number
            '',           # default first sector
            '+512M',      # size of EFI system partition
            't',          # change partition type
            'EFI System'; # 1
        Logging.log("Generated commands to create EFI partition.");
        $first-partition = False;
        $number-of-partitions++;
    } elsif !$s.get('uefi') && $s.get('zfs-filesystem') {
        # Create BIOS system partition
        @fdisk-commands.append:
            'n', # create new partition
            'p', # partition type 'primary'
            '',  # default partition number
            '',  # default first sector
            '+512M', # size of the partition for syslinux and zfsbootmenu
            'a',     # toggle bootable flag
            '',      # default partition number
            't',     # change partition type
            'Linux'; # 83

        Logging.log("Generated commands to create BIOS system partition.");
        $first-partition = False;
        $number-of-partitions++;
    }
    
    unless $s.get('zfs-filesystem') {
        # Create boot partition
        @fdisk-commands.append: 'n'; # create new partition

        unless $s.get('uefi') {
            @fdisk-commands.append: 'p'; # partition type 'primary' 
        }

        @fdisk-commands.append:
            '',       # default partition number
            '',       # default first sector
            '+1536M', # size of boot partition
            't';      # change partition type
        @fdisk-commands.append: '' unless $first-partition; # default partition number
        $first-partition = False;
        $number-of-partitions++;
        @fdisk-commands.append: $s.get('uefi') ?? 'Linux filesystem' #`(20) !! 'Linux' #`(83);
        Logging.log("Generated commands to create boot partition.");
    }
    
    # Swap Partition
    if $s.get('swap-partition') && $s.get('swap-partition') != 0 {
        @fdisk-commands.append: 'n'; # create new partition

        unless $s.get('uefi') {
            @fdisk-commands.append: 'p'; # partition type 'primary' 
        }

        @fdisk-commands.append:
            '',  # default partition number
            '',  # default first sector
            "+{$s.get('swap-partition')}G", # size of swap partition
            't'; # change partition type
        @fdisk-commands.append: '' unless $first-partition; # default partition number
        $first-partition = False;
        $number-of-partitions++;
        @fdisk-commands.append: $s.get('uefi') ?? 'Linux swap' #`(19) !! 'Linux swap / Solaris' #`(82);
        Logging.log("Generated commands to create swap partition with {$s.get('swap-partition')}GiB");
    } else {
        Logging.log("Will create no swap partition.");
    }
    
    # Root Partition
    @fdisk-commands.append: 'n'; # create new partition

    unless $s.get('uefi') {
        @fdisk-commands.append: 'p'; # partition type 'primary' 
    }

    if $s.get('uefi') || $number-of-partitions < 4 {
        @fdisk-commands.append: '';  # default partition number
    }

    @fdisk-commands.append:
        '',  # default first sector
        '',  # default last sector (rest of the disk)
        't'; # change partition type
    @fdisk-commands.append: '' unless $first-partition; # default partition number
    $first-partition = False;
    @fdisk-commands.append: $s.get('zfs-filesystem')
        ?? ($s.get('uefi') ?? 'Solaris root' #`(162) !! 'Solaris' #`(bf))
        !! ($s.get('uefi') ?? 'Linux filesystem' #`(20) !! 'Linux' #`(83));
    Logging.log("Generated commands to create root partition.");
    
    # Write changes
    @fdisk-commands.append: 'w';
    
    # Start fdisk to partition the disk
    my $fdisk-input = @fdisk-commands.join("\n");
    Logging.echo("Partitioning $install-disk");
    run-and-echo('fdisk', '--wipe', 'always', '--wipe-partitions', 'always', "/dev/$install-disk", :input($fdisk-input));
    
    Logging.log("Finished fdisk /dev/$install-disk");
    run-and-echo('partprobe', "/dev/$install-disk");
    run-and-echo('udevadm', "settle");
    run-and-echo('lsblk');
    
    # Partition Detection
    my @partitions = query-blockdevices("-lpo NAME /dev/$install-disk").map(*<name>).grep(* ne "/dev/$install-disk");
    my $partition-index = 0;
    
    Logging.log("Detected partitions of $install-disk: {@partitions.gist}");
    
    if $create-efi-partition || (!$s.get('uefi') && $s.get('zfs-filesystem')) {
        # bootloader-partition is either the EFI or the BIOS partition, depending on the system
        $s.set('bootloader-partition', @partitions[$partition-index]);
        $partition-index++;
    }
    
    if $s.get('uefi') || $s.get('zfs-filesystem') {
        # Note that in case !$create-efi-partition, handle-current-efi-partition() sets bootloader-partition to the one the user chose (on a different volume)
        my $bootloader-parent-disk = query-blockdevices("-o PKNAME $s.get('bootloader-partition')")[0]<pkname>;
        $s.set('bootloader-parent-disk', $bootloader-parent-disk);

        my $bootloader-partition-index = $s.get('bootloader-partition').match(/\d+$/).Str;
        $s.set('bootloader-partition-index', $bootloader-partition-index);
    }
    
    if $create-efi-partition {
        run-and-echo('sgdisk', '-c', "{$partition-index}:ditana-efi", "/dev/$install-disk");
        run-and-echo('mkfs.fat', '-F32', '-n', 'ditana-efi', $s.get('bootloader-partition'));
    } elsif !$s.get('uefi') && $s.get('zfs-filesystem') {
        run-and-echo('mkfs.ext4', '-F', '-L', 'ditana-bios', $s.get('bootloader-partition'));
    }
    
    unless $s.get('zfs-filesystem') {
        $s.set('bootimage-partition', @partitions[$partition-index]);
        $partition-index++;
        if $s.get('uefi') {
            run-and-echo('sgdisk', '-c', "{$partition-index}:ditana-boot", "/dev/$install-disk");
        }
        run-and-echo('mkfs.ext4', '-F', '-L', 'ditana-boot', $s.get('bootimage-partition'));
    }
    
    if $s.get('swap-partition') && $s.get('swap-partition') != 0 {
        $s.set('swap-partition', @partitions[$partition-index]);
        $partition-index++;
        if $s.get('uefi') {
            run-and-echo('sgdisk', '-c', "{$partition-index}:ditana-swap", "/dev/$install-disk");
        }
        run-and-echo('mkswap', '-L', 'ditana-swap', $s.get('swap-partition'));
    } else {
        Logging.log("No swap partition configured.");
    }
    
    $s.set('root-partition', @partitions[$partition-index]);
    $partition-index++;
    if $s.get('uefi') {
        run-and-echo('sgdisk', '-c', "{$partition-index}:ditana-root", "/dev/$install-disk");
    }

    run-and-echo('sync');

    format-and-mount-root-partition($s.get('root-partition'));
    
    Logging.log("Finished partitioning.");
}

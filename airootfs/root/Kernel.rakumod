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

sub create-kernel-configuration() is export {
    my $s = Settings.instance;
    
    my $kernel-options = "";

    my $current-kernel-options = '/proc/cmdline'.IO.slurp;
    if $current-kernel-options.contains("nomodeset") {
        $kernel-options ~= " nomodeset"
    }

    # Unconditional sysctl settings and swappiness (which depends on multiple other settings)
    my $conf-content = "";
    $conf-content ~= "net.ipv6.conf.all.accept_ra=1\n";
    $conf-content ~= "net.ipv6.conf.default.accept_ra=1\n";

    if $s.get("kernel-option-swapp") { # For all settings, True means that we deviate from the Kernel Default.
        if $s.get("install-zram") { # kernel-option-swapp is a special setting that we handle differently based on ZRAM
            $conf-content ~= "vm.swappiness=180 # recommended for ZRAM\n" # https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram
        } elsif $s.get("swap-partition") && $s.get("swap-partition") != "0" {
            $conf-content ~= "vm.swappiness=1\n"
        }
    }

    my $kernel-conf-dir = "/mnt/etc/sysctl.d";
    mkdir($kernel-conf-dir);
    "$kernel-conf-dir/ditana.conf".IO.spurt($conf-content);

    # Kernel command line parameters
    if $s.get("kernel-option-fwdpe") { $kernel-options ~= " fw_devlink=permissive" }      # https://docs.kernel.org/admin-guide/kernel-parameters.html
    if $s.get("kernel-option-inita") { $kernel-options ~= " init_on_alloc=1" }            # https://docs.kernel.org/admin-guide/kernel-parameters.html
    if $s.get("kernel-option-initf") { $kernel-options ~= " init_on_free=1" }             # https://docs.kernel.org/admin-guide/kernel-parameters.html
    if $s.get("kernel-option-spec2") { $kernel-options ~= " spectre_v2=on" }              # https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/spectre.html
    if $s.get("kernel-option-l1tff") { $kernel-options ~= " l1tf=full,force" }            # https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/l1tf.html
    if $s.get("kernel-option-mdsfu") { $kernel-options ~= " mds=full,nosmt" }             # https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/mds.html
    if $s.get("kernel-option-tsxaa") { $kernel-options ~= " tsx_async_abort=full,nosmt" } # https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/tsx_async_abort.html
    if $s.get("kernel-option-meltd") { $kernel-options ~= " l1d_flush=on" }               # https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/l1d_flush.html
    if $s.get("kernel-option-mmios") { $kernel-options ~= " mmio_stale_data=full,nosmt" } # https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/l1tf.html
    if $s.get("kernel-option-retbl") { $kernel-options ~= " retbleed=auto,nosmt" }        # https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html
    if $s.get("kernel-option-srsom") { $kernel-options ~= " spec_rstack_overflow=ibpb spectre_v2_user=on" } # https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/srso.html
    if $s.get("kernel-option-gdsfo") { $kernel-options ~= " gather_data_sampling=force" } # https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/gather_data_sampling.html
    if $s.get("kernel-option-rfdso") { $kernel-options ~= " reg_file_data_sampling=on" }  # https://www.kernel.org/doc/html/latest/admin-guide/hw-vuln/reg-file-data-sampling.html
    if $s.get("kernel-option-mitof") { $kernel-options ~= " mitigations=off" }            # https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html
    if $s.get("kernel-option-ibtof") { $kernel-options ~= " ibt=off" }                    # undocumented
    if $s.get("kernel-option-zswap") { $kernel-options ~= " zswap.enabled=0" }            # https://wiki.archlinux.org/title/Zram#Usage_as_swap

    if $s.get("encrypt-root-partition") && !$s.get("zfs-filesystem") {
        my $uuid = run-and-echo("blkid", "-s", "UUID", "-o", "value", $s.get("root-partition")).trim;

        # https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#Configuring_the_boot_loader
        if $s.get("use-init-systemd") {
            $kernel-options ~= " rd.luks.name=$uuid=root root=/dev/mapper/root"
        } elsif $s.get("use-init-busybox") {
            $kernel-options ~= " cryptdevice=UUID={$uuid}:root root=/dev/mapper/root"
        }
    }

    if $s.get("install-nvidia-proprietary") || $s.get("install-nvidia-opensource") {
        # If an NVIDIA GPU is detected and a driver is installed, enable kernel mode setting (KMS) for the NVIDIA driver
        $kernel-options ~= " nvidia-drm.modeset=1"
    }

    if $s.get("enable-auditd") {
        # Prevent message 'audit: kauditd hold queue overflow' in 'journalctl -b -p err'.
        # This issue may occur under conditions of limited CPU resources.
        $kernel-options ~= " audit=1 audit_backlog_limit=8192"
    }

    $s.set("kernel-options", $kernel-options)
}

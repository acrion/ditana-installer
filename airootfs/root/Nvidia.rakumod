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
use Internet;
use Logging;
use NvidiaParser;
use PackageManagement;
use Settings;

sub is-in-nvidia-open-list($pci-id) is export {
    CATCH {
        default {
            Logging.log("is-in-nvidia-open-list: Unexpected error: $_");
            return Nil;
        }
    }

    show-dialog-raw('--infobox', "Checking if your NVIDIA GPU with PCI ID $pci-id is supported by the open-source kernel modules...", 5, 60);

    my $nvidia_open_gpu_page = download-and-filter-nvidia-open-page();

    unless $nvidia_open_gpu_page {
        Logging.log("is-in-nvidia-open-list: Falling back to cached version of the open GPU list.");
        $nvidia_open_gpu_page = '/root/cached_open_gpu_page.txt'; # provided during ISO generation by build.sh
    }

    return parse-nvidia-open-page($nvidia_open_gpu_page, $pci-id);
}

sub get-nvidia-driver-version($pci-id) is export {
    CATCH {
        default {
            Logging.log("get-nvidia-driver-version: Unexpected error: $_");
            return Nil;
        }
    }
    
    show-dialog-raw('--infobox', "Checking the required driver version for your NVIDIA graphics card with PCI ID $pci-id...", 5, 52);
    
    my $nvidia_legacy_gpu_page = download-and-filter-nvidia-legacy-page();
    
    unless $nvidia_legacy_gpu_page {
        Logging.log("get-nvidia-driver-version: We fallback to a cached version of https://www.nvidia.com/en-us/drivers/unix/legacy-gpu to check if PCI ID $pci-id requires a legacy driver.");
        $nvidia_legacy_gpu_page='/root/cached_legacy_gpu_page.html'; # provided during ISO generation by build.sh
    }

    return parse-nvidia-page($nvidia_legacy_gpu_page, $pci-id);
}

sub check-nvidia($silent-exit-code, $reset-to-default) is export {
    return $silent-exit-code if $silent-exit-code != 0; # only do this if user navigated forward

    state $checked-nvidia is default(False);
    return $silent-exit-code if $checked-nvidia && !$reset-to-default;
    $checked-nvidia = True;

    my $s = Settings.instance;
    
    return $silent-exit-code unless $s.get('nvidia-pci-id');

    my $pci-id = $s.get('nvidia-pci-id');

    # Step 1: Check if the GPU is supported by the open-source NVIDIA kernel modules (Turing+).
    my $in-open-list = is-in-nvidia-open-list($pci-id);

    my $url-nvidia-legacy = 'https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/';
    my $url-nvidia-open   = 'https://github.com/NVIDIA/open-gpu-kernel-modules';
    my $instruction;

    if $in-open-list {
        # GPU is supported by the open-source NVIDIA kernel modules (Turing or newer).
        # Default to nvidia-open-dkms. Nouveau is available as an alternative.
        # The proprietary closed-source kernel modules are no longer shipped as the main
        # Arch package (nvidia-dkms was replaced by nvidia-open-dkms with driver 590+).
        $s.modify-setting('install-nvidia-opensource',   'default-value', True);
        $s.modify-setting('install-nvidia-proprietary',  'available', "`False`");
        $s.modify-setting('install-nvidia-proprietary',  'default-value', False);
        $s.modify-setting('install-nouveau',             'default-value', "`NOT install-nvidia-opensource`");
        $s.set('install-nvidia-opensource', True);

        $instruction = "Your graphics card with PCI ID $pci-id is supported by the open-source NVIDIA kernel modules. "
                     ~ "The open-source driver (nvidia-open-dkms) is recommended as it integrates better with the Linux kernel "
                     ~ "and is now the default in Arch Linux since driver version 590. "
                     ~ "As an alternative, you can select the Nouveau open-source driver. Please select «Help» for details.";
    } else {
        # GPU is NOT in the open-source list. Determine the required legacy driver version.
        my $nvidia-driver-version = get-nvidia-driver-version($pci-id);

        if $nvidia-driver-version eq 'latest' {
            # The GPU is not listed as legacy on the NVIcached_open_gpu_page.txtDIA page, but also not in the open-source
            # GPU list. This indicates a Maxwell, Pascal, or Volta GPU (the NVIDIA legacy page has
            # not yet been updated to include 580.xx as a legacy tier as of 2025-12). These GPUs
            # require the nvidia-580xx-dkms proprietary driver.
            my $nvidia-proprietary-package = 'nvidia-580xx-dkms';
            $s.modify-setting('install-nvidia-proprietary', 'arch-packages', [$nvidia-proprietary-package]);

            show-dialog-raw('--infobox', "Checking available drivers for your NVIDIA graphics card with PCI ID $pci-id...", 14, 70);

            my $package-exists = run('pacman', '-Si', $nvidia-proprietary-package, :err(False), :out(False)).exitcode == 0;

            if $package-exists {
                $s.modify-setting('install-nvidia-proprietary',  'default-value', True);
                $s.modify-setting('install-nvidia-opensource',   'available', "`False`");
                $s.modify-setting('install-nvidia-opensource',   'default-value', False);
                $s.modify-setting('install-nouveau',             'default-value', "`NOT install-nvidia-proprietary`");
                $s.set('install-nvidia-proprietary', True);

                $instruction = "Your graphics card with PCI ID $pci-id is not supported by the current open-source NVIDIA kernel modules "
                             ~ "(Turing or newer required). Since driver version 590, Maxwell, Pascal, and Volta GPUs require the "
                             ~ "legacy proprietary driver (nvidia-580xx-dkms). This driver will receive security updates through October 2028. "
                             ~ "As an alternative, you can select the Nouveau open-source driver. Please select «Help» for details.";
            } else {
                # nvidia-580xx-dkms is not available - fall back to Nouveau.
                $s.modify-setting('install-nvidia-proprietary', 'available', "`False`");
                $s.modify-setting('install-nvidia-proprietary', 'default-value', False);
                $s.modify-setting('install-nvidia-opensource',  'available', "`False`");
                $s.modify-setting('install-nvidia-opensource',  'default-value', False);
                $s.modify-setting('install-nouveau',           'default-value', True);
                $s.set('install-nouveau', True);

                $instruction = "Your graphics card with PCI ID $pci-id requires the legacy proprietary driver (nvidia-580xx-dkms), "
                             ~ "but this package is currently not available. The Nouveau open-source driver will be installed instead. "
                             ~ "This is unexpected - please contact support@ditana.org to inform about this situation.";
            }
        } elsif $nvidia-driver-version.Numeric.defined && $nvidia-driver-version >= 470 {
            # Legacy driver (470xx or 580xx if the NVIDIA page has been updated to list it).
            my $nvidia-proprietary-package = "nvidia-{$nvidia-driver-version}xx-dkms";
            $s.modify-setting('install-nvidia-proprietary', 'arch-packages', [$nvidia-proprietary-package]);

            show-dialog-raw('--infobox', "Checking available drivers for your NVIDIA graphics card with PCI ID $pci-id...", 14, 70);

            $instruction = "According to $url-nvidia-legacy, your graphics card with PCI ID $pci-id requires proprietary driver version $nvidia-driver-version. ";

            my $package-exists = run('pacman', '-Si', $nvidia-proprietary-package, :err(False), :out(False)).exitcode == 0;

            if $package-exists {
                $s.modify-setting('install-nvidia-proprietary', 'default-value', True);
                $s.modify-setting('install-nvidia-opensource',  'available', "`False`");
                $s.modify-setting('install-nvidia-opensource',  'default-value', False);
                $s.modify-setting('install-nouveau',           'default-value', "`NOT install-nvidia-proprietary`");
                $s.set('install-nvidia-proprietary', True);
            } else {
                $s.modify-setting('install-nvidia-proprietary', 'available', "`False`");
                $s.modify-setting('install-nvidia-proprietary', 'default-value', False);
                $s.modify-setting('install-nvidia-opensource',  'available', "`False`");
                $s.modify-setting('install-nvidia-opensource',  'default-value', False);
                $s.modify-setting('install-nouveau',           'default-value', True);
                $s.set('install-nouveau', True);

                $instruction ~= "We recommend the Nouveau driver as there is no Arch package for this version. "
                              ~ "This is unexpected - please contact support@ditana.org to inform about this situation.";
            }
        } else {
            # Very old legacy driver version (< 470). Nouveau is the only practical option.
            $s.modify-setting('install-nvidia-proprietary', 'available', "`False`");
            $s.modify-setting('install-nvidia-proprietary', 'default-value', False);
            $s.modify-setting('install-nvidia-opensource',  'available', "`False`");
            $s.modify-setting('install-nvidia-opensource',  'default-value', False);
            $s.modify-setting('install-nouveau',           'default-value', True);
            $s.set('install-nouveau', True);

            $instruction = "According to $url-nvidia-legacy, your graphics card with PCI ID $pci-id requires proprietary driver version $nvidia-driver-version. "
                         ~ "For this version, it is recommended to install the open-source Nouveau driver instead, as very old "
                         ~ "proprietary drivers may not be compatible with current kernels. Please select «Help» for details.";
        }
    }

    $s.modify-installation-step(('Configuration Categories', 'Expert Settings'), 'Hardware Support Options', 'instruction', $instruction);

    return $silent-exit-code
}

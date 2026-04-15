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
use Logging;
use Partition;
use Settings;

sub add-to-list($list, $item) {
    return $list ?? "$list\n$item" !! $item;
}

sub get-list-of-mitigations() {
    my $s = Settings.instance;
    my $list = "";
    
    $list = add-to-list($list, "        Spectre Variant 2 (spectre_v2=on)") if $s.get('kernel-option-spec2');
    $list = add-to-list($list, "        L1 Terminal Fault (l1tf=full,force)") if $s.get('kernel-option-l1tff');
    $list = add-to-list($list, "        MDS (mds=full,nosmt)") if $s.get('kernel-option-mdsfu');
    $list = add-to-list($list, "        TSX Async Abort (tsx_async_abort=full,nosmt)") if $s.get('kernel-option-tsxaa');
    $list = add-to-list($list, "        Meltdown (l1d_flush=on)") if $s.get('kernel-option-meltd');
    $list = add-to-list($list, "        MMIO Stale Data (mmio_stale_data=full,nosmt)") if $s.get('kernel-option-mmios');
    $list = add-to-list($list, "        Retbleed (retbleed=auto,nosmt)") if $s.get('kernel-option-retbl');
    $list = add-to-list($list, "        SRSO (spec_rstack_overflow=ibpb spectre_v2_user=on)") if $s.get('kernel-option-srsom');
    $list = add-to-list($list, "        Gather Data Sampling (gather_data_sampling=force)") if $s.get('kernel-option-gdsfo');
    $list = add-to-list($list, "        RFDS (reg_file_data_sampling=on)") if $s.get('kernel-option-rfdso');
    
    return $list;
}

sub get-kernel-description() {
    my $s = Settings.instance;
    return "Standard Kernel (Stable)" if $s.get('install-standard-stable-kernel');
    return "Standard Kernel (LTS)" if $s.get('install-standard-lts-kernel');
    return "Hardened Kernel (Stable)" if $s.get('install-hardened-stable-kernel');
    return "Hardened Kernel (LTS)" if $s.get('install-hardened-lts-kernel');
    return "Realtime Kernel (LTS)" if $s.get('install-realtime-lts-kernel');
    return "Zen Kernel (Stable)" if $s.get('install-zen-kernel');
    return "Undefined";
}

sub get-kernel-params-description() {
    my $s = Settings.instance;
    my $modify-swappiness-default = $s.get('install-zram') || $s.get('total-ram-gib')>=24;

    Logging.log("kernel-option-sysrq = {$s.get('kernel-option-sysrq')}");
    Logging.log("kernel-option-vfsca = {$s.get('kernel-option-vfsca')}");
    Logging.log("kernel-option-compa = {$s.get('kernel-option-compa')}");
    Logging.log("kernel-option-swapp = {$s.get('kernel-option-swapp')}");
    Logging.log("kernel-option-zswap = {$s.get('kernel-option-zswap')}");
    Logging.log("kernel-option-pagec = {$s.get('kernel-option-pagec')}");
    Logging.log("kernel-option-wmboo = {$s.get('kernel-option-wmboo')}");
    Logging.log("kernel-option-wmsca = {$s.get('kernel-option-wmsca')}");
    Logging.log("kernel-option-fwdpe = {$s.get('kernel-option-fwdpe')}");
    Logging.log("kernel-option-perf1 = {$s.get('kernel-option-perf1')}");
    Logging.log("kernel-option-duurn = {$s.get('kernel-option-duurn')}");
    Logging.log("kernel-option-inita = {$s.get('kernel-option-inita')}");
    Logging.log("kernel-option-initf = {$s.get('kernel-option-initf')}");
    Logging.log("sysctl-kptr-restrict  = {$s.get('sysctl-kptr-restrict')}");
    Logging.log("sysctl-dmesg-restrict = {$s.get('sysctl-dmesg-restrict')}");
    Logging.log("sysctl-bpf-disabled   = {$s.get('sysctl-bpf-disabled')}");
    Logging.log("sysctl-kexec-disabled = {$s.get('sysctl-kexec-disabled')}");
    Logging.log("sysctl-ptrace-restrict = {$s.get('sysctl-ptrace-restrict')}");
    Logging.log("sysctl-ptrace-unrestricted = {$s.get('sysctl-ptrace-unrestricted')}");
    Logging.log("sysctl-net-hardening  = {$s.get('sysctl-net-hardening')}");
    Logging.log("sysctl-fs-protection  = {$s.get('sysctl-fs-protection')}");
    Logging.log("kernel-option-spec2 = {$s.get('kernel-option-spec2')}");
    Logging.log("kernel-option-l1tff = {$s.get('kernel-option-l1tff')}");
    Logging.log("kernel-option-mdsfu = {$s.get('kernel-option-mdsfu')}");
    Logging.log("kernel-option-tsxaa = {$s.get('kernel-option-tsxaa')}");
    Logging.log("kernel-option-meltd = {$s.get('kernel-option-meltd')}");
    Logging.log("kernel-option-mmios = {$s.get('kernel-option-mmios')}");
    Logging.log("kernel-option-retbl = {$s.get('kernel-option-retbl')}");
    Logging.log("kernel-option-srsom = {$s.get('kernel-option-srsom')}");
    Logging.log("kernel-option-gdsfo = {$s.get('kernel-option-gdsfo')}");
    Logging.log("kernel-option-rfdso = {$s.get('kernel-option-rfdso')}");
    Logging.log("kernel-option-ibtof = {$s.get('kernel-option-ibtof')}");
    Logging.log("kernel-option-mitof = {$s.get('kernel-option-mitof')}");
    Logging.log("total-ram-gib       = {$s.get('total-ram-gib')}");
    Logging.log("install-zram        = {$s.get('install-zram')}");
    
    if $s.get('kernel-option-sysrq') &&
       $s.get('kernel-option-vfsca') == ($s.get('total-ram-gib')>=24) &&
       $s.get('kernel-option-compa') == ($s.get('total-ram-gib')>=24) &&
       $s.get('kernel-option-swapp') == $modify-swappiness-default &&
       $s.get('kernel-option-zswap') == $s.get('install-zram') &&
       $s.get('kernel-option-pagec') == $s.get('install-zram') &&
       $s.get('kernel-option-wmboo') == $s.get('install-zram') &&
       $s.get('kernel-option-wmsca') == $s.get('install-zram') &&
       $s.get('kernel-option-fwdpe') &&
       $s.get('kernel-option-perf1') &&
       !$s.get('kernel-option-duurn') &&
       $s.get('kernel-option-inita') &&
       $s.get('kernel-option-initf') &&
       # System Hardening
       $s.get('sysctl-kptr-restrict') &&
       $s.get('sysctl-dmesg-restrict') &&
       $s.get('sysctl-bpf-disabled') &&
       $s.get('sysctl-kexec-disabled') &&
       $s.get('sysctl-ptrace-restrict') == (not $s.get('install-desktop-environment')) &&
       $s.get('sysctl-ptrace-unrestricted') == $s.get('install-desktop-environment') &&
       $s.get('sysctl-net-hardening') &&
       $s.get('sysctl-fs-protection') &&
       # CPU Vulnerability Mitigation Options
       $s.get('kernel-option-spec2') == $s.get('is-spectre-v2-vulnerable') &&
       $s.get('kernel-option-l1tff') == $s.get('is-l1tf-vulnerable') &&
       $s.get('kernel-option-mdsfu') == $s.get('is-mds-vulnerable') &&
       $s.get('kernel-option-tsxaa') == $s.get('is-taa-vulnerable') &&
       $s.get('kernel-option-meltd') == $s.get('is-meltdown-vulnerable') &&
       $s.get('kernel-option-mmios') == $s.get('is-mmio-stale-data-vulnerable') &&
       $s.get('kernel-option-retbl') == $s.get('is-retbleed-vulnerable') &&
       $s.get('kernel-option-srsom') == $s.get('is-srso-vulnerable') &&
       $s.get('kernel-option-gdsfo') == $s.get('is-gds-vulnerable') &&
       $s.get('kernel-option-rfdso') == $s.get('is-rfds-vulnerable') &&
       !$s.get('kernel-option-ibtof') &&
       !$s.get('kernel-option-mitof') {
        return "Recommended (Ditana customized)";
    }
    
    unless $s.get('kernel-option-sysrq') ||
       $s.get('kernel-option-vfsca') ||
       $s.get('kernel-option-compa') ||
       $s.get('kernel-option-swapp') ||
       $s.get('kernel-option-zswap') ||
       $s.get('kernel-option-pagec') ||
       $s.get('kernel-option-wmboo') ||
       $s.get('kernel-option-wmsca') ||
       $s.get('kernel-option-fwdpe') ||
       $s.get('kernel-option-perf1') ||
       $s.get('kernel-option-duurn') ||
       $s.get('kernel-option-inita') ||
       $s.get('kernel-option-initf') ||
       # System Hardening
       $s.get('sysctl-kptr-restrict') ||
       $s.get('sysctl-dmesg-restrict') ||
       $s.get('sysctl-bpf-disabled') ||
       $s.get('sysctl-kexec-disabled') ||
       $s.get('sysctl-ptrace-restrict') == (not $s.get('install-desktop-environment')) ||
       $s.get('sysctl-ptrace-unrestricted') == $s.get('install-desktop-environment') ||
       $s.get('sysctl-net-hardening') ||
       $s.get('sysctl-fs-protection') ||
       # CPU Vulnerability Mitigation Options
       $s.get('kernel-option-spec2') ||
       $s.get('kernel-option-l1tff') ||
       $s.get('kernel-option-mdsfu') ||
       $s.get('kernel-option-tsxaa') ||
       $s.get('kernel-option-meltd') ||
       $s.get('kernel-option-mmios') ||
       $s.get('kernel-option-retbl') ||
       $s.get('kernel-option-srsom') ||
       $s.get('kernel-option-gdsfo') ||
       $s.get('kernel-option-rfdso') ||
       $s.get('kernel-option-ibtof') ||
       $s.get('kernel-option-mitof') {
        return "Kernel Default";
    }
    
    return "Customized by user";
}

sub get-mitigations-description() {
    my $s = Settings.instance;
    my $description = "";
    my $mitigation-list = get-list-of-mitigations();
    
    if $mitigation-list {
        $description = "Enforced High Security Mitigations for this CPU:\n\n$mitigation-list";
    }
    
    if $s.get('kernel-option-mitof') {
        $description ~= "Security Risk! All mitigations for this CPU’s vulnerabilities have been disabled. This affects many more vulnerabilities than those listed in the CPU Vulnerability Mitigation Options dialog. ";
    }
    
    if $s.get('kernel-option-ibtof') {
        $description ~= "Security Risk! The Mitigation for Intel Branch Target Injection has been disabled.";
    }
    
    return $description || "Kernel default";
}

sub review-summary returns Int is export {
    my $s = Settings.instance;
    my $init-system-description = $s.get('use-init-systemd') ?? "systemd" !! "BusyBox";
    my $kernel-description = get-kernel-description();
    my $kernel-params-description = get-kernel-params-description();
    my $mitigations-description = get-mitigations-description();
    my $nvidia-description = "";
    my $nvidia-mention = "";
    if $s.get('nvidia-pci-id') {
        $nvidia-mention = "NVIDIA,";
        $nvidia-description = "
NVIDIA open source driver:     {$s.get('install-nvidia-opensource')}
NVIDIA proprietary driver:     {$s.get('install-nvidia-proprietary')}
Nouveau open source driver:    {$s.get('install-nouveau')}";
    }
    my $instruction = "Start installation, including partitioning?

Computer name:                 {$s.get('host-name')}
User name:                     {$s.get('user-name')} ({$s.get('user-id')}:{$s.get('user-group')})
Locale:                        {$s.get('locale')}
Time Zone:                     {$s.get('timezone')}
Installation disk:             {$s.get('install-disk')} ({$s.get('install-disk-description')})
Root File System:              {get-filesystem-as-string()}
Encryption of root partition:  {$s.get('encrypt-root-partition')}
Swap space:                    {$s.get('swap-partition')} GiB
ZRAM:                          {$s.get('install-zram')}$nvidia-description
Boot Init System:              $init-system-description
Kernel:                        $kernel-description
Kernel Configuration:          $kernel-params-description
CPU Vulnerability Mitigations: $mitigations-description

By pressing the Escape-Key you may navigate backwards and make changes. Note that the $nvidia-mention
Kernel and Boot Init System settings are available in the Menu «Advanced settings».";
    
    my %dialog-result = show-dialog-raw(
        '--defaultno',
        '--no-collapse',
        '--yesno',
        $instruction,
        $instruction.lines.elems+4,
        98);
    
    return %dialog-result<status>;
}

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

sub add-chrooted-step(Str $commands) is export {
    "bind-mount/root/installation-steps.sh".IO.spurt($commands.chomp ~ "\n\n", :append);
}

sub create-hostid() is export {
    # Create a unique /etc/hostid even if the filesystem is not ZFS. While /etc/hostid may only have
    # historical relevance outside of ZFS, creating a unique hostid is consistent with the original
    # design intent and does no harm. This ensures that the `hostid' command does not return a default
    # value such as 007f0101. After all, the `hostid' utility is still part of the GNU core utilities.
    run-and-echo("zgenhostid"); # Note that zgenhostid is always available in the live ISO, but not inside chroot
    mkdir('mnt/etc');
    die unless '/etc/hostid'.IO.copy('/mnt/etc/hostid');
}

sub copy-files-into-chroot-before-pacstrap() is export {
    run-and-echo("chown", "-R", "root:root", "%*ENV<HOME>/folders");
    run-and-echo("rsync", "--recursive", "--times", "--no-perms", "--executability", "--verbose", "%*ENV<HOME>/folders-before-pacstrap/", "/mnt/")
}

sub copy-files-into-chroot-after-pacstrap() is export {
    run-and-echo("chown", "-R", "root:root", "%*ENV<HOME>/folders");
    run-and-echo("rsync", "--recursive", "--times", "--no-perms", "--executability", "--verbose", "%*ENV<HOME>/folders/", "/mnt/")
}

sub add-version() is export {
    my $os-release-path = '/mnt/usr/lib/os-release'.IO;
    die unless $os-release-path.e;
    my $build-id = %*ENV<DITANA_BUILD_ID>;
    if $build-id {
        $os-release-path.spurt("BUILD_ID={$build-id}\n", :append); # see `man os-release`
    }
}

sub curate-chroot-files() is export {
    my $s = Settings.instance;

    '/etc/pacman.d/mirrorlist'.IO.copy('/mnt/etc/pacman.d/mirrorlist');

    '/mnt/etc/skel/.local/bin'.IO.mkdir;

    # https://wiki.archlinux.org/title/Installation_guide#Network_configuration
    '/mnt/etc/hostname'.IO.spurt($s.get('host-name') ~ "\n");

    if $s.get("install-zram") {
        '/mnt/etc/systemd/zram-generator.conf'.IO.spurt("[zram0]\n");
    }

    #if $s.get("install-kmscon") {
    #    '/mnt/etc/kmscon'.IO.mkdir;
    #    '/mnt/etc/kmscon/kmscon.conf'.IO.spurt("font-name=JetBrainsMono Nerd Font\n"); # font is installed by package ditana-config-xfce
    #    '/mnt/etc/kmscon/kmscon.conf'.spurt("no-drm\n", :append) if $s.get('nvidia-pci-id');
    #}

    unless $s.get("install-variety") {
        '/mnt/etc/skel/.config/variety/variety.conf'.IO.unlink;
        '/mnt/etc/skel/.config/autostart/variety.desktop'.IO.unlink;
    }

    unless $s.get("install-stable-diffusion") {
        '/mnt/usr/share/applications/stable-diffusion.desktop'.IO.unlink;
    }

    if $s.get("install-codegpt") {
        my $openai-api-file = '/mnt/etc/skel/.shell.d/openai.sh'.IO;
        $openai-api-file.spurt("# To use e. g. codegpt, you need to copy your OpenAI API key from
# https://platform.openai.com/api-keys
# to here. You may want to change the model, e.g. `codegpt config set openai.model gpt-4o-mini`
#export OPENAI_API_KEY=
");
        $openai-api-file.chmod(0o700)
    }

    if $s.get("install-terminal-utilities") {
        '/mnt/etc/skel/.config/bat'.IO.mkdir;
        '/mnt/etc/skel/.config/bat/config'.IO.spurt("--paging=never
--wrap=never
--style=snip
")
    }

    if $s.get("enable-network") {
        '/mnt/etc/hosts'.IO.spurt("# Static table lookup for hostnames.
# See hosts(5) for details.

127.0.0.1  localhost
::1        localhost ip6-localhost ip6-loopback
ff02::1    ip6-allnodes
ff02::2    ip6-allrouters
127.0.1.1  {$s.get('host-name')}.localdomain {$s.get('host-name')}");
        '/mnt/etc/hosts'.IO.chmod(0o644)
    }

    if $s.get("install-nvidia-prime") {
        # NOTE: NVIDIA Prime GPU Offloading Configuration Limitations
        #
        # While we install NVIDIA Prime support, there is currently no universal solution
        # to automatically enable GPU offloading for OpenGL applications. Users need to
        # manually invoke applications with the following environment variables:
        #
        # __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <application>
        #
        # Setting these variables globally via /etc/profile.d is not viable as it breaks
        # XFCE’s window manager (xfwm4) rendering. Alternative approaches like systemd
        # services or application profiles have their own limitations.
    }
    
    if $s.get("install-ollama") {
        add-chrooted-step(q{echo -e "\033[32m--- Configuring Ollama ---\033[0m"});
        add-chrooted-step(q{systemctl enable ollama});
        # Start ollama serve as the ollama user with the same environment as the
        # systemd unit, so the model is stored in /var/lib/ollama where the service
        # expects it at runtime.
        add-chrooted-step(q{runuser -u ollama -- env HOME=/var/lib/ollama OLLAMA_MODELS=/var/lib/ollama ollama serve > /dev/null 2>&1 &});
        add-chrooted-step(q{OLLAMA_PID=$!});
        add-chrooted-step(q{echo "Waiting for Ollama to start..."});
        add-chrooted-step(q{for i in $(seq 1 30); do ollama list > /dev/null 2>&1 && break; sleep 1; done});
        add-chrooted-step(q{echo -e "\033[32m--- Pulling phi4-mini model ---\033[0m"});
        add-chrooted-step(q{ollama pull phi4-mini});
        add-chrooted-step(q{kill $OLLAMA_PID 2>/dev/null || true});
        add-chrooted-step(q{wait $OLLAMA_PID 2>/dev/null || true});
    }
}

sub genfstab() is export {
    my $fstab = run-and-echo("genfstab", "-U", "/mnt").lines.grep(none(rx/«zfs»/)).join("\n");
    '/mnt/etc/fstab'.IO.spurt($fstab);
}

sub pacstrap() is export {
    my $s = Settings.instance;
    my @native-packages = $s.get-installed-native-packages;
    my @bootstrap = $s.get-bootstrap-packages;
    Logging.echo(@native-packages.gist);

    # At this point, the system time is synchronized. We log the status here to include it in bug reports (should include "System clock synchronized: yes").
    run-and-echo("timedatectl", "status");

    # Bootstrap with essential packages to initialize the target system.
    # The keyring is created via -K only on this first call.
    Logging.echo("Bootstrap packages: {@bootstrap.gist}");
    run-and-echo("pacstrap", "-K", "/mnt", |@bootstrap, :retry(2));

    # Install remaining packages in batches to reduce peak disk usage
    # (see https://github.com/acrion/ditana-installer/issues/5).
    # Using pacstrap without -K reuses the host's pacman.conf,
    # so custom repos (ditana, chaotic-aur) remain available.
    my @remaining = @native-packages.grep({ $_ ∉ @bootstrap });

    if @remaining.elems > 0 {
        my $batch-size = 30;
        for @remaining.batch($batch-size) -> @batch {
            Logging.echo("Installing package batch ({@batch.elems} packages)...");
            # In case of an error, we retry once, in case the error was related to a temporary download issue
            run-and-echo("pacstrap", "/mnt", |@batch, :retry(2));
            # Remove cached package files to free disk space
            shell "rm -f /mnt/var/cache/pacman/pkg/*.pkg.tar.*";
        }
    }
}

sub generate-chroot-settings-file() is export {
    Logging.log("get-required-by-chroot: start");
    my $s = Settings.instance;
    my $settings-file = "bind-mount/root/settings.sh".IO;
    if $settings-file.e {
        $settings-file.unlink;
    }

    for $s.get-required-by-chroot {
        my $value;
        if $s.get($_) ~~ Bool {
            $value = $s.get($_) ?? "y" !! "n";
        } else {
            $value = $s.get($_);
        }
        my $var = $_.uc.subst("-", "_", :g);
        Logging.log("get-required-by-chroot: $var=$value");
        $settings-file.spurt("$var=\"$value\"\n", :append);
    }

    Logging.log("get-required-by-chroot: end");
}

sub chroot-installation() is export {
    shell "arch-chroot /mnt /root/chroot-install.sh";
    die "During chroot install steps, an error occurred." unless '/mnt/var/log/chroot_installation_finished'.IO.e;
}

sub generate-aur-package-installation-script() is export {
    for Settings.instance.get-installed-aur-packages {
        add-chrooted-step("echo -e '\\033[32m--- Installing $_ ---\\033[0m'");
        add-chrooted-step("runuser -u builduser -- pikaur -S $_ --noconfirm || true")
    }
}

sub generate-chroot-script() is export {
    # Please note that the purpose of this function partly overlaps with that of the static script `bind-mount/chroot-install.sh`.
    # In general, more complex things that are required in the chroot environment should rather be coded in `bind-mount/chroot-install.sh`.
    # This function contains short steps based on simple case distinctions.

    my $s = Settings.instance;

    add-chrooted-step(q{echo -e "\033[32m--- Configuring time ---\033[0m"});
    add-chrooted-step("ln -sf '/usr/share/zoneinfo/{$s.get('timezone')}' /etc/localtime");
    add-chrooted-step("hwclock --systohc"); # generate /etc/adjtime

    if $s.get("enable-network") {
        add-chrooted-step("systemctl enable systemd-timesyncd"); # https://wiki.archlinux.org/title/Systemd-timesyncd#Enable_and_start
        add-chrooted-step("systemctl enable NetworkManager");
        add-chrooted-step("systemctl enable systemd-resolved");
    }

#    if $s.get("install-kmscon") {
#        for 2..5 -> $tty {
#            add-chrooted-step("systemctl disable getty\@tty{$tty}.service");
#            add-chrooted-step("systemctl enable kmsconvt\@tty{$tty}.service");
#        }
#    }

    if $s.get("install-bluetooth") {
        add-chrooted-step("systemctl enable bluetooth"); # https://wiki.archlinux.org/title/Bluetooth
    }

    add-chrooted-step(q{echo -e "\033[32m--- Generating locales ---\033[0m"});
    add-chrooted-step(q{locale-gen}); # https://wiki.archlinux.org/title/Installation_guide#Localization

    if $s.get("install-desktop-environment") {
        add-chrooted-step(q{fc-cache -fv});
    }

    if $s.get("install-audio") {
        add-chrooted-step("usermod -aG audio {$s.get('user-name')}")
    }
    
    if $s.get("install-cron") {
        add-chrooted-step(q{systemctl enable cronie});
    }
    
    if $s.get("enable-auditd") {
        add-chrooted-step(q{systemctl enable auditd});
    }

    if $s.get("install-pacman-core-tools") {
        add-chrooted-step(q{systemctl enable pkgfiled});
    }

    if $s.get("enable-fstrim") {
        add-chrooted-step(q{systemctl enable fstrim.timer});
    }

    if $s.get("install-logrotate") {
        add-chrooted-step(q{systemctl enable logrotate.timer});
    }

    if $s.get("install-firewalld") {
        add-chrooted-step(q{systemctl enable firewalld});
    }

    if $s.get("install-openssh") {
        add-chrooted-step(q{systemctl enable sshd});
        add-chrooted-step("su - {$s.get('user-name')} -c 'ssh-keygen -t ed25519 -N \"\" -f ~/.ssh/id_ed25519 -q'");
        add-chrooted-step("su - {$s.get('user-name')} -c 'touch ~/.ssh/authorized_keys'");
        add-chrooted-step("su - {$s.get('user-name')} -c 'chmod 600 ~/.ssh/authorized_keys'");
    }

    if $s.get("install-nvidia-prime") {
        add-chrooted-step(q{systemctl enable switcheroo-control});
    }

    if $s.get("install-terminal-utilities") {
        add-chrooted-step("su - {$s.get('user-name')} -c 'git lfs install'");
    }

    # see folders/etc/systemd/system/ditana-initialize-system.service and folders/usr/share/ditana/initialize-system-as-root.sh
    add-chrooted-step(q{systemctl enable ditana-initialize-system.service});
}

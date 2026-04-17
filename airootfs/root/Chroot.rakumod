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

my Str @additional-root-script-steps;

sub add-root-script-step(Str $line) is export {
    @additional-root-script-steps.push($line);
}

sub add-chrooted-step(Str $commands) is export {
    "bind-mount/root/installation-steps.sh".IO.spurt($commands.chomp ~ "\n", :append);
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
    my $s = Settings.instance;
    my @files = $s.get-files-for-enabled-settings;

    for @files -> $file {
        my $src = "%*ENV<HOME>/folders{$file}";
        my $dest = "/mnt{$file}";

        if $src.IO.e {
            my $dest-dir = $dest.IO.dirname;
            run-and-echo("mkdir", "-p", $dest-dir) unless $dest-dir.IO.d;
            run-and-echo("cp", "--preserve=mode,timestamps", $src, $dest);
            Logging.log("Copied $src to $dest");
        } else {
            die "File $src does not exist (required by settings)";
        }
    }
}

sub add-version() is export {
    my $os-release-path = '/mnt/usr/lib/os-release'.IO;
    die unless $os-release-path.e;
    my $build-id = %*ENV<DITANA_BUILD_ID>;
    if $build-id {
        $os-release-path.spurt("BUILD_ID={$build-id}\n", :append); # see `man os-release`
    }

    my $config-hash = %*ENV<DITANA_CONFIG_HASH>;
    if $config-hash && $config-hash ne "unknown" {
        $os-release-path.spurt("VERSION_CODENAME=$config-hash\n", :append);
    }
}

sub curate-chroot-files() is export {
    my $s = Settings.instance;

    '/etc/pacman.d/mirrorlist'.IO.copy('/mnt/etc/pacman.d/mirrorlist');
    '/mnt/etc/skel/.local/bin'.IO.mkdir;

    # https://wiki.archlinux.org/title/Installation_guide#Network_configuration
    '/mnt/etc/hostname'.IO.spurt($s.get('host-name') ~ "\n");

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
}

sub genfstab() is export {
    my $fstab = run-and-echo("genfstab", "-U", "/mnt").lines.grep(none(rx/«zfs»/)).join("\n");
    '/mnt/etc/fstab'.IO.spurt($fstab);
}

sub pacstrap() is export {
    my @native-packages = Settings.instance.get-installed-native-packages;
    Logging.echo(@native-packages.gist);

    # At this point, the system time is synchronized. We log the status here to include it in bug reports (should include "System clock synchronized: yes").
    run-and-echo("timedatectl", "status");
    
    # In case of an error, we retry once, in case the error was related to a temporary download issue
    run-and-echo("pacstrap", "-K", "/mnt", |@native-packages, :retry(2));

    # Remove cached package files to free disk space
    shell "rm -f /mnt/var/cache/pacman/pkg/*.pkg.tar.*";
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

sub add-early-chrooted-step(Str $commands) is export {
    "bind-mount/root/early-installation-steps.sh".IO.spurt($commands.chomp ~ "\n", :append);
}

sub generate-chroot-script() is export {
    "bind-mount/root/installation-steps.sh".IO.spurt("");  # clear file
    "bind-mount/root/early-installation-steps.sh".IO.spurt(""); # NEU: clear early file
    
    my $s = Settings.instance;
    
    for $s.get-early-chroot-script-steps -> $step {
        add-early-chrooted-step($step);
    }

    # Check if a package is available natively or in the AUR
    # This function is used as an alternative to pikaur -Si, which requires systemd (unavailable in chroot)
    add-chrooted-step(q:to/FUNC/.chomp);
    is_package_available() {
        local package_name="$1"
        if pacman -Si "$package_name" &>/dev/null; then
            echo -e "\033[32m--- ${package_name}: Available as native package ---\033[0m"
            return 0
        fi
        local aur_api_url="https://aur.archlinux.org/rpc/"
        local query_params="v=5&type=info&arg[]=${package_name}"
        if curl -s "${aur_api_url}?${query_params}" | jq -e '.resultcount > 0' >/dev/null; then
            echo -e "\033[32m--- ${package_name}: Available in AUR ---\033[0m"
            return 0
        else
            echo -e "\033[33m--- ${package_name}: Not available ---\033[0m"
            return 1
        fi
    }
    FUNC

    # Unconditional time configuration
    add-chrooted-step(q{echo -e "\033[32m--- Configuring time ---\033[0m"});
    add-chrooted-step("ln -sf '/usr/share/zoneinfo/{$s.get('timezone')}' /etc/localtime");
    add-chrooted-step("hwclock --systohc");

    # Locale generation
    add-chrooted-step(q{echo -e "\033[32m--- Generating locales ---\033[0m"});
    add-chrooted-step(q{locale-gen});

    # Append all chroot-script entries from enabled settings
    for $s.get-chroot-script-steps -> $step {
        add-chrooted-step($step);
    }

    # see folders/etc/systemd/system/ditana-initialize-system.service
    add-chrooted-step(q{systemctl enable ditana-initialize-system.service});
}

sub generate-root-script() is export {
    my $s = Settings.instance;
    my $script-path = '/mnt/usr/share/ditana/initialize-system-as-root.sh';

    my $header = q:to/END/;
    #!/usr/bin/env bash
    # This script is executed as a one-time service after the initial installation of the Ditana GNU/Linux distribution.
    # It is generated by the Ditana installer. See ditana-initialize-system.service.

    {
    END

    my $footer = q:to/END/;
    } 2>&1 | tee -a /var/log/install_ditana.log
    END

    my @steps = $s.get-root-script-steps;
    @steps.append(@additional-root-script-steps);

    my $body = @steps ?? @steps.join("\n") !! "true";

    $script-path.IO.dirname.IO.mkdir;
    $script-path.IO.spurt($header ~ $body ~ "\n" ~ $footer);
    $script-path.IO.chmod(0o755);
    Logging.log("Generated $script-path with {@steps.elems} steps");
}

sub get-session-setup-script-path returns Str {
    my $s = Settings.instance;
    my $mimeapps-path = $s.get("real-install")
        ?? "/mnt/usr/share/ditana/session-setup.sh"
        !! "/tmp/session-setup.sh";
}

sub generate-session-setup() is export {
    my $s = Settings.instance;
    my @scripts = $s.get-session-setups;

    # Generate /usr/share/ditana/session-setup.sh which sources all registered scripts
    my $setup-script-path = get-session-setup-script-path();
    my $setup-content = "#!/bin/bash\n";
    $setup-content ~= "# Generated by Ditana installer — sources session-setup scripts before the DE starts.\n\n";

    my @once-scripts;
    my @always-scripts;

    for @scripts -> $entry {
        my ($script, $once) = $entry ~~ Positional ?? @($entry) !! ($entry, False);
        if $once {
            @once-scripts.push($script);
        } else {
            @always-scripts.push($script);
        }
    }

    if @once-scripts {
        $setup-content ~= "if [ -f \"\$HOME/.config/ditana/trigger-first-login\" ]; then\n";
        for @once-scripts -> $script {
            $setup-content ~= "    [ -x \"$script\" ] && . \"$script\"\n";
        }
        $setup-content ~= "    rm -f \"\$HOME/.config/ditana/trigger-first-login\"\n";
        $setup-content ~= "fi\n";
    }

    for @always-scripts -> $script {
        $setup-content ~= "[ -x \"$script\" ] && . \"$script\"\n";
    }

    $setup-script-path.IO.dirname.IO.mkdir;
    $setup-script-path.IO.spurt($setup-content);
    $setup-script-path.IO.chmod(0o755);

    Logging.log("Generated session-wrapper with {@scripts.elems} session-setup scripts");
}

sub generate-session-setup-script() is export {
    my $s = Settings.instance;
    my @script-entries = $s.get-session-setup-scripts;
    return unless @script-entries;

    my $setup-script-path = get-session-setup-script-path();
    unless $setup-script-path.IO.e {
        die "session-setup.sh does not exist. "
          ~ "Call generate-session-setup before generate-session-setup-script.";
    }

    my @once-lines;
    my @always-lines;

    for @script-entries -> $entry {
        my ($lines, $once) = @($entry);
        if $once {
            @once-lines.append(@($lines));
        } else {
            @always-lines.append(@($lines));
        }
    }

    my $content = $setup-script-path.IO.slurp;

    if @once-lines {
        my $insertion = @once-lines.map({"    $_"}).join("\n") ~ "\n";
        my $marker = '    rm -f "$HOME/.config/ditana/trigger-first-login"';
        if $content.contains($marker) {
            $content = $content.subst($marker, $insertion ~ $marker);
        } else {
            # No existing first-login block — create one
            $content ~= "\nif [ -f \"\$HOME/.config/ditana/trigger-first-login\" ]; then\n";
            $content ~= $insertion;
            $content ~= "    rm -f \"\$HOME/.config/ditana/trigger-first-login\"\n";
            $content ~= "fi\n";
        }
    }

    if @always-lines {
        $content ~= @always-lines.map({"$_"}).join("\n") ~ "\n";
    }

    $setup-script-path.IO.spurt($content);
    Logging.log("Updated session-setup.sh with {@script-entries.elems} inline script block(s)");
}

sub generate-autostart-entries() is export {
    my $s = Settings.instance;
    my @entries = $s.get-autostart-entries;
    my $autostart-dir = $s.get("real-install")
        ?? '/mnt/etc/xdg/autostart'
        !! "/tmp/autostart";

    run-and-echo("mkdir", "-p", $autostart-dir) unless $autostart-dir.IO.d;

    for @entries -> $entry {
        my ($only-show-in, $script-path) = @($entry);
        my $basename = $script-path.IO.basename.subst(/\.sh$/, '');
        my $desktop-path = "$autostart-dir/ditana-{$basename}.desktop";

        my $content = "[Desktop Entry]\n";
        $content ~= "Type=Application\n";
        $content ~= "Exec=/bin/bash -c '$script-path'\n";
        $content ~= "Hidden=false\n";
        $content ~= "NoDisplay=true\n";
        $content ~= "X-GNOME-Autostart-enabled=true\n";
        $content ~= "Name=Ditana {$basename}\n";
        if $only-show-in && $only-show-in.chars > 0 {
            $content ~= "OnlyShowIn={$only-show-in}\n";
        }
        $content ~= "Terminal=false\n";

        $desktop-path.IO.spurt($content);
        Logging.log("Generated autostart entry: $desktop-path");
    }
}

sub patch-lightdm-conf() is export {
    my $conf = '/mnt/etc/lightdm/lightdm.conf';
    if $conf.IO.e {
        my $content = $conf.IO.slurp;

        # Set session-wrapper
        if $content !~~ /'session-wrapper=/usr/share/ditana/session-wrapper'/ {
            if $content ~~ /^^ '#'? \s* 'session-wrapper=' \N* $$/ {
                $content = $content.subst(
                    /^^ '#'? \s* 'session-wrapper=' \N* $$/,
                    'session-wrapper=/usr/share/ditana/session-wrapper'
                );
            } else {
                # Fallback (no existing session-wrapper entry)
                $content = $content.subst(
                    /^^ '[Seat:*]' $$/,
                    "[Seat:*]\nsession-wrapper=/usr/share/ditana/session-wrapper"
                );
            }
        }

        # Determine default session name
        my $s = Settings.instance;
        my $default-session;
        if $s.get("install-wayfire") {
            $default-session = "wayfire";
        } elsif $s.get("install-niri") {
            $default-session = "niri";
        } elsif $s.get("install-xfce") {
            $default-session = "xfce";
        }

        if $default-session {
            if $content ~~ /^^ '#'? \s* 'user-session=' \N* $$/ {
                $content = $content.subst(
                    /^^ '#'? \s* 'user-session=' \N* $$/,
                    "user-session=$default-session"
                );
            } else {
                $content = $content.subst(
                    /'session-wrapper=/usr/share/ditana/session-wrapper'/,
                    "session-wrapper=/usr/share/ditana/session-wrapper\nuser-session=$default-session"
                );
            }
        }

        # Set greeter
        if $content !~~ /'greeter-session=lightdm-slick-greeter'/ {
            if $content ~~ /^^ '#'? \s* 'greeter-session=' \N* $$/ {
                $content = $content.subst(
                    /^^ '#'? \s* 'greeter-session=' \N* $$/,
                    'greeter-session=lightdm-slick-greeter'
                );
            } else {
                # Fallback: No existing greeter-session entry
                $content = $content.subst(
                    /^^ '[Seat:*]' $$/,
                    "[Seat:*]\ngreeter-session=lightdm-slick-greeter"
                );
            }
        }

        $conf.IO.spurt($content);
    }
}

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
use RunAndLog;
use Settings;

sub add-repos-and-sync() is export {
    state $added-repos is default(False);
    return if $added-repos;
    $added-repos = True;
    return unless Settings.instance.get('real-install');
    
    my $s = Settings.instance;

    return unless $s.get('real-install');
    establish-internet-connection();

    show-dialog-raw('--infobox', "Downloading software information...", 4, 65);
    
    run-and-log 'pacman-key', '--init'; # initialize pacman keyring

    Logging.log("Configuring Arch multilib repository");
    run-and-log 's6', 
        '--task-run', 
        "%*ENV<HOME>/bind-mount/root/sparrow/tasks/pacman\@enable_multilib={$s.get('enable-multilib') ?? 'y' !! 'n' }";

    if $s.get('enable-chaotic-aur') {
        run-and-log "%*ENV<HOME>/bind-mount/root/enable-chaotic-aur.sh", 'y';
    }

    Logging.log("Enabling the Ditana repository");
    run-and-log "%*ENV<HOME>/bind-mount/root/enable-ditana.sh";

    Logging.log("Signing Ditana repository");
    run-and-log "%*ENV<HOME>/bind-mount/root/sign-ditana.sh";

    Logging.log("Syncing new repositories");
    run-and-log 'pacman', '-Sy';
}

sub update-keyring is export {
    # Update the Live ISO’s archlinux-keyring package before running pacstrap
    # This ensures the keyring contains all current Arch Linux packager keys
    # Without this update, packages signed by recently added packagers may fail verification
    show-dialog-raw('--infobox', "Loading security certificates...", 4, 65);
    run-and-log("pacman", "-Sy", "--noconfirm", "archlinux-keyring");
}

sub update-mirrorlist is export {
    # Update the Live ISO's pacman mirrorlist to use its latest version, rather than the one from ISO build time
    show-dialog-raw('--infobox', "Finding download servers...", 4, 65);
    run-and-log("pacman", "-Sy", "--noconfirm", "pacman-mirrorlist");
    
    # Use the updated mirrorlist if pacnew was created
    my $pacnew = "/etc/pacman.d/mirrorlist.pacnew".IO;
    if $pacnew.e {
        $pacnew.move("/etc/pacman.d/mirrorlist");
    }
}

sub adjust-mtu-if-needed() is export {
    return unless Settings.instance.get('real-install');

    show-dialog-raw('--infobox', "Checking network configuration...", 4, 65);

    my $ip-route-output = run-and-log('ip', '-j', 'route', 'get', '8.8.8.8');
    my $ip-route = from-json($ip-route-output);
    my $interface = $ip-route[0]<dev> // '';

    return unless $interface.chars > 0;

    my $proc = run('curl', '-s', '--connect-timeout', '10', '--fail', 'https://archlinux.org/mirrors/status/json/', :out(False), :err(False));
    my $curl-test = $proc.exitcode;

    if $curl-test != 0 {
        Logging.log("Curl failed - adjusting MTU on $interface to 1400");
        run-and-log('ip', 'link', 'set', 'dev', $interface, 'mtu', '1400');

        my $max-tries = 10;
        my $success = False;
        for 1..$max-tries {
            sleep 1;
            my $retry-proc = run('curl', '-s', '--connect-timeout', '10', '--fail', 'https://archlinux.org/mirrors/status/json/', :out(False), :err(False));
            if $retry-proc.exitcode == 0 {
                Logging.log("Curl now works after MTU adjustment (try $_)");
                $success = True;
                last;
            }
            Logging.log("Curl retry failed (try $_) - waiting...");
        }
        unless $success {
            Logging.log("Warning: Curl still fails after $max-tries tries - proceeding anyway");
        }
    } else {
        Logging.log("Curl works - no MTU adjustment needed");
    }
}

sub rate-mirrors() is export {
    show-dialog-raw('--infobox', "Checking server speeds...", 4, 65);
    run-and-log "rate-mirrors", "--allow-root", "--save=/etc/pacman.d/mirrorlist", "arch"
}

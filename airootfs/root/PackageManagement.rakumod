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

    show-dialog-raw('--infobox', "Reading information from online package repositories...", 4, 65);
    
    run-and-log 'pacman-key', '--init'; # initialize pacman keyring

    if $s.get('enable-multilib') {
        Logging.log("Enabling Arch multilib repository");
        run-and-log 's6', 
            '--task-run', 
            "%*ENV<HOME>/bind-mount/root/sparrow/tasks/pacman" ~
            '@action=enable-arch-multilib-repo,' ~
            "enable_multilib={$s.get('enable-multilib')}";
    }

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

sub rate-mirrors() is export {
    Logging.log("Finding fastest Arch mirrors");
    run-and-echo "rate-mirrors", "--allow-root", "--save=/etc/pacman.d/mirrorlist", "arch"
}

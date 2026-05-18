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

class Logging {
    my Logging $instance;
    method new {!!!}
    submethod instance {
        $instance = Logging.bless unless $instance;
        $instance;
    }

    submethod TWEAK {
        my $logfile = $*USER eq 'root'
            ?? "%*ENV<HOME>/folders/var/log/install_ditana.log".IO
            !! "/tmp/install_ditana.log".IO;

        if $logfile.e {
            if '/tmp/ditana-set-font.sh'.IO.f {
                $logfile.spurt("=== set-font-hook exists, continuing installation log upon restart of installation ===\n", :append);
            } else {
                $logfile.unlink;
            }
        }
    }

    method log(::?CLASS:U: $message) {
        self.instance!log-internal($message, status=>False, echo=>False, warn=>False);
    }

    method status(::?CLASS:U: $message) {
        self.instance!log-internal($message, status=>True, echo=>False, warn=>False);
    }

    method echo(::?CLASS:U: $message) {
        self.instance!log-internal($message, status=>False, echo=>True, warn=>False);
    }

    method echo-nocolor(::?CLASS:U: $message) {
        self.instance!log-internal($message, status=>False, echo=>True, warn=>False, note=>False);
    }

    method echo-error(::?CLASS:U: $message) {
        self.instance!log-internal($message, status=>False, echo=>True, warn=>True);
    }

    method warn(::?CLASS:U: $message) {
        self.instance!log-internal($message, status=>False, echo=>True, warn=>True);
    }

    method !log-internal($message, :$status, :$echo, :$warn, :$note=True) {
        my $logfile;
        
        if $*USER eq 'root' {
            $logfile = "/mnt/var/log/install_ditana.log".IO; # after pacstrap, see copy-files-into-chroot-after-pacstrap()

            unless $logfile.e {
                $logfile = "%*ENV<HOME>/folders/var/log/install_ditana.log".IO;
                $logfile.parent.mkdir;
            }
        } else {
            # simulation mode
            $logfile = "/tmp/install_ditana.log".IO;
        }
        
        my $fh = $logfile.open(:a) or die "Cannot open logfile $_: $!";
        $fh.say("{DateTime.now.Str}\t$message");
        $fh.close;

        if $status && %*ENV<TMUX> {
            my $color = $warn ?? "orange" !! "white";
            qqx{tmux set -g "status-format[0]" "#[align=centre,fg=$color,bg=black] $message"};
        }

        if $echo {
            $warn ?? note "\e[33m$message\e[0m" !!
            $note ?? note "\e[32m$message\e[0m" !! note $message;
        }
    }
}

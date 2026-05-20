#!/usr/bin/env raku

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
use lib ".";
use AskForSetting;
use AskForYesNo;
use Chroot;
use Desktop;
use Dialogs;
use Flatpak;
use Font;
use Hostname;
use Internet;
use Kernel;
use Keymap;
use Locale;
use Logging;
use MimeApps;
use Mount;
use Nvidia;
use NvmeFormat;
use PackageManagement;
use Partition;
use RunAndLog;
use SelectDisk;
use SelectSwapSize;
use Settings;
use Summary;
use Timezone;
use Uefi;
use Welcome;

my $log-on-screen = False;

sub switch-on-logging {
    shell q{clear};
    $log-on-screen = True;
}

sub reboot {
    run-and-echo('systemctl', 'reboot');
}

my %dispatch = MY::.pairs.grep(*.key.starts-with('&')).map({ .key.substr(1) => .value });

sub process-categories($dialog, $previous-dialog-name, $current-dialog-name) returns Int {
    my $selected-category;
    repeat {
        if Settings.instance.get('tmux') {
            qqx{tmux set -g "status-format[0]" "#[align=left,fg=white,bg=black] $previous-dialog-name ← <Back> #[align=centre,bg=black,fg=#39c5cf]●#[fg=white] $current-dialog-name #[align=right,fg=#21262d,bg=#21262d] $previous-dialog-name ← <Back> "};
        }
        $selected-category = configure-and-show-dialog($dialog);

        if $selected-category.chars > 0 {
            my $selected-dialog = @($dialog<categories>).first(*<name> eq $selected-category);

            if $selected-dialog {
                my $selected-dialog-name = kebab-to-title($selected-dialog<name>);
                given $selected-dialog<type> {
                    when 'categories' {
                        process-categories($selected-dialog, $current-dialog-name, $selected-dialog-name);
                    }
                    when 'checklist'|'radiolist' {
                        if Settings.instance.get('tmux') {
                            qqx{tmux set -g "status-format[0]" "#[align=left,fg=white,bg=black] $current-dialog-name ← <Back> #[align=centre,bg=black,fg=#39c5cf]●#[fg=white] $selected-dialog-name #[align=right,fg=#21262d,bg=#21262d] $current-dialog-name ← <Back> "};
                        }
                        configure-and-show-dialog($selected-dialog);
                    }
                    when 'ask-for-setting' {
                        if Settings.instance.get('tmux') {
                            qqx{tmux set -g "status-format[0]" "#[align=left,fg=white,bg=black] $current-dialog-name ← <Back> #[align=centre,bg=black,fg=#39c5cf]●#[fg=white] $selected-dialog-name #[align=right,fg=#21262d,bg=#21262d] $current-dialog-name ← <Back> "};
                        }
                        ask-for-setting($selected-dialog);
                    }
                    when 'ask-for-yes-no' {
                        if Settings.instance.get('tmux') {
                            qqx{tmux set -g "status-format[0]" "#[align=left,fg=white,bg=black] $current-dialog-name ← <Back> #[align=centre,bg=black,fg=#39c5cf]●#[fg=white] $selected-dialog-name #[align=right,fg=#21262d,bg=#21262d] $current-dialog-name ← <Back> "};
                        }
                        ask-for-yes-no($selected-dialog);
                    }
                    when 'procedure' {
                        my $name = $selected-dialog<name>;
                        if $name eq 'review-summary-and-start-installation' {
                            if review-summary() == 0 {
                                return 0
                            }
                        } elsif %dispatch{$name}:exists {
                            my &proc := %dispatch{$name};
                            if &proc.arity > 0 {
                                &proc(0);
                            } elsif &proc.returns ~~ Int {
                                &proc();
                            } else {
                                &proc();
                            }
                        } else {
                            die "No procedure found for '$name'";
                        }
                    }
                    default {
                        die "Unknown dialog type: {$selected-dialog<type>}";
                    }
                }
            }
        }
    } while $selected-category.chars > 0;

    return 0xff;
}

sub is-dialog($installation-step) {
    die "Type of $installation-step<name> is undefined." unless $installation-step<type>.defined;
    $installation-step<type> ne "procedure";
}

sub find-dialog-name($current-index, &index-modifier) {
    my @installation-steps = Settings.get-installation-steps;

    my $modified-index = &index-modifier($current-index);
    return "" unless $modified-index ∈ 0..^@installation-steps.elems;
    my $installation-step = @installation-steps[$modified-index];

    if is-dialog($installation-step) {
        if $installation-step<name> !~~ Str {
            Logging.log("------------ ERROR ------------");
            Logging.log("Index: $modified-index");
            Logging.log("max index+1: {@installation-steps.elems}");
            Logging.log("------------- ERROR ------------");
        }
        return kebab-to-title($installation-step<name>)
    } elsif $modified-index ≠ $current-index {
        return find-dialog-name($modified-index, &index-modifier)
    } else {
        return kebab-to-title($installation-step<name>);
    }
}

sub process-installation-step($installation-step, $current-index, $silent-exit-code) returns Int {
    my @installation-steps = Settings.get-installation-steps;
    my $current-dialog-name  = find-dialog-name($current-index, -> $i { $i });
    my $previous-dialog-name = find-dialog-name($current-index, -> $i { $i - 1 });
    my $next-dialog-name     = find-dialog-name($current-index, -> $i { $i + 1 });

    my $log-entry = "Processing '$current-dialog-name'...";
    if $log-on-screen {
        Logging.echo($log-entry);

        if Settings.instance.get('tmux') {
            qqx{tmux set -g "status-format[0]" "#[align=centre,bg=black,fg=#39c5cf]●#[fg=white] $current-dialog-name "}
        }
    } else {
        Logging.log($log-entry);

        if Settings.instance.get('tmux') {
            if $current-index > 0 {
                if $current-index < @installation-steps.elems-1 {
                    qqx{tmux set -g "status-format[0]" "#[align=left,fg=white,bg=black] $previous-dialog-name ← <Back> #[align=centre,bg=black,fg=#39c5cf]●#[fg=white] $current-dialog-name #[align=right,fg=white,bg=black] <Next> → $next-dialog-name "}
                }
                else
                {
                    qqx{tmux set -g "status-format[0]" "#[align=left,fg=white,bg=black] $previous-dialog-name ← <Back> #[align=centre,bg=black,fg=#39c5cf]●#[fg=white] $current-dialog-name #[align=right,fg=#21262d,bg=#21262d] $previous-dialog-name ← <Back> "}
                }
            } elsif $current-index < @installation-steps.elems-1 {
                qqx{tmux set -g "status-format[0]" "#[align=centre,bg=black,fg=#39c5cf]●#[fg=white] $current-dialog-name #[align=right,fg=white,bg=black] <Next> → $next-dialog-name"}
            }
        }
    }

    my $result=$silent-exit-code;

    given $installation-step<type> {
        when 'categories' {
            $result = process-categories($installation-step, $previous-dialog-name, $current-dialog-name);
        }
        when 'checklist'|'radiolist' {
            $result = configure-and-show-dialog($installation-step);
        }
        when 'ask-for-setting' {
            $result = ask-for-setting($installation-step);
        }
        when 'ask-for-yes-no' {
            $result = ask-for-yes-no($installation-step)
        }
        when 'procedure' {
            my $name = $installation-step<name>;
            die "No procedure found for '$name'" unless %dispatch{$name}:exists;
            my &proc := %dispatch{$name};
            if &proc.arity > 0 {
                $result = &proc($silent-exit-code);
            } elsif &proc.returns ~~ Int {
                $result = &proc();
            } else {
                &proc();
            }
        }
        default {
            die "Unknown installation step type: {$installation-step<type>}";
        }
    }

    $result;
}

sub debug-info() {
    my $debug-info = "Please create a GitHub issue on https://github.com/acrion/ditana-installer or write an email to support@ditana.org and attach the log file install_ditana.log. To retrieve this file from another machine, execute /root/folders/usr/lib/ditana/create-debug-user on this machine and follow the instructions. Thank you!";

    say $debug-info;
    Logging.log($debug-info);
}

# Setup procedures (those whose dispatch function takes no arguments and
# does not declare `returns Int`) perform one-time configuration: pacman
# sync, keyring update, mirror rating, swap default, etc. They must run
# at most once per installer session, regardless of how often the user
# navigates back and forward across them. Interactive procedures (which
# take $silent-exit-code or return Int) remain re-entrant.
my %setup-procedure-ran;

sub is-setup-procedure($installation-step --> Bool) {
    return False unless $installation-step<type> eq 'procedure';
    my $name = $installation-step<name>;
    return False unless %dispatch{$name}:exists;
    my &proc := %dispatch{$name};
    return &proc.arity == 0 && &proc.returns !~~ Int;
}

sub main() {
    if !'/tmp/ditana-set-font.sh'.IO.e {
        welcome();

        show-dialog-raw('--infobox', "Checking Internet Connection...", 4, 65);
        establish-internet-connection();

        show-dialog-raw('--infobox', "Downloading Installer Configuration...", 4, 65);

        my $config-dir = $*PROGRAM.parent;
        my $config-archive = $config-dir.child('ditana-config.tar.gz');

        my $branch = 'main';
        if $*USER eq 'root' {
            $branch = %*ENV<DITANA_BRANCH> // 'main';
        } else {
            my $git = run('git', 'rev-parse', '--abbrev-ref', 'HEAD', :out, :err);
            $branch = $git.exitcode == 0 ?? $git.out.slurp(:close).trim !! 'main';
            Logging.log("Simulation mode: detected Git branch '$branch'");
        }

        my $config-tag = $branch eq 'main' ?? 'latest' !! 'develop-latest';
        my $config-url = "https://github.com/acrion/ditana-config/releases/download/$config-tag/ditana-config.tar.gz";

        my $download = run('curl', '-fsSL', $config-url, '-o', '/tmp/ditana-config.tar.gz', :out, :err);
        if $download.exitcode == 0 {
            copy('/tmp/ditana-config.tar.gz', $config-archive);
            unlink '/tmp/ditana-config.tar.gz';
            Logging.log("Downloaded $config-tag configuration from GitHub.");
        } else {
            Logging.log("Using bundled configuration (download failed).");
        }

        run('tar', 'xzf', $config-archive, '--exclude=json-kdl-converter', '-C', $config-dir);

        my $config-hash = "unknown";
        my $hash-file = $config-dir.child('config_hash.txt');
        if $hash-file.e {
            $config-hash = $hash-file.slurp(:close).trim;
        }

        my $config-date = "unknown";
        my $date-file = $config-dir.child('config_date.txt');
        if $date-file.e {
            $config-date = $date-file.slurp(:close).trim;
        }

        my $lsb-release = $config-dir.child('folders/etc/lsb-release');
        if $lsb-release.e {
            $lsb-release.spurt("DISTRIB_CODENAME=$config-hash\n", :append);
        }

        %*ENV<DITANA_CONFIG_HASH> = $config-hash;
        Logging.log("Loaded configuration state: $config-hash ($config-date)");

        my $msg = qq:to/END/.chomp;

The logic and configuration of this installer are decoupled from the ISO image. Instead, the installer dynamically downloads the most up-to-date configuration from our repository at runtime.

This ensures you always benefit from the latest improvements and bug fixes without needing to download a new ISO.

The currently loaded configuration state is:
Commit Hash: $config-hash
Timestamp:   $config-date

This unique identifier is saved in your installed system and can be queried later using the 'lsb_release -cs' command.
END
        show-dialog-raw('--title', 'Installer Configuration', '--msgbox', $msg, 19, 75);
        show-dialog-raw('--title', 'Ditana GNU/Linux Installer', '--infobox', "\nDetecting Hardware...", 10, 50);
    }

    if Settings.instance.get('tmux') {
        qx{tmux set -g status-position top};
        qx{tmux set -g status-style "bg=#21262d,fg=#e6edf3"};
    }

    my @installation-steps = Settings.get-installation-steps;
    my $current-index = 0;

    # The dialog exit codes are used to control the navigation within the installation
    # wizard. If the user clicks «Cancel» or presses «Esc», the wizard navigates back
    # to the previous step. An installation step returns $silent-exit-code when it
    # silently performs automatic actions without displaying a dialog due to its
    # internal logic. The specific use of '$silent-exit-code' ensures that the wizard
    # handles navigation correctly, avoiding unintended loops and maintaining
    # consistent behavior whether the user moves forward or backward.
    my $silent-exit-code=0;

    while $current-index < @installation-steps.elems {
        my $installation-step = @installation-steps[$current-index];
        my $name = $installation-step<name>;

        # Skip setup procedures that have already run in this session. This
        # makes them idempotent across the entire navigation graph: forward
        # re-entry after a Back-Then-Forward sequence as well as direct
        # backward traversal. Interactive procedures (those whose dispatch
        # function takes $silent-exit-code or returns Int) are never marked
        # here and remain re-entrant in both directions, so dialogs like
        # `choose-region-or-timezone` or `select-disk` stay reachable when
        # the user navigates back through them.
        if %setup-procedure-ran{$name} {
            Logging.log("Skipping already-executed setup procedure '$name'");
            $current-index = $silent-exit-code == 0
                ?? $current-index + 1
                !! ($current-index > 0 ?? $current-index - 1 !! 0);
            next;
        }

        my $result = Settings.instance.installation-step-is-available($name)
            ?? process-installation-step($installation-step, $current-index, $silent-exit-code)
            !! $silent-exit-code;

        given $result {
            when 0 { # OK / Proceed
                # Record a successful forward pass through a setup procedure
                # so that any future visit (forward or backward) skips it.
                if is-setup-procedure($installation-step) {
                    %setup-procedure-ran{$name} = True;
                }
                $current-index++;
                $silent-exit-code = 0;
            }
            when 0xff | 1 { # Escape or Cancel
                $current-index = $current-index > 0 ?? $current-index - 1 !! 0;
                $silent-exit-code = 1;
            }
        }
    }
}

main();
CATCH {
    Logging.log($_);
    debug-info();
}

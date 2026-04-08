#!/usr/bin/env raku

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
use lib ".";
use AskForSetting;
use AskForYesNo;
use Chroot;
use Desktop;
use Dialogs;
use Font;
use Kernel;
use Keyboard;
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

my $log-on-screen = False;

sub process-categories($dialog, $previous-dialog-name, $current-dialog-name) {
    my $selected-category;
    repeat {
        if Settings.instance.get('tmux') {
            qqx{tmux set -g "status-format[0]" "#[align=left,fg=white,bg=black] $previous-dialog-name ← <Back> #[align=centre,fg=white,bg=black] $current-dialog-name #[align=right,fg=green,bg=green] $previous-dialog-name ← <Back> "};
        }
        $selected-category = configure-and-show-dialog($dialog);
        
        if $selected-category.chars > 0 {
            my $selected-dialog = @($dialog<categories>).first(*<name> eq $selected-category);
            
            if $selected-dialog {
                my $selected-dialog-name = kebab-to-title($selected-dialog<name>);
                given $selected-dialog<type> {
                    when 'categories' {
                        return process-categories($selected-dialog, $current-dialog-name, $selected-dialog-name)==0xff ?? 3 !! 0;
                    }
                    when 'checklist'|'radiolist' {
                        if Settings.instance.get('tmux') {
                            qqx{tmux set -g "status-format[0]" "#[align=left,fg=white,bg=black] $current-dialog-name ← <Back> #[align=centre,fg=white,bg=black] $selected-dialog-name #[align=right,fg=green,bg=green] $current-dialog-name ← <Back> "};
                        }
                        configure-and-show-dialog($selected-dialog);
                    }
                    when 'procedure' {
                        given $selected-dialog<name> {
                            when 'review-summary-and-start-installation' {
                                if review-summary() == 0 {
                                    shell q{clear};
                                    $log-on-screen = True;
                                    return 0 # start installation
                                }
                            }
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
            qqx{tmux set -g "status-format[0]" "#[align=centre,fg=white,bg=black] $current-dialog-name "}
        }
    } else {
        Logging.log($log-entry);

        if Settings.instance.get('tmux') {
            if $current-index > 0 {
                if $current-index < @installation-steps.elems-1 {
                    qqx{tmux set -g "status-format[0]" "#[align=left,fg=white,bg=black] $previous-dialog-name ← <Back> #[align=centre,fg=white,bg=black] $current-dialog-name #[align=right,fg=white,bg=black] <Next> → $next-dialog-name "}
                }
                else
                {
                    qqx{tmux set -g "status-format[0]" "#[align=left,fg=white,bg=black] $previous-dialog-name ← <Back> #[align=centre,fg=white,bg=black] $current-dialog-name #[align=right,fg=green,bg=green] $previous-dialog-name ← <Back> "}
                }
            } elsif $current-index < @installation-steps.elems-1 {
                qqx{tmux set -g "status-format[0]" "#[align=centre,fg=white,bg=black] $current-dialog-name #[align=right,fg=white,bg=black] <Next> → $next-dialog-name"}
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
            given $installation-step<name> {
                when 'welcome' {
                    $result = '/tmp/ditana-set-font.sh'.IO.f
                        ?? $silent-exit-code
                        !! show-dialog-raw(
                            '--no-collapse',
                            '--msgbox',
                            $installation-step<text>.subst(q{$version},%*ENV<DITANA_VERSION>//""),
                            $installation-step<text>.lines+4,
                            98
                           )<status>;
                }
                when 'update-terminal-font' {
                    $result = update-terminal-font($silent-exit-code);
                }
                when 'keymap-layout' {
                    $result = choose-keymap-layout();
                }
                when 'keymap-variant' {
                    $result = choose-keymap-variant($silent-exit-code);
                }
                when 'set-keymap-and-delay-rate' {
                    $result = set-keymap-and-delay-rate($silent-exit-code);
                }
                when 'test-keymap' {
                    $result = test-keymap();
                }
                when 'choose-region-or-timezone' {
                    $result = choose-region-or-timezone();
                }
                when 'choose-specific-timezone' {
                    $result = choose-specific-timezone($silent-exit-code);
                }
                when 'choose-main-locale' {
                    $result = choose-main-locale();
                }
                when 'choose-sub-locale' {
                    $result = choose-sub-locale();
                }
                when 'select-disk' {
                    $result = select-disk();
                }
                when 'check_efi' {
                    $result = check_efi($silent-exit-code);
                }
                when 'confirm-nvme-format' {
                    $result = confirm-nvme-format($silent-exit-code);
                }
                when 'select-swap-size' {
                    $result = select-swap-size();
                }
                when 'add-repos-and-sync' {
                    add-repos-and-sync();
                }
                when 'adjust-mtu-if-needed' {
                    adjust-mtu-if-needed();
                }
                when 'update-keyring' {
                    update-keyring();
                }
                when 'update-mirrorlist' {
                    update-mirrorlist();
                }
                when 'rate-mirrors' {
                    rate-mirrors();
                }
                when 'check-nvidia' {
                    $result = check-nvidia($silent-exit-code, False);
                }
                # here follows the configuration menu, see settings.json
                when 'format-nvme' {
                    format-nvme();
                }
                when 'partition-drive' {
                    partition-drive();
                }
                when 'create-kernel-configuration' {
                    create-kernel-configuration();
                }
                when 'mount-bootimage-partition' {
                    mount-bootimage-partition();
                }
                when 'mount-bootloader-partition' {
                    mount-bootloader-partition();
                }
                when 'enable-swap-partition' {
                    enable-swap-partition();
                }
                when 'set-host-dpi' {
                    set-host-dpi();
                }
                when 'configure-bind-mounts' {
                    configure-bind-mounts();
                }
                when 'copy-files-into-chroot-before-pacstrap' {
                    copy-files-into-chroot-before-pacstrap();
                }
                when 'add-version' {
                    add-version();
                }
                when 'pacstrap' {
                    pacstrap();
                }
                when 'copy-files-into-chroot-after-pacstrap' {
                    copy-files-into-chroot-after-pacstrap();
                }
                when 'apply-locale' {
                    apply-locale();
                }
                when 'copy-console-keyboard-configuration' {
                    copy-console-keyboard-configuration();
                }
                when 'copy-xorg-keyboard-configuration' {
                    copy-xorg-keyboard-configuration();
                }
                when 'configure-terminal-font' {
                    configure-terminal-font();
                }
                when 'create-xfce-keyboard-xml' {
                    create-xfce-keyboard-xml();
                }
                when 'create-keyboard-service' {
                    create-keyboard-service();
                }
                when 'create-hostid' {
                    create-hostid();
                }
                when 'genfstab' {
                    genfstab();
                }
                when 'curate-chroot-files' {
                    curate-chroot-files();
                }
                when 'create-mimeapps-list' {
                    create-mimeapps-list();
                }
                when 'generate-aur-package-installation-script' {
                    generate-aur-package-installation-script();
                }
                when 'generate-chroot-script' {
                    generate-chroot-script();
                }
                when 'generate-root-script' {
                    generate-root-script();
                }
                when 'generate-session-setup' {
                    generate-session-setup();
                }
                when 'generate-session-setup-script' {
                    generate-session-setup-script();
                }
                when 'generate-autostart-entries' {
                    generate-autostart-entries();
                }
                when 'patch-lightdm-conf' {
                    patch-lightdm-conf();
                }
                when 'generate-chroot-settings-file' {
                    generate-chroot-settings-file();
                }
                when 'chroot-installation' {
                    chroot-installation();
                }
                when 'cleanup-mounts' {
                    cleanup-mounts();
                }
                when 'reboot' {
                    run-and-echo('systemctl', 'reboot');
                }
            }
            
        }
        default {
            die "Unknown installation step type: {$installation-step<type>}";
        }
    }

    $result;
}

sub debug-info() {

    my $debug-info = "Please create a GitHub issue on https://github.com/acrion/ditana-installer or write an email to support@ditana.org and attach the log file install_ditana.log. To retrieve this file from another machine, execute /root/folders/usr/share/ditana/create-debug-user.sh on this machine and follow the instructions. Thank you!";

    say $debug-info;
    Logging.log($debug-info);
}

sub main() {
    show-dialog-raw('--title', 'Ditana GNU/Linux Installer', "--infobox", "\nDetecting Hardware...", 10, 50);

    if Settings.instance.get('tmux') {
        qx{tmux set -g status-position top};
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
        my $result = Settings.instance.installation-step-is-available($installation-step<name>)
            ?? process-installation-step($installation-step,$current-index,$silent-exit-code)
            !! $silent-exit-code;
        
        given $result {
            when 0 { # OK / Proceed
                $current-index++;
                $silent-exit-code=0
            }
            when 3 { # return from sub-category-selection, see process-categories
                $silent-exit-code=1
            }
            when 0xff | 1 { # Escape or Cancel
                $current-index = $current-index > 0 ?? $current-index - 1 !! 0;
                $silent-exit-code=1
            }
        }
    }
}

main();
CATCH {
    Logging.log($_);
    debug-info();
}

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
use Chroot;
use Dialogs;
use Logging;
use RunAndLog;

my $simulate-no-internet = False;
my $simulate-no-wifi-devices = False;
my $simulate-no-networks = False;

sub connected-to-internet() returns Bool {
    if $simulate-no-internet {
        Logging.log("No internet connection ditana.org and kernel.org (simulated)");
        return False;
    }

    if run('curl', '-s', '--head', '--fail', 'https://ditana.org', :err(False), :out(False)).exitcode == 0 {
        Logging.log("Verified internet connection to ditana.org");
        return True;
    }

    if run('curl', '-s', '--head', '--fail', 'https://kernel.org', :err(False), :out(False)).exitcode == 0 {
        Logging.log("Verified internet connection to kernel.org");
        return True;
    }

    Logging.log("No internet connection ditana.org and kernel.org");
    return False;
}

sub choose-wifi-device() {
    show-and-log-status "Getting list of Wi-Fi devices and states...";

    if $simulate-no-wifi-devices {
        show-and-log-status "List of Wi-Fi devices is empty (simulated).";
        return { status => 2 };
    }

    my $devices-output = run-and-log('iwctl', 'device', 'list');

    my @menu-options;
    my @devices = $devices-output.lines
        .skip(4)  # skip the first four header lines
        .map(-> $line {
            $line.subst(rx/ \x1b \[ <[0..9;]>* m /, '', :g) # Remove color codes
                 .trim # Trim whitespace
        })
        .grep(*.chars);  # ignore empty lines

    Logging.log("Raw device lines: {@devices.gist}");

    @devices = @devices.map(-> $line {
        my @parts = $line.words;
        Logging.log("Line parts: {@parts.gist}");
        [$line.words[0], $line.words[2]]
    });

    Logging.log("Processed devices: {@devices.gist}");

    unless @devices {
        show-and-log-status "List of Wi-Fi devices is empty.";
        return { status => 2 };
    }

    # Build the menu options
    for @devices -> $device {
        my ($name, $status) = $device;
        Logging.log("Added device: $name, $status");
        @menu-options.append($name, $status);
    }

    Logging.log("Menu-options: {@menu-options}");

    Logging.log("Available Wi-Fi devices: {@menu-options.join(' ')}");

    # Display dialog and allow user to make a choice
    return show-dialog-raw(
        '--title', 'Internet Connection',
        '--menu', '\nSelect a Wi-Fi device:',
        17, 50, 10,
        |@menu-options
    );
}

sub choose-ssid(Str $device-name) {
    show-and-log-status "Getting network list from device $device-name...";

    if $simulate-no-networks {
        show-and-log-status "Network list is empty (simulated).";
        return { status => 2 };
    }

    # Get network list from iwctl and process its output
    # We need to:
    # 1. Skip ANSI color codes
    # 2. Remove leading spaces and '>'
    # 3. Extract network names (first 34 chars of each line)
    my $networks-output = run-and-log('iwctl', 'station', $device-name, 'get-networks');

    # Process the output, skipping header lines and empty lines
    my @ssids = $networks-output.lines
        .skip(4)  # Skip header lines
        .map(-> $line {
            # Remove ANSI color codes and leading spaces/'>',
            # then take first 34 chars and trim
            $line.subst(rx/ \x1b \[ <[0..9;]>* m /, '', :g) # Remove color codes
                 .subst(rx/^ <[\s>]>* /, '') # Remove leading spaces and '>'
                 .substr(0, 34)             # Take first 34 chars
                 .trim                      # Trim whitespace
        })
        .grep(*.chars);  # Filter out empty lines

    unless @ssids {
        show-and-log-status "Network list is empty.";
        return { status => 2 };
    }

    # Build menu options with numbered entries
    my @menu-options;
    for @ssids.kv -> $idx, $ssid {
        @menu-options.append($ssid, ($idx + 1).Str);
    }

    # Show dialog for network selection
    return show-dialog-raw(
        '--title', 'Select Network',
        '--menu', '\nSelect a Wi-Fi network:',
        30, 50, 10,
        |@menu-options
    );
}

sub establish-internet-connection() is export {
    # Main loop - continues until internet connection is established
    while !connected-to-internet() {
        my %device-name = choose-wifi-device();
        Logging.log("Return code of choose-wifi-device: {%device-name<status>}");

        if %device-name<status> != 0 {
            if %device-name<status> == 2 {
                show-dialog-raw(
                    '--msgbox',
                    "No Internet connection and no Wi-Fi devices.\n\nIf you have a built-in Wi-Fi device, you may need to turn it on with a hard key or keyboard combination. Otherwise, connect a LAN cable. Confirm to check again.",
                    10, 50
                );
            }
        } else {
            # Inner loop for network selection and connection attempts
            loop {
                show-dialog-raw(
                    '--title', 'Ditana Installer',
                    '--infobox', "\nScanning Wi-Fi networks with device {%device-name<value>}...",
                    10, 50
                );

                run('iwctl', 'station', %device-name<value>, 'scan', :out(False), :err(False));
                my %ssid = choose-ssid(%device-name<value>);

                if %ssid<status> == 2 {
                    run('iwctl', 'station', %device-name<value>, 'scan', :out(False), :err(False));

                    my %result = show-dialog-raw(
                        '--msgbox',
                        "No Wi-Fi networks found.\n\nConfirm to select a different device (or press the 'Escape' key to repeat the scan with the device you selected).",
                        9, 43
                    );

                    if %result<status> == 0 {
                        Logging.log("User confirmed choose different device, because no networks were found. Proceeding with device selection");
                        last;
                    }
                    Logging.log("User pressed Escape key to repeat scan, because no networks were found.");
                }
                elsif %ssid<status> != 0 {
                    Logging.log("User canceled ssid selection, proceeding with device selection.");
                    last;
                } else {
                    Logging.log("User selected ssid, now get password.");
                    my $ssid = %ssid<value>;
                    my $ssid-passphrase = qqx{dialog --stdout --insecure --passwordbox "Please enter the password for Wi-Fi '$ssid'" 10 50};

                    if $ssid-passphrase {
                        show-dialog-raw(
                            '--title', 'Ditana Installer',
                            '--infobox', "\nConnecting to Wi-Fi network '$ssid' with device '{%device-name<value>}'...",
                            10, 50
                        );

                        if run('iwctl', '--passphrase', $ssid-passphrase, 'station', %device-name<value>, 'connect', $ssid, :err(False), :out(False)).exitcode == 0 {
                            my $timeout = 10;
                            while $timeout >= 0 {
                                if connected-to-internet() {
                                    last;
                                }
                                sleep 1;
                                $timeout--;
                            }

                            if $timeout < 0 {
                                Logging.log("Wi-Fi password was correct, but internet connection failed.");
                                show-dialog-raw('--msgbox', 'Password was correct, but internet connection failed.', 10, 50);
                            }
                            else {
                                # The temporary file initialize-wifi.sh contains the Wi-Fi password.
                                # It is executed and then deleted by folders/usr/lib/ditana/initialize-system-as-root
                                "folders/usr/lib/ditana".IO.mkdir;
                                my $wifi-script = 'folders/usr/lib/ditana/initialize-wifi.sh'.IO;
                                $wifi-script.spurt("nmcli dev wifi connect '$ssid' password '$ssid-passphrase'\n");
                                $wifi-script.IO.chmod(0o700);

                                add-root-script-step(q:to/END/.chomp);
echo "Initializing Wi-Fi..."
/usr/lib/ditana/initialize-wifi.sh
echo "Successfully initialized Wi-Fi, deleting file that contained the Wi-Fi password."
shred -u /usr/lib/ditana/initialize-wifi.sh
END
                                last;
                            }
                        }
                        else {
                            Logging.log("Connection failed (probably wrong password).");
                            show-dialog-raw('--msgbox', 'Connection failed (probably wrong password).', 10, 50);
                        }
                    } else {
                        Logging.log("User canceled or entered an empty password.");
                    }
                }
            }
        }
    }
}

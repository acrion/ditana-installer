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
use JSON::Fast;
use Dialogs;
use Settings;
use Timezone;
use Logging;

sub get-country-name($code) {
    state %country-names;

    unless %country-names {
        # package iso-codes is installed to provide /usr/share/iso-codes/json/iso_3166-1.json
        my $json-text = "/usr/share/iso-codes/json/iso_3166-1.json".IO.slurp;
        my $iso-codes-data = from-json($json-text);
        
        for @($iso-codes-data{'3166-1'}) -> $country {
            my $code = $country<alpha_2>;
            my $name = $country<common_name> // $country<name> // 
                    $country<official_name> // $code;
            %country-names{$code} = $name;
        }
    }

    return %country-names{$code.uc} // $code;
}

sub get-special-layout-name($code) {
    given $code {
        when 'ara' { 'Arabic' }
        when 'brai' { 'Braille' }
        when 'cd' { 'Congo-Kinshasa' }
        when 'cg' { 'Congo-Brazzaville' }
        when 'custom' { 'Custom' }
        when 'epo' { 'Esperanto' }
        when 'latam' { 'Latin American' }
        default { get-country-name($code) }
    }
}

sub get-variant-description($layout, $variant) {
    state $descriptions = do {
        my $manpage-path = qx{man -w xkeyboard-config}.trim;
        my %layout-descriptions;
        
        my $content = qqx{zcat "$manpage-path"};
        
        for $content.lines -> $line {
            if $line ~~ /(\S+) '(' (<-[)]>+) ')' \s+ (.+)/ {
                my $l = ~$0;
                my $v = ~$1;
                my $desc = ~$2;
                
                %layout-descriptions{$l}{$v} = $desc.trim;
            }
        }
        
        %layout-descriptions;
    }
    
    return $descriptions{$layout}{$variant} // '';
}

sub choose-keymap-layout() returns Int is export {
    state $temp-file = qx{mktemp}.chomp;
    $temp-file.IO.spurt(qx{localectl list-x11-keymap-layouts});
    
    my @menu-options;
    for $temp-file.IO.lines -> $code {
        my $name = get-special-layout-name($code);
        @menu-options.append: $code, $name;
    }

    # Priority: previous choice > sub-locale (e.g. "de_CH" → "ch") > detected country code
    my @layouts = @menu-options.rotor(2).map(*.[0]);
    my $preferred = '';

    with Settings.instance.get('keymap-layout') -> $prev {
        $preferred = $prev if @layouts.grep($prev);
    }
    unless $preferred {
        with Settings.instance.get('locale') -> $loc {
            if $loc ~~ / _ (\S+) $ / {
                my $candidate = $0.Str.lc;
                $preferred = $candidate if @layouts.grep($candidate);
            }
        }
    }
    unless $preferred {
        my $cc = detected-country-code().lc;
        $preferred = $cc if $cc && @layouts.grep($cc);
    }

    my @default-args;
    @default-args = '--default-item', $preferred if $preferred;

    my @dialog-args = '--title', 'Keyboard Layout Selection',
                      '--cancel-label', "Back",
                      |@default-args,
                      '--menu', '\nSelect your keyboard layout.',
                      32, 50, 10, |@menu-options;
                     
    my $result = show-dialog-raw(|@dialog-args);
    if $result<status> == 0 {
        Settings.instance.set('keymap-layout', $result<value>);
    }
    $result<status>
}

sub show-variant-help() {
    my $help-text='When selecting a keyboard layout, you may encounter various «variants» available for some layouts. Here’s a brief explanation to help you understand the options better:

=== Dead Keys vs. No Dead Keys ===

In some keyboard layouts, certain keys (called «dead keys») are used to type accents or diacritical marks by pressing them before another key. For example, pressing the dead key for the acute accent (´) followed by the letter e results in é. The variant labeled «no dead keys» means these special keys are disabled, and you can type the accent symbols directly without them modifying subsequent letters. This variant might be preferred if you do not frequently use accented characters or if the layout includes separate keys for these symbols.

=== Testing the Layout ===

After selecting a layout variant, you have the option to test it. This is useful to ensure that the keys produce the expected characters. If not, you can press Escape to return to this dialog.';
    
    my %wrap-text = calculate-wrapped-lines($help-text, 94);
    my @args = '--title', 'Help: Keyboard Layout Variant',
               '--no-collapse',
               '--msgbox', %wrap-text<text>,
               %wrap-text<lines>+4, 98;
               
    show-dialog-raw(|@args);
}

sub choose-keymap-variant($silent-exit-code) returns Int is export {
    Logging.log("choose-keymap-variant: start");
    my $keymap-layout = Settings.instance.get('keymap-layout');
    my $proc = run "localectl", "list-x11-keymap-variants", $keymap-layout, :out, :err;
    my $list-of-keymap-variants = $proc.out.slurp(:close);
        
    if $proc.exitcode {
        Logging.log("choose-keymap-variant: found no variants, silent_exit_code=$silent-exit-code");
        Settings.instance.set('keymap-variant', '');
        return $silent-exit-code;
    }

    state $temp-file=qx{mktemp}.chomp;
    $temp-file.IO.spurt($list-of-keymap-variants);
    Logging.log("choose-keymap-variant: found variants");
    
    my @nodeadkeys-entry;
    my @menu-options;
    
    for $list-of-keymap-variants.lines -> $code {
        my $variant-description = get-variant-description($keymap-layout, $code);
        
        if $code eq 'nodeadkeys' {
            @nodeadkeys-entry = $code, $variant-description;
        } else {
            @menu-options.append: $code, $variant-description;
        }
    }
    
    @menu-options.unshift(|@nodeadkeys-entry) if @nodeadkeys-entry;
    
    my $dialogtext = "\nSelect your keyboard variant for {get-special-layout-name($keymap-layout)}.";
    
    if Settings.instance.get('real-install')
    && Settings.instance.get('display-hardware-in-use')
    && !Settings.instance.get('installing-over-ssh') {
        $dialogtext ~= ' After selection you may review a graphical representation. Press ENTER to close it.';
    }
        
    Logging.log("choose-keymap-variant: built dialog options");

    # Priority: previous choice (if still valid for this layout)
    #         > <main-locale>_nodeadkeys > <main-locale> > nodeadkeys
    my @variants = $list-of-keymap-variants.lines;
    my $preferred = '';

    with Settings.instance.get('keymap-variant') -> $prev {
        $preferred = $prev if $prev && @variants.grep($prev);
    }
    unless $preferred {
        my $main = Settings.instance.get('main-locale') || '';
        if $main {
            for ("{$main}_nodeadkeys", $main) -> $candidate {
                if @variants.grep($candidate) {
                    $preferred = $candidate;
                    last;
                }
            }
        }
        $preferred = 'nodeadkeys' if !$preferred && @variants.grep('nodeadkeys');
    }

    my @default-args;
    @default-args = '--default-item', $preferred if $preferred;

    loop {
        my @dialog-args = '--help-button',
                        '--title', "Keyboard Layout Variant",
                        '--cancel-label', "Back",
                        |@default-args,
                        '--menu', $dialogtext,
                        27, 98, 10,
                        |@menu-options;
                        
        my %variant = show-dialog-raw(|@dialog-args);
        
        given %variant<status> {
            when 0 {
                Settings.instance.set('keymap-variant', %variant<value>);
                return 0;
            }
            when 2 {
                show-variant-help();
            }
            default {
                return 1;
            }
        }
    }
}

sub set-keymap-and-delay-rate($silent-exit-code) returns Int is export {
    Logging.log("set-keymap-and-delay-rate: A - entered, silent-exit-code = $silent-exit-code");
    return $silent-exit-code if $silent-exit-code != 0;

    my $tty = qx{tty}.chomp;
    Logging.log("set-keymap-and-delay-rate: B - current tty = '$tty' (controlling terminal)");
    if $tty ~~ /pts/ {
        Logging.log("set-keymap-and-delay-rate: WARNING - Running in a pseudo-terminal. Hardware commands need /dev/tty0!");
    }

    my $s = Settings.instance;
    my $layout  = $s.get('keymap-layout');
    my $variant = $s.get('keymap-variant') // '';

    Logging.log("set-keymap-and-delay-rate: C - layout='$layout', variant='$variant'");

    # 1. Write persistent X11 config
    my $cmd-x11 = "DISPLAY='' localectl --no-convert set-x11-keymap $layout";
    $cmd-x11 ~= " '' $variant" if $variant;
    Logging.log("set-keymap-and-delay-rate: D - X11 command: $cmd-x11");
    my $p1 = shell $cmd-x11;
    Logging.log("set-keymap-and-delay-rate: D1 - X11 exitcode = {$p1.exitcode}");

    # 2. Generate precise console keymap using ckbcomp
    my $map-file = "/etc/vconsole-ditana.map";
    my $cmd-gen = "ckbcomp $layout";
    $cmd-gen ~= " $variant" if $variant;
    $cmd-gen ~= " > $map-file";
    
    Logging.log("set-keymap-and-delay-rate: E - ckbcomp command: $cmd-gen");
    my $p-gen = shell $cmd-gen;
    Logging.log("set-keymap-and-delay-rate: E1 - ckbcomp exitcode = {$p-gen.exitcode}");

    # 3. Apply generated map to running TTY
    my $cmd-load = "loadkeys $map-file < /dev/tty0";
    Logging.log("set-keymap-and-delay-rate: F - loadkeys command: $cmd-load");
    my $p-load = shell $cmd-load;
    Logging.log("set-keymap-and-delay-rate: F1 - loadkeys exitcode = {$p-load.exitcode}");

    # 4. Write /etc/vconsole.conf manually for persistence
    # (localectl set-keymap is intentionally omitted as it doesn't handle custom maps well)
    my $vconsole-content = "KEYMAP=$map-file\n";
    "/etc/vconsole.conf".IO.spurt($vconsole-content);
    Logging.log("set-keymap-and-delay-rate: G - wrote /etc/vconsole.conf with KEYMAP=$map-file");

    # 5. Keyboard typematic delay/rate
    my $keyboard-delay = $s.get('keyboard-delay');
    my $keyboard-rate  = $s.get('keyboard-rate');
    Logging.log("set-keymap-and-delay-rate: H - keyboard-delay=$keyboard-delay, keyboard-rate=$keyboard-rate");

    my $cmd-rate = "kbdrate --silent --delay $keyboard-delay --rate $keyboard-rate < /dev/tty0";
    Logging.log("set-keymap-and-delay-rate: I - kbdrate command: $cmd-rate");
    my $p-rate = shell $cmd-rate;
    Logging.log("set-keymap-and-delay-rate: I1 - kbdrate exitcode = {$p-rate.exitcode}");

    Logging.log("set-keymap-and-delay-rate: J - finished successfully");
    0
}

sub copy-console-keyboard-configuration() is export {
    my $source = '/etc/vconsole.conf'; # created by set-keymap-and-delay-rate()
    my $destination = '/mnt/etc/vconsole.conf';

    die unless $source.IO.e;
    $destination.IO.parent.mkdir();
    $source.IO.copy($destination); # note that we extend this file in configure-terminal-font()

    my $map-source = '/etc/vconsole-ditana.map';
    my $map-dest   = '/mnt/etc/vconsole-ditana.map';

    if $map-source.IO.e {
        Logging.log("copy-console-keyboard-configuration: copying custom map $map-source to $map-dest");
        $map-dest.IO.parent.mkdir();
        $map-source.IO.copy($map-dest);
    }
}

sub copy-xorg-keyboard-configuration() is export {
    my $source = '/etc/X11/xorg.conf.d/00-keyboard.conf'; # created by set-keymap-and-delay-rate()
    my $destination = '/mnt/etc/X11/xorg.conf.d/00-keyboard.conf';

    die unless $source.IO.e;
    $destination.IO.parent.mkdir();
    $source.IO.copy($destination);
}

sub test-keymap() returns Int is export {
    my $input=qx{mktemp}.chomp;
    my $description = (Settings.instance.get("keymap-layout")
        ~ " " ~ Settings.instance.get("keymap-variant")).trim();
    my $content = qq:to/END/;
You selected keymap "$description".
You may enter arbitrary text here to test your typing.
Please note that this terminal font (Terminus) supports
not the complete Unicode set, but at least 1356 symbols.

Press TAB to navigate to below buttons.
Press Escape to change the keymap.

END
    $input.IO.spurt($content);
    
    my %result = show-dialog-raw(
        '--title',
        "Keyboard Layout Test",
        "--editbox",
        $input,
        20,
        101);

    $input.IO.unlink;
    return %result<status>;
}

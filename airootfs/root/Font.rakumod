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
use Settings;
use RunAndLog;

sub find-closest-font-size(Real $desired-font-pt, Real $terminal-dpi) returns Int {
    my @sizes = (12, 14, 16, 18, 20, 22, 24, 28, 32); # available Terminus font sizes
    my $target = $desired-font-pt * $terminal-dpi / 72; # ideal Terminus font size
    
    # Find closest size using reduction and min by absolute difference
    @sizes.min: { abs($_ - $target) }
}

sub update-terminal-font($silent-exit-code) returns Int is export {
    return $silent-exit-code if $silent-exit-code != 0; # only do this if user navigated forward

    my $hook-path = '/tmp/ditana-set-font.sh';
    my $hook-already-applied = $hook-path.IO.e;

    if $hook-already-applied {
        # The previous installer session wrote this hook, the wrapper script
        # sourced it (running setfont and exporting DISPLAY_SIZE), then
        # restarted us. The visible font is already correct, but the
        # Settings cache of this fresh process is empty - so we still need
        # to recompute terminal-font below and persist it for later use by
        # configure-terminal-font(). DISPLAY_SIZE is restored via the
        # detect= entry for "display-size" in hardware-detection.kdl.
        Logging.log("Detected hook file that changed the terminal font size, skipping setfont (already ran in wrapper script).");
        Logging.log("Content of hook file:");
        Logging.log("{$hook-path.IO.slurp}");
        $hook-path.IO.unlink;
        Settings.instance.set("set-font-hook-exists", False);
    }

    my $terminal-columns = Settings.instance.get("terminal-columns");
    my $terminal-lines = Settings.instance.get("terminal-lines");

    return $silent-exit-code unless $terminal-columns.defined && $terminal-lines.defined;

    state $display-size is default(-1);
    my $updated-display-size = Settings.instance.get("display-size");

    Logging.log("updated-display-size = $updated-display-size");
    Logging.log("display-size = $display-size");

    Logging.log("Comparison result: {try { $updated-display-size == $display-size }}");

    return $silent-exit-code if $updated-display-size ~~ Int && $updated-display-size == $display-size;

    $display-size = $updated-display-size;

    Logging.log("Display fills $terminal-columns × $terminal-lines characters with 6 × 12 pixels");

    # ter-112n has pixel size 6x12, see https://terminus-font.sourceforge.net
    my $approx-width = $terminal-columns × 6;
    my $approx-height = $terminal-lines × 12;

    # This is not necessarily the native resolution, which might be higher. But it is the screen resolution
    # that is used for virtual terminals, which is what we need to specify the font size that should be used for them.
    my $display-width = ($approx-width + 7) div 8 × 8;
    my $display-height = ($approx-height + 7) div 8 × 8;
    Logging.log("Display resolution (not necessarily its native resolution): $display-width × $display-height");

    my $terminal-dpi = sqrt($display-width² + $display-height²) / $display-size;

    my $desired-font-pt = 10;
    my $font-size = find-closest-font-size($desired-font-pt, $terminal-dpi);
    Logging.log("Font size nearest to {$desired-font-pt}pt: $font-size");

    my $terminal-font = $font-size > 12 ?? "ter-1{$font-size}b" !! "ter-1{$font-size}n";

    Settings.instance.set("terminal-font", "$terminal-font");

    if !$hook-already-applied {
        if Settings.instance.get('tmux') {
            $hook-path.IO.spurt("setfont $terminal-font\nexport DISPLAY_SIZE=$display-size");
            die "Interrupting installer to change font size of virtual terminal."
        } else {
            qqx{setfont $terminal-font};
        }
    }

    return $silent-exit-code;
}

sub configure-terminal-font() is export {
    my $terminal-font = Settings.instance.get("terminal-font");
    Logging.echo("Configuring terminal font $terminal-font");
    '/mnt/etc/vconsole.conf'.IO.spurt("\nFONT=$terminal-font\n", :append); # this file is created by `copy-console-keyboard-configuration()`
}

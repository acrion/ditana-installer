# Copyright (c) 2026 acrion innovations GmbH
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

=begin pod

Unattended installation from an answer file.

An answer file supplies in advance what the wizard would otherwise ask. Every
setting it names is applied before the first dialog is drawn, and every
installation step whose questions are all answered is skipped. Nothing else
about the installer changes: the same settings drive the same installation, so
an unattended install and an interactive one cannot drift apart.

Where the file comes from, first match wins:

=item C<ditana.autoinstall=URL|PATH> on the kernel command line. This is the
form a hosting provider uses, because it survives PXE and needs no modified
image.

=item A filesystem labelled C<DITANA_AUTO> on any attached device, holding
C<autoinstall.kdl>. The "config drive" pattern: attach a small image beside the
installation medium and change nothing else.

=item C</root/autoinstall.kdl>, baked into a custom ISO.

Two modes:

=item C<strict> (the default) stops if the file leaves any question
unanswered. A provisioning system must not have a machine silently installed
with a guessed answer.

=item C<defaults> fills what the file does not name with the value the
installer detected for this hardware. Convenient for a user who wants to
answer three questions and accept the rest.

Both refuse to guess about a question the installer cannot answer itself --
which disk to erase has no safe default in either mode.

=end pod

use v6.d;
use JSON::Fast;
use Logging;
use Settings;

class Autoinstall {
    my Autoinstall $instance;
    method new {!!!}
    method instance {
        $instance = Autoinstall.bless unless $instance;
        $instance;
    }

    has Bool $.active is rw = False;
    has Str  $.path is rw = '';
    has Str  $.mode is rw = 'strict';
    has Str  $.source is rw = '';
    has %.answers;
    has %.post-install;

    # The kernel command line is the provider-facing entry point; the label and
    # the baked-in file exist for the cases where it cannot be set.
    my constant CMDLINE-KEY = 'ditana.autoinstall';
    my constant VOLUME-LABEL = 'DITANA_AUTO';
    my constant BAKED-IN = '/root/autoinstall.kdl';
    my constant MOUNTPOINT = '/run/ditana-autoinstall';

    #| Find an answer file and return its local path, or Nil.
    method !locate(--> Str) {
        my $from-cmdline = self!from-cmdline();
        return $from-cmdline if $from-cmdline;

        my $from-label = self!from-labelled-volume();
        return $from-label if $from-label;

        return BAKED-IN if BAKED-IN.IO.e;
        Nil;
    }

    method !from-cmdline(--> Str) {
        return Nil unless '/proc/cmdline'.IO.e;
        my $value = '/proc/cmdline'.IO.slurp.words
                        .first(*.starts-with(CMDLINE-KEY ~ '='));
        return Nil unless $value;
        $value = $value.substr((CMDLINE-KEY ~ '=').chars);
        return Nil unless $value.chars;

        if $value.starts-with('http://') || $value.starts-with('https://') {
            my $target = '/run/ditana-autoinstall.kdl';
            Logging.log("Autoinstall: fetching $value");
            my $fetch = run('curl', '-fsSL', '--max-time', '60', $value, '-o', $target,
                            :out, :err);
            if $fetch.exitcode != 0 {
                # Fail rather than fall through: the operator named a source,
                # and quietly installing from a different one would be worse
                # than stopping.
                die "Autoinstall: cannot fetch $value (curl exit {$fetch.exitcode})";
            }
            self.source = $value;
            return $target;
        }

        die "Autoinstall: $value does not exist" unless $value.IO.e;
        self.source = $value;
        $value;
    }

    method !from-labelled-volume(--> Str) {
        my $device = "/dev/disk/by-label/{VOLUME-LABEL}";
        return Nil unless $device.IO.e;

        mkdir MOUNTPOINT unless MOUNTPOINT.IO.d;
        my $mount = run('mount', '-o', 'ro', $device, MOUNTPOINT, :out, :err);
        if $mount.exitcode != 0 {
            Logging.log("Autoinstall: found $device but could not mount it");
            return Nil;
        }

        my $file = MOUNTPOINT ~ '/autoinstall.kdl';
        unless $file.IO.e {
            run('umount', MOUNTPOINT, :out, :err);
            Logging.log("Autoinstall: $device carries no autoinstall.kdl");
            return Nil;
        }
        self.source = "$device:/autoinstall.kdl";
        $file;
    }

    #| Is an answer file present at all? Answered before the configuration is
    #| downloaded and before Settings exists, because the dialogs shown during
    #| those steps must already know not to wait for a keypress. Locating the
    #| file needs neither -- only validating it does, and that happens later in
    #| load().
    method detect(--> Bool) {
        return True if self.path;
        my $found = self!locate();
        return False unless $found;
        self.path = $found;
        self.active = True;
        True;
    }

    #| Apply the answer file that detect() found. Must run after the
    #| configuration is loaded: a setting can only be checked against the
    #| settings that exist.
    method load(--> Bool) {
        return False unless self.detect();
        self.load-from(self.path);
    }

    #| Read one answer file, check it against the settings that actually
    #| exist, and apply it. Separate from load() so that the file can also be
    #| named directly -- and so that this half is testable without a kernel
    #| command line or a labelled volume.
    method load-from(Str $path --> Bool) {
        Logging.log("Autoinstall: using {self.source || $path}");

        my $converter = $*PROGRAM.parent.child('json-kdl-converter').resolve.absolute;
        my $conversion = run($converter, 'kdl2json', $path, :out, :err);
        my $json = $conversion.out.slurp(:close);
        my $errors = $conversion.err.slurp(:close);
        if $conversion.exitcode != 0 {
            die "Autoinstall: $path is not valid KDL\n$errors";
        }
        my $data = from-json($json);

        self.mode = self!scalar($data<mode>) // 'strict';
        unless self.mode eq 'strict' | 'defaults' {
            die "Autoinstall: mode must be 'strict' or 'defaults', not '{self.mode}'";
        }

        if $data<post-install>:exists {
            %!post-install = $data<post-install>;
        }

        my $settings = $data<settings> // {};
        unless $settings ~~ Associative {
            die "Autoinstall: the 'settings' block must contain named values";
        }

        my @unknown;
        for $settings.kv -> $name, $raw {
            # Checked against the settings this installer actually loaded, not
            # against a schema kept elsewhere: the configuration is downloaded
            # at run time, so the running installer is the only authority on
            # which settings exist.
            unless Settings.instance.setting-exists($name) {
                @unknown.push($name);
                next;
            }
            %!answers{$name} = self!scalar($raw);
        }

        if @unknown {
            die "Autoinstall: no such setting(s): {@unknown.sort.join(', ')}";
        }

        for %!answers.kv -> $name, $value {
            Settings.instance.set($name, $value);
            Logging.log("Autoinstall: $name = $value");
        }

        self.active = True;
        True;
    }

    #| KDL gives every node's arguments as a list; a setting takes one value.
    method !scalar($raw) {
        return $raw unless $raw ~~ Positional;
        die "Autoinstall: expected exactly one value, got {$raw.elems}" unless $raw.elems == 1;
        my $value = $raw[0];
        # A yes/no setting is stored as a plain Bool, the way AskForYesNo
        # sets it; Tristate exists for the "unknown" case that an answer file
        # cannot express.
        $value;
    }

    #| True when every question this step would ask has an answer, so the step
    #| can be skipped without asking anything.
    method step-is-answered($step --> Bool) {
        return False unless self.active;
        my $name = $step<name>;

        given $step<type> {
            when 'ask-for-setting' | 'ask-for-yes-no' {
                return %!answers{$name}:exists;
            }
            when 'radiolist' | 'checklist' {
                my @settings = Settings.instance.get-dialog($name);
                return False unless @settings;
                return !@settings.map(*.name).grep({ !(%!answers{$_}:exists) });
            }
            when 'categories' {
                my @children = ($step<categories> // []).list;
                return False unless @children;
                return !@children.grep({ !self.step-is-answered($_) });
            }
            default {
                # A procedure decides for itself whether it needs to ask.
                # Nothing is assumed here: if it does ask, show-dialog-raw
                # stops the run and names it, which is how a missing entry
                # surfaces as a clear error instead of a hung installation.
                return False;
            }
        }
    }

    #| In defaults mode an unanswered setting keeps what the installer
    #| detected. In strict mode the run stops instead, naming what is missing.
    method require-answered(@names) {
        return if self.mode eq 'defaults';
        my @missing = @names.grep({ !(%!answers{$_}:exists) });
        return unless @missing;
        die "Autoinstall (strict): unanswered setting(s): {@missing.sort.join(', ')}\n"
          ~ "Add them to the answer file, or set mode \"defaults\" to accept "
          ~ "the values detected for this machine.";
    }
}

sub autoinstall-active(--> Bool) is export {
    Autoinstall.instance.active;
}

sub autoinstall(--> Autoinstall) is export {
    Autoinstall.instance;
}

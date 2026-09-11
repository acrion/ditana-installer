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

=item C<autoinstall.kdl> beside the installer -- C</root/autoinstall.kdl> in an
ISO built with one in it, and the file next to C<main.raku> when the installer
is started from a checkout.

What the file does not name keeps the value the installer would have offered:
either the default in C<ditana-config> or what was detected for this hardware.
That is not a guess. It is the same answer an interactive run pre-selects, and
overriding a detected value would mean choosing something that does not fit
the machine.

What has no such value is a different matter, and the run stops there rather
than inventing one. Two kinds:

=item A question with nothing behind it -- the user name is empty until
somebody types one. The step names the settings it is missing and the run
stops before anything is written.

=item A question the installer cannot answer at all: which disk to erase,
whether to overwrite an EFI partition another system boots from, the
passphrase for an encrypted root. Those reach their dialog, and the dialog
gate stops the run and names the box.

There is deliberately no lenient mode. A value from the configuration is an
answer, a missing value is not, and no third case turned out to exist.

=end pod

use v6.d;
use JSON::Fast;
use Logging;
use Settings;
use Tristate;

class Autoinstall {
    my Autoinstall $instance;
    method new {!!!}
    method instance {
        $instance = Autoinstall.bless unless $instance;
        $instance;
    }

    has Bool $.active is rw = False;
    has Str  $.path is rw = '';
    has Str  $.source is rw = '';
    has %.answers;
    has %.passwords;

    #| The accounts a password can be set for. 'user' is whichever name the
    #| user-name setting gives; root has no password on Ditana and gets none
    #| here, so that an answer file cannot quietly create one.
    my constant PASSWORD-ACCOUNTS = <user>;

    # The kernel command line is the provider-facing entry point; the label and
    # the baked-in file exist for the cases where it cannot be set.
    my constant CMDLINE-KEY = 'ditana.autoinstall';
    my constant VOLUME-LABEL = 'DITANA_AUTO';
    my constant MOUNTPOINT = '/run/ditana-autoinstall';

    #| autoinstall.kdl beside the installer itself. In an ISO that is
    #| /root/autoinstall.kdl; in a simulated run started from a checkout it is
    #| the file next to main.raku, which is how the mechanism can be exercised
    #| without building an image first. Deriving it rather than hard-coding
    #| /root keeps both cases on the same code path.
    method !baked-in(--> Str) {
        $*PROGRAM.parent.child('autoinstall.kdl').absolute;
    }

    #| Find an answer file and return its local path, or Nil.
    method !locate(--> Str) {
        my $from-cmdline = self!from-cmdline();
        return $from-cmdline if $from-cmdline;

        my $from-label = self!from-labelled-volume();
        return $from-label if $from-label;

        my $baked-in = self!baked-in();
        return $baked-in if $baked-in.IO.e;
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

        # Anything that is not one of the blocks below is named and rejected,
        # for the same reason a misspelt setting is: a block that is read and
        # ignored looks from the outside exactly like a block that was
        # applied.
        my @stray = $data.keys.grep(* !~~ any(<settings passwords>));
        if @stray {
            die "Autoinstall: $path has no place for {@stray.sort.join(', ')}. "
              ~ "An answer file holds 'settings' and 'passwords'.";
        }

        self!read-passwords($data<passwords>, $path) if $data<passwords>:exists;

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

        # Setting one value re-evaluates every setting whose default is an
        # expression naming it, so an answer applied early can be overwritten
        # by the dependency update that a later answer triggers. The settings
        # dialogs have the same problem and solve it the same way: apply
        # everything, then assert it again once nothing else will move. reset()
        # rather than set() because by then the value is already there, and
        # set() would consider it unchanged and do nothing.
        #
        # Sorted, so that two runs of the same file do the same thing in the
        # same order and a log can be compared against another log.
        for %!answers.keys.sort -> $name {
            Settings.instance.set($name, %!answers{$name});
            Logging.log("Autoinstall: $name = {%!answers{$name}}");
        }
        for %!answers.keys.sort -> $name {
            Settings.instance.reset($name, %!answers{$name});
        }

        self!settle-radiolists();
        self!verify-answers-hold($path);

        self.active = True;
        True;
    }

    #| Every answer must still hold once nothing else will move.
    #|
    #| Applying an answer file is not a sequence of independent assignments,
    #| and neither of the two things that can undo an answer is visible while
    #| the answers are being applied:
    #|
    #| An C<available> condition decides whether a setting is a row any
    #| dialog would show. A setting that an answer has put out of reach is one no
    #| interactive user could have chosen -- and C<settle-radiolists> cannot
    #| see it either, because C<get-dialog> filters by availability, so the
    #| dialog it belongs to is not even acknowledged as answered. A file
    #| naming a kernel other than the long-term support one together with
    #| C<zfs-filesystem #true> came through that gap with both ZFS and Btrfs
    #| selected at once.
    #|
    #| A C<default-value> expression is a standing rule rather than a starting
    #| value: it is re-evaluated whenever anything it names changes and then
    #| applies its result over whatever was there, including over an answer.
    #| The two passes above make a file order-independent, but they cannot
    #| make an answer survive a rule that contradicts it.
    #|
    #| Both stop the installation, and both achieve this even when the setting
    #| appears benign. The operator recorded what the machine ought to be;
    #| that it cannot be that is a fact concerning the machine or the file, and it
    #| is preferable to discover it here rather than after an installation
    #| that is not the one requested. Naming the condition holds equal weight
    #| to naming the setting -- without it the message says that something is
    #| impossible without saying what would make it possible.
    method !verify-answers-hold(Str $path) {
        my @complaints;

        for %!answers.keys.sort -> $name {
            unless Settings.instance.is-available($name) {
                my $condition = Settings.instance.availability-condition($name);
                @complaints.push(
                    "$name = {%!answers{$name}} cannot be set, because the setting "
                  ~ "is not available on this machine"
                  ~ ($condition ?? ". It requires: $condition" !! '.'));
                next;
            }

            next unless Settings.instance.different-value($name, %!answers{$name});

            my $rule = Settings.instance.default-expression($name);
            @complaints.push(
                "$name was answered {%!answers{$name}} but ended up "
              ~ "{Settings.instance.get($name) // '(unset)'}"
              ~ ($rule ?? ", because its value follows: $rule" !! '')
              ~ '.');
        }

        return unless @complaints;

        die "Autoinstall: $path asks for settings this installation cannot honour:\n"
          ~ @complaints.map({ "  - $_" }).join("\n");
    }

    #| Every radiolist step, however deeply the categories nest.
    method !radiolist-dialogs(@steps = Settings.instance.installation-steps.values) {
        my @names;
        for @steps -> $step {
            @names.push($step<name>) if $step<type> eq 'radiolist';
            @names.append(|self!radiolist-dialogs(($step<categories> // []).list))
                if $step<type> eq 'categories';
        }
        @names;
    }

    #| Make an answered radiolist exclusive, the way choosing in it would.
    #|
    #| A radiolist is one choice spread over several boolean settings, and the
    #| dialog unchecks the others when one is checked. An answer file naming
    #| only C<profile-server #true> would otherwise leave C<profile-default>
    #| standing at the C<#true> the configuration gave it, and every default
    #| expression that asks about a profile would then see two of them.
    #|
    #| Touching a radiolist at all therefore means owning it: the members the
    #| file does not name go false. What that cannot repair -- naming two as
    #| true, or naming the only true one as false -- stops the run, because
    #| there is no way to tell which of the two the operator meant.
    method !settle-radiolists() {
        for self!radiolist-dialogs() -> $dialog-name {
            my @settings = Settings.instance.get-dialog($dialog-name);
            next unless @settings;
            next unless @settings.grep({ %!answers{.name}:exists });

            for @settings -> $setting {
                next if %!answers{$setting.name}:exists;
                next unless Settings.instance.get($setting.name);
                Logging.log("Autoinstall: '$dialog-name' is answered, so "
                          ~ "{$setting.name} goes false");
                Settings.instance.set($setting.name, False);
            }

            my @chosen = @settings.map(*.name).grep({ Settings.instance.get($_) });
            unless @chosen == 1 {
                die "Autoinstall: '$dialog-name' is one choice out of "
                  ~ "{@settings.elems}, and the answer file leaves "
                  ~ (@chosen ?? "{@chosen.sort.join(' and ')} chosen"
                             !! "none of them chosen")
                  ~ ". Name exactly one of {@settings.map(*.name).sort.join(', ')} "
                  ~ "as #true.";
            }
        }
    }

    #| The account passwords, as the hashes /etc/shadow stores.
    #|
    #| A block of their own and not settings, because they are not
    #| configuration: they are per-machine secrets, they belong in no run
    #| record, and there is nothing in ditana-config for them to be checked
    #| against.
    #|
    #| Only hashes. An answer file for a hosting provider lives on a
    #| provisioning server and is read by everything that provisions, so a
    #| plaintext password in one is a password that has already leaked.
    #| Refusing it is the point; accepting it "for convenience" would make the
    #| whole file a place people put passwords.
    method !read-passwords($block, Str $path) {
        unless $block ~~ Associative {
            die "Autoinstall: the 'passwords' block must contain named values";
        }
        for $block.kv -> $account, $raw {
            unless $account ~~ any(PASSWORD-ACCOUNTS) {
                die "Autoinstall: $path sets a password for '$account'. "
                  ~ "The accounts an installation has are "
                  ~ "{PASSWORD-ACCOUNTS.join(', ')}; 'user' is whichever name "
                  ~ "the user-name setting gives.";
            }
            my $hash = self!scalar($raw);
            # Every crypt format libxcrypt offers starts this way, and no
            # password a person would type does.
            unless $hash ~~ Str && $hash.starts-with('$') {
                die "Autoinstall: the password for '$account' is not a hash. "
                  ~ "An answer file may only carry hashes -- it is read by "
                  ~ "everything that provisions a machine.\n"
                  ~ "Make one with: openssl passwd -6, or mkpasswd -m yescrypt";
            }
            %!passwords{$account} = $hash;
            Logging.log("Autoinstall: a password hash is given for '$account'");
        }
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

    #| The settings a step would ask about, or Nil when that cannot be said.
    #|
    #| Nil is not the empty list. It means "this step decides for itself what
    #| it asks" -- every procedure, and a dialog that turns out to have no
    #| settings on this machine. Such a step is always entered, and whatever
    #| it does ask reaches the dialog gate, which stops the run and names the
    #| box. That is what lets this mapping be incomplete without an
    #| installation ever hanging on a question nobody answered.
    method settings-of-step($step) {
        my $name = $step<name>;

        given $step<type> {
            when 'ask-for-setting' | 'ask-for-yes-no' {
                return ($name,);
            }
            when 'radiolist' | 'checklist' {
                # Settings the dialog would not show on this machine are not
                # questions it asks, so an answer file need not carry them.
                my @settings = Settings.instance.get-dialog($name);
                return Nil unless @settings;
                return @settings.map(*.name).List;
            }
            when 'categories' {
                # A category menu is navigation: it asks nothing itself, and
                # skipping it is what the user does by walking straight to
                # «Review Summary and Start». The children that are
                # procedures -- the summary, the optional swap size -- offer
                # an adjustment to a value that is already set, so a child
                # with no settings of its own adds no question here either.
                my @children = ($step<categories> // []).list;
                return Nil unless @children;
                my @names;
                for @children -> $child {
                    my $of-child = self.settings-of-step($child);
                    @names.append(|$of-child) with $of-child;
                }
                return @names.List;
            }
            default {
                return Nil;
            }
        }
    }

    #| Does this setting hold an answer already, without anybody having been
    #| asked?
    #|
    #| A value out of ditana-config or out of hardware detection counts, and
    #| has to: it is what an interactive dialog would arrive pre-selected
    #| with, and a file that had to repeat all of it would break every time
    #| the configuration gained a checkbox. What does not count is a setting
    #| standing empty -- the user name until somebody types one -- or a
    #| Tristate whose value is still unknown.
    method !holds-an-answer(Str $name --> Bool) {
        my $value = Settings.instance.get($name);
        return False without $value;
        return $value.value.defined if $value ~~ Tristate;
        return $value.trim.chars > 0 if $value ~~ Str;
        True;
    }

    #| True when this step has nothing left to ask and can be passed over.
    #|
    #| A step with a setting that holds no answer at all stops the run here
    #| rather than at its dialog: this is the last point at which the settings
    #| behind a step are known, so the message can name them instead of naming
    #| a box.
    method step-can-be-skipped($step --> Bool) {
        return False unless self.active;

        my $settings = self.settings-of-step($step);
        return False without $settings;

        my @unanswered = $settings.grep({
            !(%!answers{$_}:exists) && !self!holds-an-answer($_)
        });
        return True unless @unanswered;

        die "Autoinstall: '{$step<name>}' asks about "
          ~ "{@unanswered.sort.join(', ')}, which has no value and which the "
          ~ "answer file does not name.\nAdd it to the answer file.";
    }
}

#| The line an unattended run writes to the serial console when it stops.
#|
#| Repeated in ditana-build's `bin/test-install-in-qemu`, which greps for it.
#| Changing it here without changing it there incurs no cost to the harness
#| beyond its speed: it falls back to waiting out its timeout, which is where
#| it started.
constant AUTOINSTALL-ABORT-MARKER = 'DITANA-AUTOINSTALL-ABORT:';

#| Say on the serial console that an unattended installation stopped, and why.
#|
#| Nobody is watching the screen of an unattended run, and the installer's own
#| log lives inside the machine being installed -- which on this kind of
#| failure is the machine that does not exist yet. The serial line is the one
#| channel that leaves the box before anything is installed, and a harness
#| driving the installer in a virtual machine can read it while the guest is
#| still running. Without it such a run is indistinguishable from a hang, and
#| ditana-build waited out its full 5400-second timeout to report that the
#| guest "never reached the reboot that ends an installation" -- true, and
#| saying nothing about what went wrong.
#|
#| Every line is prefixed, so that a grep for the marker returns the whole
#| message rather than its first line.
#|
#| Silent when there is no serial line, and silent when writing to it fails. A
#| machine need not have one, and failing to report a failure must not turn
#| into a second failure that hides the first.
sub announce-unattended-abort($message) is export {
    return unless autoinstall-active();

    my $serial = '/dev/ttyS0'.IO;
    return unless $serial.e;

    my $handle = $serial.open(:w);
    for $message.Str.lines -> $line {
        $handle.print("{AUTOINSTALL-ABORT-MARKER} $line\n");
    }
    $handle.close;

    CATCH { default { Logging.log("could not announce on $serial: $_") } }
}

sub autoinstall-active(--> Bool) is export {
    Autoinstall.instance.active;
}

#| True when an answer file is in charge and provides every one of these
#| settings.
#|
#| This is what a procedure asks before drawing a box. A procedure is not
#| skipped the way a plain question step is, because it usually derives
#| further settings from the answer -- select-disk also records the boot
#| device and the partition that already holds a bootloader -- and skipping it
#| would leave those empty for everything downstream. So the procedure runs
#| and only the box is left out.
sub autoinstall-answers(*@names --> Bool) is export {
    my $autoinstall = Autoinstall.instance;
    return False unless $autoinstall.active;
    !@names.grep({ !($autoinstall.answers{$_}:exists) });
}

sub autoinstall(--> Autoinstall) is export {
    Autoinstall.instance;
}

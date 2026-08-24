use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;

# chroot-install.sh runs inside the chroot, where the Raku installer's own
# gate cannot reach. A dialog drawn there waits for a keypress nobody is going
# to give, and an unattended installation sits at it -- already finished, and
# from the outside indistinguishable from one still working -- until whatever
# waits on the other end gives up.
#
# It happened twice in one evening: once at the password prompt, once at the
# box that says the installation is finished. Both times after the whole
# system had been installed. show_dialog is the one way through, and this is
# what keeps it that way.

my $script = $?FILE.IO.absolute.IO.parent.parent.parent
                 .child('airootfs/root/bind-mount/root/chroot-install.sh');
ok $script.e, 'chroot-install.sh is where it is expected';

my @lines = $script.lines;

# The definition itself is the one place `dialog` may be called directly, and
# it is recognised by being inside the function body rather than by its line
# number, which moves.
my $in-definition = False;
my @bypasses;
for @lines.kv -> $index, $line {
    $in-definition = True  if $line.starts-with('show_dialog() {');
    $in-definition = False if $in-definition && $line eq '}';
    next if $in-definition;
    next if $line.trim.starts-with('#');
    # `dialog` as a command: at the start of a word, not inside show_dialog
    # and not the English word in a sentence.
    next unless $line ~~ / << 'dialog' \s+ '--' /;
    next if $line ~~ / 'show_dialog' /;
    @bypasses.push("{$index + 1}: {$line.trim}");
}

is @bypasses.elems, 0,
    'every dialog in chroot-install.sh goes through show_dialog'
    or diag "These call dialog directly:\n" ~ @bypasses.join("\n");

# And the gate itself does what it claims. The script cannot be sourced
# without a chroot, so the function is lifted out and run on its own -- which
# also means the test reads the real definition and not a copy of it.
my $definition = @lines.grep({ $_ }).join("\n");
$definition ~~ / 'show_dialog() {' .*? \n '}' /;
my $function = ~$/;
ok $function.chars, 'the definition can be lifted out to be exercised';

my $log = $*TMPDIR.child('ditana-chroot-dialog-test.log');
$log.spurt('');

#| Run show_dialog with the given arguments and return its exit code. `dialog`
#| is replaced by something that fails loudly: if the gate ever calls it under
#| an answer file, that must not look like success.
sub gate(*@args, :$autoinstall = 'y') {
    # Not an interpolating heredoc: the shell it builds is full of $, {} and
    # >>, and every one of them means something to Raku as well.
    my $template = q:to/SH/;
        AUTOINSTALL="@MODE@"
        dialog() { echo "dialog was called: $*" >> @LOG@; return 7; }
        @FUNCTION@
        show_dialog @ARGS@
        SH
    my $script-text = $template
        .subst('@MODE@', $autoinstall)
        .subst('@LOG@', $log.absolute)
        .subst('@FUNCTION@', $function)
        .subst('@ARGS@', @args.map({ "'$_'" }).join(' '));
    my $proc = run('bash', '-c', $script-text, :out, :err);
    $proc.out.slurp(:close);
    $proc.err.slurp(:close);
    $proc.exitcode;
}

# /var/log/install_ditana.log does not exist here, so the logging inside the
# function writes nowhere; bash reports that on stderr and carries on, which
# is why only the exit code is asserted.
is gate('--msgbox', 'The system installation is finished', 10, 50), 0,
    'a box that only reports is passed over, and the installation continues';
is gate('--infobox', 'Working', 4, 65), 0,
    'and so is an info box';

isnt gate('--passwordbox', 'Please enter a password', 10, 50), 0,
    'a box that asks stops the installation instead of waiting at it';
isnt gate('--yesno', 'Really?', 10, 50), 0,
    'and so does a yes/no box';

is $log.slurp, '',
    'none of that reached dialog itself, so nothing waited for a keypress';

is gate('--msgbox', 'Hello', 10, 50, autoinstall => 'n'), 7,
    'with nobody driving the installation, every box is shown as before';

done-testing;

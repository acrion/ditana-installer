use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use Autoinstall;

# The serial line is the only channel that leaves an unattended installation
# before anything is installed, and announce-unattended-abort is what writes to
# it. Two properties matter, and neither can be had by reading the code.
#
# The device it writes to is named by DITANA_SERIAL_CONSOLE here, which is not
# a test hook: a machine whose console is a virtio console has /dev/hvc0 and
# nothing on /dev/ttyS0, and it needs to be able to say so.

my $fixture = $?FILE.IO.absolute.IO.parent.child('fixture').absolute;
chdir $fixture;

my $scratch = $*TMPDIR.child("ditana-serial-{$*PID}");
$scratch.mkdir;

# Reached the way the installer reaches it: an answer file switches the run to
# unattended, and only then does anything get announced. Nothing is forced.
my $answers = $scratch.child('answers.kdl');
$answers.spurt(q:to/KDL/);
    settings {
        user-name "operator"
    }
    KDL
autoinstall().load-from($answers.absolute);
ok autoinstall-active(), 'the run is unattended, so the announcement applies at all';

# --- what a stopped run says -------------------------------------------------

my $console = $scratch.child('console');
%*ENV<DITANA_SERIAL_CONSOLE> = $console.absolute;
$console.spurt('');

announce-unattended-abort("Autoinstall: two things are wrong:\n  - the first\n  - the second");

my @lines = $console.slurp.lines;
is @lines.elems, 3, 'every line of the message is written';
ok all(@lines.map(*.starts-with('DITANA-AUTOINSTALL-ABORT:'))),
    'and every one of them carries the marker';
# Without the prefix on each line, a grep for the marker returns the first line
# of a refusal and drops the part that names what was actually refused.
ok @lines[1].contains('the first'), 'the detail lines survive, not just the heading';

# A console is written to, not overwritten: a second message has to arrive
# below the first one rather than on top of it.
announce-unattended-abort('and one more thing');
my @after = $console.slurp.lines;
is @after.elems, 4, 'a second announcement is added to what the console already carried';
ok @after[3].contains('one more thing'), 'and it is the one that arrived last';

# --- a device that exists and does not answer --------------------------------
# /dev/ttyS0 is created by the driver on machines with no serial line attached,
# so the existence check the sub does is not the test it looks like. A FIFO
# nobody reads blocks on open in exactly the same way a dead port can, and it
# is the one way to reach that state without inventing one.

my $blocked = $scratch.child('blocked');
run('mkfifo', $blocked.absolute);
%*ENV<DITANA_SERIAL_CONSOLE> = $blocked.absolute;

my $start = now;
announce-unattended-abort('this will not get through');
my $elapsed = now - $start;

ok $elapsed < 30,
    'a console that never accepts the write does not hold the installer for ever';
ok $elapsed >= 4,
    'and it is given a few seconds before being given up on, not abandoned at once';

# --- a machine with no serial line at all ------------------------------------

%*ENV<DITANA_SERIAL_CONSOLE> = $scratch.child('does-not-exist').absolute;
lives-ok { announce-unattended-abort('nowhere to say it') },
    'a machine without the device is silent rather than broken';

# --- naming the device ---------------------------------------------------
# A machine nobody is sitting at is told things on the kernel command line --
# it survives PXE, and it is already where the answer file is named. An
# environment variable would not reach the installer at all there: it is
# started from a getty autologin, and the operator sets the command line.

is cmdline-value('ditana.console', 'BOOT_IMAGE=/vmlinuz ditana.console=/dev/hvc0 quiet'),
    '/dev/hvc0', 'the console is read off the kernel command line';
is cmdline-value('ditana.autoinstall', 'ditana.autoinstall=http://host/a.kdl rw'),
    'http://host/a.kdl', 'and so is the answer file, through the same reader';
nok cmdline-value('ditana.console', 'BOOT_IMAGE=/vmlinuz quiet'),
    'a command line that does not name it reads as nothing';
nok cmdline-value('ditana.console', 'ditana.console= quiet'),
    'and so does one that names it without a value';
# starts-with on the bare key would take this for the console.
nok cmdline-value('ditana.console', 'ditana.console-log=/dev/null'),
    'a longer key that begins the same way is not mistaken for it';

%*ENV<DITANA_SERIAL_CONSOLE>:delete;
is serial-console().absolute, '/dev/ttyS0',
    'with nothing said either way it is the first serial port';

%*ENV<DITANA_SERIAL_CONSOLE> = '/dev/hvc0';
is serial-console().absolute, '/dev/hvc0',
    'and the environment names it where there is no command line of one\'s own';

done-testing;

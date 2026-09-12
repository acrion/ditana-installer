use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use Restart;

# The installer ends its own process once, on purpose: the console font can
# only be changed for a terminal nobody is drawing on, so it writes a hook,
# unwinds, and run-ditana-installer.sh sources the hook and starts it again.
#
# At the top of main.raku, a `die` with a string is indistinguishable from an
# installation that has stopped, and the top of main.raku is what decides
# whether DITANA-AUTOINSTALL-ABORT: goes onto the serial console. A restart
# announced that way is a healthy run reported as a dead one, on every medium
# that boots to a virtual terminal -- and the harness reading that console acts
# on it.
#
# What is pinned here is therefore not that the font changes, but that the two
# cases stay tellable apart, and in which order the top of the program tells
# them apart.

# --- the type is what makes them tellable apart ------------------------------

my $restart = X::Ditana::Restart.new(reason => 'font');
ok $restart ~~ Exception, 'the restart is an ordinary exception';
is $restart.message, 'font', 'and carries its reason as the message';

sub branch-for($e) {
    do given $e {
        when X::Ditana::Restart { 'restart' }
        default                 { 'abort' }
    }
}

is branch-for($restart), 'restart', 'a CATCH can select it by type alone';

# A plain `die "..."` produces X::AdHoc, and every refusal in the installer is
# one of those. If the restart were ever made a subclass of something they
# share, this is the assertion that falls.
is branch-for(X::AdHoc.new(payload => 'Autoinstall: ... cannot honour')), 'abort',
    'an answer file being refused still lands in the other branch';

# --- where the distinction has to be made ------------------------------------
# Source assertions, because the alternative is booting a medium. The ordering
# is the load-bearing one: a `when` placed after the announcement would satisfy
# every other line in this file and restore the defect in full.

my $root = $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root');

my $main = $root.child('main.raku').slurp;
my $catch = $main.substr($main.index('main();'));

my $when = $catch.index('when X::Ditana::Restart');
my $announce = $catch.index('announce-unattended-abort');
ok $when.defined, 'the top-level CATCH knows the restart by type';
ok $announce.defined, 'and still announces everything else';
ok $when < $announce, 'the restart is recognised before anything is announced';

ok $catch.contains('.rethrow'),
    'a real failure is rethrown, so the exit status and backtrace stay as they were';

my $font = $root.child('Font.rakumod').slurp;
ok $font.contains('X::Ditana::Restart'), 'the font step throws the type';
nok $font.contains('die "Interrupting'),
    'and no longer dies with a string that nothing can classify';

# The hook has to be on disk before the process ends, or the wrapper breaks out
# of its loop instead of restarting and the installer is simply gone.
my $spurt = $font.index('$hook-path.IO.spurt');
my $throw = $font.index('X::Ditana::Restart');
ok $spurt.defined && $spurt < $throw,
    'the hook is written before the process unwinds';

done-testing;

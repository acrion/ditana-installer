use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use Chroot;

# folders-before-pacstrap is copied into the target file system before pacman
# has installed anything, so rsync creates the directories on the way -- /usr
# among them, because usr/lib/os-release is in there. pacman later installs
# into a /usr that already exists and does not change the permissions of a
# directory it finds; it only warns.
#
# The installer runs with the umask from login.defs, which is 027 on Ditana.
# That made /usr 0750, and on a 0750 /usr nothing can be executed by anyone
# but root: the first non-root command in a chroot script died with
# "failed to execute /usr/bin/bash: Permission denied".
#
# What is checked here is the installer's own copy command, run into a
# directory of its own -- not a reproduction of it, which would stop checking
# the installer the day somebody edited one and not the other.

my $scratch = $*TMPDIR.child('ditana-before-pacstrap-modes');
run('rm', '-rf', $scratch.absolute);
my $source = $scratch.child('folders-before-pacstrap');
my $target = $scratch.child('mnt');
$source.child('usr/lib').mkdir;
$source.child('usr/lib/os-release').spurt("NAME=\"Ditana GNU/Linux\"\n");
$target.mkdir;

#| The mode of a path, as the three octal digits chmod speaks.
sub mode-of($path) {
    my $proc = run('stat', '-c', '%a', $path, :out, :err);
    my $out = $proc.out.slurp(:close).trim;
    $proc.err.slurp(:close);
    $out;
}

# First the failure, so that the test says what it is protecting against and
# not merely that today's command happens to work. This is the copy as it was:
# the same rsync, taking its permissions from the installer's umask.
run('sh', '-c', "umask 027; exec rsync --recursive --times --no-perms --executability "
                ~ "'{$source.absolute}/' '{$target.absolute}/'", :out, :err);
is mode-of($target.child('usr').absolute), '750',
    'left to the installer\'s umask of 027, rsync creates a /usr no ordinary user can enter';

# And now the installer's own command, verbatim.
run('rm', '-rf', $target.absolute);
$target.mkdir;
run('sh', '-c', before-pacstrap-rsync($source.absolute, $target.absolute), :out, :err);

is mode-of($target.child('usr').absolute), '755',
    '/usr is traversable, which is what lets a non-root user run anything at all';
is mode-of($target.child('usr/lib').absolute), '755',
    'and so is every directory below it';
is mode-of($target.child('usr/lib/os-release').absolute), '644',
    'while the files stay unreadable to nobody and writable by root only';

done-testing;

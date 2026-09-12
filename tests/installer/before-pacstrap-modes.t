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
# A 0750 /usr cannot be traversed by anyone but root, so nothing on the
# installed system can be executed by an ordinary user: the first non-root
# command in a chroot script fails with "failed to execute /usr/bin/bash:
# Permission denied".
#
# The source of this copy is a git checkout, and git records no directory
# modes: they are whatever the umask of the shell that cloned the repository
# was. So the test creates its source under the worst of those umasks and
# insists the copy comes out right regardless -- inheriting the mode from
# either side is precisely the defect.
#
# What runs is the installer's own command, not a reproduction of it, which
# would stop checking the installer the day somebody edited one and not the
# other.

my $scratch = $*TMPDIR.child('ditana-before-pacstrap-modes');
run('rm', '-rf', $scratch.absolute);
my $source = $scratch.child('folders-before-pacstrap');
my $target = $scratch.child('mnt');

#| The mode of a path, as the three octal digits chmod speaks.
sub mode-of($path) {
    my $proc = run('stat', '-c', '%a', $path, :out, :err);
    my $out = $proc.out.slurp(:close).trim;
    $proc.err.slurp(:close);
    $out;
}

# 027 is the umask the installer really runs with, and a checkout made under
# it has directories a group member cannot enter and others cannot see at all.
run('sh', '-c', "umask 027; mkdir -p '{$source.absolute}/usr/lib' '{$target.absolute}'"
              ~ " && printf 'NAME=\"Ditana GNU/Linux\"\\n' > '{$source.absolute}/usr/lib/os-release'"
              ~ " && printf '#!/bin/sh\\n' > '{$source.absolute}/usr/lib/probe.sh'"
              ~ " && chmod u+x '{$source.absolute}/usr/lib/probe.sh'", :out, :err);

is mode-of($source.child('usr').absolute), '750',
    'the source really is a checkout of the kind that caused this';

my @rsync = before-pacstrap-rsync($source.absolute, $target.absolute);
my $proc = run(|@rsync, :out, :err);
$proc.out.slurp(:close);
$proc.err.slurp(:close);
is $proc.exitcode, 0, 'the copy succeeds';

is mode-of($target.child('usr').absolute), '755',
    '/usr is traversable, which is what lets a non-root user run anything at all';
is mode-of($target.child('usr/lib').absolute), '755',
    'and so is every directory below it';
is mode-of($target.child('usr/lib/os-release').absolute), '644',
    'a plain file is readable by everyone and writable by root';
is mode-of($target.child('usr/lib/probe.sh').absolute), '755',
    'and a file that was executable stays executable, for everyone';

done-testing;

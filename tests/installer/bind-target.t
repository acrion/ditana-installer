use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use Mount;

# Bind mounts into the target file system are attached to paths that the
# freshly installed system already carries -- and some of those are symlinks.
# Everything follows a symlink: writing the placeholder writes through it, and
# `mount --bind` attaches to whatever it resolves to. Since the target's
# symlinks are absolute and resolved against the running system, both land on
# a file the *live* environment is using.
#
# Mounting itself needs root and is not what is checked here. What is checked
# is that the path is a real, empty file before the mount and the symlink it
# was afterwards.

my $scratch = $*TMPDIR.child('ditana-bind-target-tests');
$scratch.mkdir;
$scratch.child('run').mkdir;
$scratch.child('etc').mkdir;

my $real = $scratch.child('run/resolv.conf');
my $link = $scratch.child('etc/resolv.conf');

sub fresh() {
    unlink $link if $link.e || $link.l;
    $real.spurt("nameserver 10.0.2.3\n");
    $real.symlink($link);
}

# The one that cost 4.6 GB of installation: /mnt/etc/resolv.conf is a symlink
# to /run/systemd/resolve/stub-resolv.conf, and creating the placeholder wrote
# through it -- emptying the resolv.conf the live environment was using, and
# leaving the chroot with a dangling symlink and no nameserver.
fresh();
my $displaced = prepare-bind-target($link.absolute);

is $displaced, $real.absolute,
    'a symlink in the way is reported, not silently written through';
nok $link.l,
    'and it is gone, so the mount attaches where it was told to';
ok $link.e && $link.s == 0,
    'what stands there instead is an empty file of its own';
is $real.slurp, "nameserver 10.0.2.3\n",
    'the file it pointed at is untouched -- that is the live system\'s own';

# The installed system must get its symlink back. Left as the empty
# placeholder, /etc/resolv.conf would resolve nothing on the installed
# machine, which is worse than the failure this replaces.
restore-bind-target($link.absolute, $displaced);
ok $link.l, 'afterwards the symlink is back';
is $link.slurp, "nameserver 10.0.2.3\n", 'pointing where it pointed before';

# A plain file is the ordinary case and must not be disturbed by any of this.
unlink $link;
$link.spurt('');
is prepare-bind-target($link.absolute), '',
    'a target that is not a symlink displaces nothing';
ok $link.e && !$link.l, 'and stays the file it was';

# The placeholder is only created when there is nothing there at all.
unlink $link;
is prepare-bind-target($link.absolute), '',
    'a target that does not exist displaces nothing either';
ok $link.e, 'and is created, because mount --bind needs something to attach to';

done-testing;

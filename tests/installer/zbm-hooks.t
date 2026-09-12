use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;

# ZFSBootMenu builds its image with generate-zbm, which adds the zfsbootmenu
# hook by itself. The config the package ships also lists the hook, and says
# in its own comment that the two together mean "the module will be marked for
# inclusion twice, which is generally harmless".
#
# It is not harmless. The second pass creates the symlinks the first one made,
# `ln` runs without -f, and no image is produced at all:
#
#     -> Running build hook: [zfsbootmenu]
#     ln: failed to create symbolic link '.../bin/zbm': File exists
#     ==> ERROR: Failed to install ZFSBootMenu core
#
# The installation is otherwise complete when this happens: everything before it
# has worked, so nothing earlier gives any sign of it.
#
# The function is lifted out of the real script rather than reproduced, so
# what is tested is what runs.

my $script = $?FILE.IO.absolute.IO.parent.parent.parent
    .child('airootfs/root/bind-mount/root/install-and-configure-bootloader.sh');
ok $script.e, 'install-and-configure-bootloader.sh is where it is expected';

$script.slurp ~~ / 'drop_implicit_zbm_hook() {' .*? \n '}' /;
my $function = ~$/;
ok $function.chars, 'drop_implicit_zbm_hook can be lifted out to be exercised';

my $conf = $*TMPDIR.child('ditana-zbm-mkinitcpio.conf');

sub hooks-after(Str $line) {
    $conf.spurt("# a comment mentioning zfsbootmenu, which must survive\n$line\nCOMPRESSION=\"zstd\"\n");
    my $proc = run('bash', '-c', "$function\ndrop_implicit_zbm_hook '{$conf.absolute}'", :out, :err);
    $proc.out.slurp(:close);
    $proc.err.slurp(:close);
    $conf.lines.first(*.starts-with('HOOKS='));
}

is hooks-after('HOOKS=(base udev autodetect modconf block filesystems keyboard keymap zfsbootmenu)'),
    'HOOKS=(base udev autodetect modconf block filesystems keyboard keymap)',
    'the explicit hook goes, and nothing else does';

is hooks-after('HOOKS=(base udev zfsbootmenu block)'),
    'HOOKS=(base udev block)',
    'including when it is not the last one';

is hooks-after('HOOKS=(base udev block filesystems keyboard)'),
    'HOOKS=(base udev block filesystems keyboard)',
    'a config that never listed it is left alone';

# Running the installation twice over the same configuration must not eat
# anything further: an installer step that is only correct the first time is
# one that breaks on the day somebody re-runs it.
$conf.spurt("HOOKS=(base udev zfsbootmenu block)\n");
for ^2 {
    my $proc = run('bash', '-c', "$function\ndrop_implicit_zbm_hook '{$conf.absolute}'", :out, :err);
    $proc.out.slurp(:close);
    $proc.err.slurp(:close);
}
is $conf.lines.first(*.starts-with('HOOKS=')), 'HOOKS=(base udev block)',
    'and doing it twice changes no more than doing it once';

is $conf.lines.grep(*.starts-with('HOOKS=')).elems, 1,
    'there is still exactly one HOOKS line';

done-testing;

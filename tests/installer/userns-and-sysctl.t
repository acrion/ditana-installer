use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use Settings;

# A setting declares what it needs - an executable that may create a user
# namespace, a sysctl value - and the installer collects those declarations from
# the settings that are switched on. A declaration is what makes the two
# collectable at all: a sysctl value written as an echo line inside a
# chroot-script cannot be reconciled with another one, and the user namespace
# permission has to exist because Arch no longer ships the setuid bubblewrap
# that would otherwise stand in for it.
#
# The fixture beside this file is the configuration; see its own comments.
my $fixture = $?FILE.IO.absolute.IO.parent.child('fixture').absolute;
chdir $fixture;

my $s = Settings.instance;

# --- the user namespace allowlist -------------------------------------------

my @allow = $s.get-userns-allow-for-enabled-settings;

ok @allow.grep('/usr/bin/bwrap'), 'an executable a switched-on setting asked for is on the list';
ok @allow.grep('/usr/bin/other'), 'a setting may ask for more than one executable';

# The permission travels with the setting, so switching the setting off has to
# take the permission with it. Otherwise an allowlist would keep growing over the
# life of a configuration and nobody would notice the entries nothing needs.
nok @allow.grep('/usr/bin/never'), 'a switched-off setting contributes nothing';

# Flatpak and Bubblejail both need bwrap, so this is the ordinary case rather than
# an exotic one. The loader reads the file line by line and would count a repeated
# path as a second executable.
is @allow.grep('/usr/bin/bwrap').elems, 1, 'an executable two settings ask for appears once';

# --- sysctl values ----------------------------------------------------------

my @values = $s.get-sysctl-values;
my %by-key = @values.map({ $_[0] => $_ });

ok %by-key<kernel.test_alpha>:exists, 'a value a switched-on setting asked for is collected';
is %by-key<kernel.test_alpha>[1], '1', 'the value arrives as it was declared';

# The name goes into the generated file beside the value, so that a line in
# /etc/sysctl.d/ditana.conf can be traced back to the choice that produced it.
is %by-key<kernel.test_alpha>[2], 'needs-userns-a', 'the setting that asked for it is named';

nok %by-key<kernel.test_beta>:exists, 'a switched-off setting contributes no value';

is @values.grep({ $_[0] eq 'kernel.test_alpha' }).elems, 1,
    'two settings asking for the same value produce one line, not two';

# --- the conflict that nothing else would show ------------------------------

# kernel-option-duurn and enable-unprivileged-namespaces write opposite values of
# kernel.unprivileged_userns_clone. As echo lines appended to one file, both are
# written and the last one wins, silently. The two are kept apart
# by their default expressions, and this is what happens if a later edit ever
# breaks that.
$s.set('conflicts-with-a', True);

my $error;
{
    $s.get-sysctl-values;
    CATCH { default { $error = .Str } }
}

ok $error.defined, 'two settings writing one key differently stop the installation';
ok $error && $error.contains('kernel.test_alpha'), 'the message names the key';
ok $error && $error.contains('needs-userns-a') && $error.contains('conflicts-with-a'),
    'the message names both settings, so the user knows which one to switch off';

$s.set('conflicts-with-a', False);
ok $s.get-sysctl-values.elems, 'the collection works again once the contradiction is resolved';

done-testing;

use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use Autoinstall;
use Hostname;
use Settings;

# generate-host-name constructs a name for the new machine, and it may do so
# solely when host-name is empty. An unattended run enters the procedure in the
# same manner as any other run, following the application of the answer file.

my $fixture = $?FILE.IO.absolute.IO.parent.child('fixture').absolute;
chdir $fixture;

my $scratch = $*TMPDIR.child('ditana-host-name-tests');
$scratch.mkdir;

sub apply(Str $kdl, Str $name) {
    my $path = $scratch.child("$name.kdl");
    $path.spurt($kdl);
    autoinstall().load-from($path.absolute);
}

# --- an interactive run -----------------------------------------------------

# Nothing is answered, and host-name stands at the empty default specified by
# the configuration. Every interactive run arrives at the procedure in this
# state, and the dialog requesting the name offers what it generates here.
generate-host-name();
like Settings.instance.get('host-name'), /^ 'ditana-' /,
    'without a host name, one is made up as before';

# --- an unattended run ------------------------------------------------------

# Back to the empty default, which is also where an unattended run begins.
# The answer file for the nightly test installation names no host name, and
# that machine still requires one.
Settings.instance.set-to-default('host-name');
apply(q:to/KDL/, 'without-host-name');
    settings {
        user-name "operator"
    }
    KDL
generate-host-name();
like Settings.instance.get('host-name'), /^ 'ditana-' /,
    'an answer file that names no host name gets one made up';

# What determines the outcome is whether host-name is empty, not whether the
# answer file mentions it. A file giving it as "" results in the machine
# being nameless just like one that leaves the line out entirely, and an empty
# name would ultimately appear in /etc/hostname.
apply(q:to/KDL/, 'empty-host-name');
    settings {
        host-name ""
    }
    KDL
generate-host-name();
like Settings.instance.get('host-name'), /^ 'ditana-' /,
    'an answer file that gives the host name as empty gets one made up as well';

# This is what went wrong: the procedure used to set host-name regardless of
# any prior designation, so a machine whose answer file had named one was
# still installed as ditana- followed by five random letters.
apply(q:to/KDL/, 'with-host-name');
    settings {
        host-name "web-01"
    }
    KDL
generate-host-name();
is Settings.instance.get('host-name'), 'web-01',
    'a host name given in the answer file is the one the machine gets';

done-testing;

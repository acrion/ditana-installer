use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use Autoinstall;
use Settings;

# The user's password is asked for by a dialog inside the chroot, which the
# installer's own gate cannot reach: an unattended run would wait there for
# ever, with the whole system already installed. So the answer file carries
# it -- and only as a hash, because such a file lives on a provisioning
# server and is read by everything that provisions a machine.

my $fixture = $?FILE.IO.absolute.IO.parent.child('fixture').absolute;
chdir $fixture;

my $scratch = $*TMPDIR.child('ditana-password-tests');
$scratch.mkdir;

sub apply(Str $kdl, Str $name) {
    my $path = $scratch.child("$name.kdl");
    $path.spurt($kdl);
    autoinstall().answers.keys.map({ autoinstall().answers{$_}:delete });
    autoinstall().passwords.keys.map({ autoinstall().passwords{$_}:delete });
    autoinstall().load-from($path.absolute);
}

apply(q:to/KDL/, 'hash');
    settings {
        user-name "operator"
    }
    passwords {
        user "$y$j9T$MDf.9Fz0Ov0Xq7Q1$0FDLuG7f2sHhP1oQ1yUcOaK6VU3Zc9lZ1kQhWlKmXo2"
    }
    KDL
is autoinstall().passwords<user>,
    '$y$j9T$MDf.9Fz0Ov0Xq7Q1$0FDLuG7f2sHhP1oQ1yUcOaK6VU3Zc9lZ1kQhWlKmXo2',
    'a hash is taken as given';

# The one that matters. A plaintext password in an answer file is a password
# that has already leaked, and accepting it "for convenience" would turn the
# file into the place people put passwords.
throws-like { apply(q:to/KDL/, 'plaintext') }, Exception, message => /'not a hash'/,
    settings {
        user-name "operator"
    }
    passwords {
        user "correct horse battery staple"
    }
    KDL
    'a plaintext password is refused, and the message says how to make a hash';

# The accounts are a closed list, so that a typo cannot silently set the
# password of nothing at all -- and so that root, which has no password on
# Ditana, cannot quietly acquire one here.
throws-like { apply(q:to/KDL/, 'stray-account') }, Exception, message => /'root'/,
    settings {
        user-name "operator"
    }
    passwords {
        root "$y$j9T$abcdefghijklmnop$0FDLuG7f2sHhP1oQ1yUcOaK6VU3Zc9lZ1kQhWlKmXo2"
    }
    KDL
    'a password for an account an installation does not have is named and refused';

# A file with no passwords block is not an error here: it is an error later,
# in the chroot, where the run stops and says which block is missing. That is
# the right place, because an interactive installation has no passwords block
# either and must keep working.
apply(q:to/KDL/, 'no-passwords');
    settings {
        user-name "operator"
    }
    KDL
nok autoinstall().passwords<user>:exists,
    'an answer file without passwords loads, and carries none';

done-testing;

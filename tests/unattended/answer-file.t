use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use Autoinstall;
use Settings;

# Settings loads the configuration from the current directory, and the answer
# file is checked against exactly what it loaded. The fixture beside this file
# is that configuration; see its own comments for why it is not a copy of
# ditana-config.
my $fixture = $?FILE.IO.absolute.IO.parent.child('fixture').absolute;
chdir $fixture;

my $scratch = $*TMPDIR.child('ditana-answer-file-tests');
$scratch.mkdir;

#| Write an answer file and hand it to the mechanism the way detect() would.
#| Each test gets its own file, so a test that dies leaves nothing behind for
#| the next one.
sub apply(Str $kdl, Str $name = 'answers') {
    my $path = $scratch.child("$name.kdl");
    $path.spurt($kdl);
    autoinstall().answers.keys.map({ autoinstall().answers{$_}:delete });
    autoinstall().load-from($path.absolute);
}

#| Put a setting back to the state it has before anybody answers anything, so
#| that a test about a missing value is not reading one an earlier test left.
sub forget(Str $name) {
    Settings.instance.set($name, '');
}

# --- what an answer file does to the settings ------------------------------

apply(q:to/KDL/);
    settings {
        user-name "operator"
        encrypt-root-partition #false
    }
    KDL

is Settings.instance.get('user-name'), 'operator', 'an answered setting reaches Settings';
is Settings.instance.get('encrypt-root-partition'), False, 'a yes/no answer arrives as a Bool, not as the string "false"';
ok autoinstall-active(), 'loading an answer file switches the installer to unattended';

# A typo in a setting name is the mistake this catches, and it is worth
# catching: the installer would otherwise install a machine that silently
# ignored the line the operator wrote.
throws-like { apply(q:to/KDL/, 'typo') }, Exception, message => /'user-nmae'/,
    settings {
        user-nmae "operator"
    }
    KDL
    'a setting that does not exist is named and stops the run';

throws-like { apply(q:to/KDL/, 'two-values') }, Exception, message => /'exactly one value'/,
    settings {
        user-name "operator" "second"
    }
    KDL
    'a setting given two values is rejected rather than one of them picked';

# A block the installer does not read is indistinguishable, from outside,
# from one it applied. post-install is the block somebody will reach for
# first, and it does not exist yet.
throws-like { apply(q:to/KDL/, 'stray-block') }, Exception, message => /'post-install'/,
    settings {
        user-name "operator"
    }
    post-install {
        run "/usr/local/bin/handover"
    }
    KDL
    'a block that is not settings is named and rejected';

# --- which steps can be skipped --------------------------------------------

my %steps = Settings.instance.installation-steps;

apply(q:to/KDL/, 'steps');
    settings {
        user-name "operator"
        profile-default #false
        profile-server #true
    }
    KDL

ok autoinstall().step-can-be-skipped(%steps<user-name>),
    'a step asking for one setting is skipped when that setting is answered';
ok autoinstall().step-can-be-skipped(%steps{"User Profile"}),
    'a radiolist is skipped when every option it would show is answered';

# install-extra-unavailable is in the same dialog but never available. It is
# not a question this machine would be asked, so requiring an answer for it
# would make an otherwise complete answer file unusable.
apply(q:to/KDL/, 'full-checklist');
    settings {
        install-extra-editor #true
        install-extra-shell #false
    }
    KDL
ok autoinstall().step-can-be-skipped(%steps<Extras>),
    'a checklist ignores the settings it would not show on this machine';

apply(q:to/KDL/, 'categories-full');
    settings {
        profile-default #false
        profile-server #true
        install-extra-editor #true
        install-extra-shell #false
    }
    KDL
ok autoinstall().step-can-be-skipped(%steps{"Configuration Categories"}),
    'a category menu is skipped once every child is answered';

# A procedure decides for itself whether it needs to ask, so nothing is
# assumed about it here. Whatever it does ask reaches the dialog gate, which
# stops and names it -- that is what lets the mapping be incomplete.
apply(q:to/KDL/, 'procedure');
    settings {
        timezone "Europe/Zurich"
    }
    KDL
nok autoinstall().step-can-be-skipped(%steps<choose-region-or-timezone>),
    'a procedure is never assumed to be answered';

# --- a radiolist is one choice, not several booleans ------------------------

# profile-default is the configuration's #true. Naming only the other one has
# to unset it, or every default expression asking about a profile would see
# two of them at once -- which no interactive run can produce, because the
# dialog unchecks the others.
apply(q:to/KDL/, 'radiolist-one');
    settings {
        profile-server #true
    }
    KDL
is Settings.instance.get('profile-default'), False,
    'naming one option of a radiolist unsets the option the configuration had chosen';
is Settings.instance.get('profile-server'), True,
    'and leaves the named one chosen';

throws-like { apply(q:to/KDL/, 'radiolist-two') }, Exception, message => /'profile-default' .* 'profile-server'/,
    settings {
        profile-default #true
        profile-server #true
    }
    KDL
    'naming two options of a radiolist stops the run rather than picking one';

throws-like { apply(q:to/KDL/, 'radiolist-none') }, Exception, message => /'User Profile'/,
    settings {
        profile-default #false
    }
    KDL
    'unsetting the only chosen option without naming another stops the run';

# --- what the file need not name, and what it must --------------------------

# The configuration's own answer is an answer. Demanding that a file repeat it
# would mean a file that has to grow by a line every time ditana-config gains
# a checkbox, and none of those lines would say anything the installer did not
# already know.
apply(q:to/KDL/, 'unanswered-with-default');
    settings {
        user-name "operator"
    }
    KDL
ok autoinstall().step-can-be-skipped(%steps<encrypt-root-partition>),
    'a question the configuration has a value for is not one the file must answer';
is Settings.instance.get('encrypt-root-partition'), False,
    'and that value is left exactly as the configuration had it';

ok autoinstall().step-can-be-skipped(%steps<Extras>),
    'a checklist whose boxes all have configured values needs no answer either';

# The other half of the same rule. A setting standing empty is not a value
# somebody chose, and installing a machine whose user has no name is not a
# thing to do quietly.
forget('user-name');
apply(q:to/KDL/, 'no-user-name');
    settings {
        encrypt-root-partition #true
    }
    KDL
throws-like { autoinstall().step-can-be-skipped(%steps<user-name>) },
    Exception, message => /'user-name'/,
    'a question with nothing behind it stops the run and names the setting';

# The message names settings rather than a box, which is why this is decided
# here and not at the dialog: this is the last point at which the settings
# behind a step are still known.
apply(q:to/KDL/, 'user-name-given');
    settings {
        user-name "operator"
    }
    KDL
ok autoinstall().step-can-be-skipped(%steps<user-name>),
    'and it is satisfied by the answer file naming it';

# A procedure has no known set of settings, so nothing can be demanded of it
# up front. It runs, and the dialog gate catches whatever it asks. This is
# what "no safe default for which disk to erase" comes down to in code.
nok autoinstall().step-can-be-skipped(%steps<select-disk>),
    'a procedure is entered rather than answered for';

done-testing;

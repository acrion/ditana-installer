use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use AskForSetting;
use Autoinstall;
use Settings;

# An input box holds what is typed into it to rules: a host name must be a
# name, a user ID a whole number between 1000 and 60000. An answer file fills
# the box without anybody typing, so the run must hold the answer to the same
# rules, or stop and name the setting.
#
# That used to occur exclusively for a box positioned at the top of the wizard.
# A box located inside a category menu was bypassed alongside the menu itself,
# and a box this machine does not show was not examined: host-name "Web 01!" was
# transferred verbatim into /etc/hostname outside the developer profile, and
# user-id and user-group were checked by nobody.

my $fixture = $?FILE.IO.absolute.IO.parent.child('fixture').absolute;
chdir $fixture;

my $scratch = $*TMPDIR.child('ditana-answered-setting-rules-tests');
$scratch.mkdir;

#| Apply an answer file with no remnants from the prior one, ensuring each
#| test concerns the settings specified by its own file.
sub apply(Str $kdl, Str $name) {
    my $path = $scratch.child("$name.kdl");
    $path.spurt($kdl);
    autoinstall().answers.keys.map({ autoinstall().answers{$_}:delete });
    autoinstall().load-from($path.absolute);
}

my %steps = Settings.instance.installation-steps;

# --- a step this machine does not show --------------------------------------

# The top-level host-name step appears solely for the server profile, and the
# fixture starts with the standard one. In ditana-config this is every machine
# outside the developer profile.
nok Settings.instance.installation-step-is-available('host-name'),
    'with the standard profile, the host-name step at the top is not shown';

apply(q:to/KDL/, 'host-name-invalid');
    settings {
        host-name "Web 01!"
    }
    KDL

throws-like { validate-answered-settings(%steps<host-name>) },
    Exception, message => /'host-name' .* 'Web 01!'/,
    'an answer that breaks the rules of a step this machine does not show stops the run';

# The step contained within the menu carries the same name as the one located at
# the top, so a check requesting availability by name would pass over both.
throws-like { validate-answered-settings(%steps{'Advanced Settings'}) },
    Exception, message => /'host-name'/,
    'and so does the same answer at the step inside a category menu';

# --- however deeply the categories nest -------------------------------------

# The range rule associated with the step also excludes "staff", so a message
# that only names the setting would come even without the type rule. It must be
# a complaint concerning the type.
apply(q:to/KDL/, 'user-group-not-a-number');
    settings {
        user-group "staff"
    }
    KDL
throws-like { validate-answered-settings(%steps{'Advanced Settings'}) },
    Exception, message => /"user-group = 'staff' must be a whole number"/,
    'an answer two category menus down is held to the type its step expects';

apply(q:to/KDL/, 'user-id-out-of-range');
    settings {
        user-id 70000
    }
    KDL
throws-like { validate-answered-settings(%steps{'Advanced Settings'}) },
    Exception, message => /'user-id' .* '1000..60000'/,
    'and to the range its step allows, which the message names';

# The counter-control. A check that stopped every file naming these settings
# would be inferior to none, since it would be circumvented.
apply(q:to/KDL/, 'all-valid');
    settings {
        host-name "web-01"
        user-id 1001
        user-group 1001
    }
    KDL
lives-ok { validate-answered-settings(%steps{'Advanced Settings'}) },
    'answers within the rules pass, however deep their step';
lives-ok { validate-answered-settings(%steps<host-name>) },
    'and at a step this machine does not show';

# --- zero in a whole-number box ---------------------------------------------

# A sudo-timeout set to 0 causes sudo to request the password each time, and
# the step's range permits this. The type rule did not: it took only positive
# numbers, so no file could request 0 without stopping the run. The input box
# applies the same rule (input-box.t).
apply(q:to/KDL/, 'sudo-timeout-zero');
    settings {
        sudo-timeout 0
    }
    KDL
lives-ok { validate-answered-settings(%steps{'Advanced Settings'}) },
    'zero passes the type rule of a whole-number box';

# 7 lies within the range, thus this constitutes the type rule in isolation.
apply(q:to/KDL/, 'sudo-timeout-leading-zero');
    settings {
        sudo-timeout "007"
    }
    KDL
throws-like { validate-answered-settings(%steps{'Advanced Settings'}) },
    Exception, message => /"sudo-timeout = '007' must be a whole number of 0 or more, without leading zeros"/,
    'a leading zero does not, and the message says what does';

# --- a quoted number ---------------------------------------------------------

# A numeric value enclosed in quotation marks satisfies the rules of its box,
# and the setting must subsequently contain that number, as it does following
# the input box. Settings.set performs comparisons as strings, treating "1001"
# and 1001 as the same value and keeping the string form.
apply(q:to/KDL/, 'user-id-quoted');
    settings {
        user-id "1001"
    }
    KDL
is-deeply Settings.instance.get('user-id'), '1001',
    'precondition: a quoted answer arrives as a string';
lives-ok { validate-answered-settings(%steps{'Advanced Settings'}) },
    'a quoted whole number passes the rules of its box';
is-deeply Settings.instance.get('user-id'), 1001,
    'and is then stored as a number';

apply(q:to/KDL/, 'display-size-quoted');
    settings {
        display-size "13.3"
    }
    KDL
lives-ok { validate-answered-settings(%steps<display-size>) },
    'a quoted number with a fraction passes the rules of its box';
is-deeply Settings.instance.get('display-size'), 13.3,
    'and is then stored as a number as well';

# --- where the installation applies them ------------------------------------

# A source assertion, since the loop lives in main.raku, and loading main.raku
# starts an installation. The check must occur before the loop asks whether
# this machine shows the step. Within the branch that skips an answered step,
# it would pass every test above and leave the steps this machine does not
# show unverified once more.
my $main = $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root/main.raku').slurp;
my @loop = $main.substr($main.index('sub main()')).lines;
my $takes   = @loop.first(*.trim.starts-with('my $installation-step ='), :k);
my $checks  = @loop.first(*.trim eq 'validate-answered-settings($installation-step);', :k);
my $decides = @loop.first(*.contains('installation-step-is-available'), :k);

ok $checks.defined,
    'the installation loop checks the answers of every step it reaches, without a condition';

# The condition does not have to appear on the same line as the call. Within
# `if $installation-step<type> eq 'ask-for-setting' { ... }`, the line reads the
# same, and each category menu goes unchecked again. Thus, the call must reside
# within the block that takes the step from the list: no brace separating the
# two may leave a block open. Comment lines do not count, as a brace within a
# sentence opens nothing.
my $left-open = ($takes.defined && $checks.defined && $takes < $checks)
    ?? [+] @loop[$takes ..^ $checks].grep({ !.trim.starts-with('#') })
                                    .map({ .comb('{').elems - .comb('}').elems })
    !! Nil;
ok $left-open.defined && $left-open == 0,
    'in the block of the loop itself, not in one that a condition opens';
ok $checks.defined && $decides.defined && $checks < $decides,
    'before it asks whether this machine shows the step';

done-testing;

use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;

# Which package repository an ISO installs from, and which branch the
# installer comes from, are two different things. Made into one decision, they
# leave the combination the nightly release gate needs unbuildable: the
# installer and configuration users actually have, installing the packages that
# are about to become production.
#
# The decision is lifted out of the real build.sh rather than reproduced, so
# what is tested is what runs.

my $build = $?FILE.IO.absolute.IO.parent.parent.parent.child('build.sh');
ok $build.e, 'build.sh is where it is expected';

my $text = $build.slurp;
$text ~~ / 'apply_testing_patch=n' .*? \n 'fi' \n /;
my $decision = $/ ?? ~$/ !! '';
bail-out 'the patch decision is no longer where build.sh kept it'
    unless $decision.chars;
ok $decision.chars, 'the patch decision can be lifted out';

$text ~~ / '# The configuration tarball follows the branch' .*? \n 'fi' \n /;
my $config = $/ ?? ~$/ !! '';
bail-out 'the configuration-tag decision is no longer where build.sh kept it'
    unless $config.chars;
ok $config.chars, 'the configuration-tag decision can be lifted out too';

#| Run both decisions for one branch and one setting of the flag.
sub decide(Str $branch, Str $flag = '') {
    my $script = "current_branch='$branch'\n"
               ~ ($flag ?? "export DITANA_BUILD_TESTING_ISO='$flag'\n"
                        !! "unset DITANA_BUILD_TESTING_ISO\n")
               ~ $decision ~ $config
               ~ "\necho \"patch=\$apply_testing_patch tag=\$DITANA_CONFIG_TAG\"\n";
    my $proc = run('bash', '-c', $script, :out, :err);
    my $out = $proc.out.slurp(:close).lines.first(*.starts-with('patch='));
    $proc.err.slurp(:close);
    $out // 'FAILED';
}

is decide('main'), 'patch=n tag=latest',
    'a plain main build is the release ISO: production packages, released configuration';

# build.sh runs this suite with DITANA_BUILD_TESTING_ISO already exported -- that
# is how a nightly ISO is asked for. A case that lets that reach it while
# describing a build without the flag passes on its own and fails inside the
# build, where the ISO is simply not written and the one failing line scrolls
# past. A case has to state its own environment rather than inherit one.
{
    temp %*ENV<DITANA_BUILD_TESTING_ISO> = 'y';
    is decide('main'), 'patch=n tag=latest',
        'and it stays that, even while the flag stands in the environment';
    is decide('main', 'y'), 'patch=y tag=latest',
        'while asking for it explicitly still works from that same environment';
}

is decide('testing'), 'patch=y tag=develop-latest',
    'a branch build is the development ISO: testing packages, branch configuration';

# The combination the gate is for. This is what it installs:
# the installer and configuration users have, and the packages that are about
# to replace production.
is decide('main', 'y'), 'patch=y tag=latest',
    'main with DITANA_BUILD_TESTING_ISO installs testing packages with the released configuration';

is decide('main', 'n'), 'patch=n tag=latest',
    'and saying no to the flag leaves the release ISO alone';

# The flag must not reach across to a branch build and change its
# configuration tag, which follows the branch and nothing else.
is decide('testing', 'y'), 'patch=y tag=develop-latest',
    'the flag changes nothing for a branch build, which already patches';

done-testing;

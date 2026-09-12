use v6.d;
use Test;

# A release medium is the versioned state, and mkarchiso makes that easy to
# lose: it copies the profile's airootfs into the system image whole, so any
# file lying in the tree travels into the signed ISO. One did, for months --
# a .orig beside a script, invisible because the personal ignore file of the
# machine that builds lists *.orig, and `git status` on that machine therefore
# never mentioned it.
#
# The check asks git the same question with that file switched off. Everything
# the build itself produces is named in the repository's own .gitignore, so the
# line this draws is: declared in the repository, or not declared at all.

my $build = $?FILE.IO.absolute.IO.parent.parent.parent.child('build.sh');
ok $build.e, 'build.sh is where it is expected';
my $text = $build.slurp;

$text ~~ / '# --- BEGIN versioned-tree' .*? '# --- END versioned-tree' /;
my $block = $/ ?? ~$/ !! '';
bail-out 'the versioned-tree markers are gone from build.sh' unless $block.chars;
ok $block.chars, 'the block can be lifted out';

# Before anything that takes minutes, so that a refusal costs nothing and the
# one question it may ask is asked while somebody is still there to answer.
ok $text.index('# --- BEGIN versioned-tree') < $text.index('tests/installer/run-tests'),
    'the tree is checked before the build does any work';

# A repository to drive the check against: one tracked file, one product the
# repository declares, and whatever strays the case is about.
sub stage(:@strays = (), :$exclude = '', :$personal = '*.orig') {
    my $root = $*TMPDIR.child("versioned-tree-{$*PID}-{(^2**32).pick.base(36)}");
    # The repository gets a directory of its own: the driver script below lives
    # beside it and not in it, or the test would plant the very thing it looks
    # for.
    my $dir = $root.child('repo');
    $dir.mkdir;

    my %env = %*ENV.clone;
    %env<GIT_CONFIG_GLOBAL> = '/dev/null';
    %env<GIT_CONFIG_SYSTEM> = '/dev/null';
    %env<GIT_AUTHOR_NAME> = %env<GIT_COMMITTER_NAME> = 'test';
    %env<GIT_AUTHOR_EMAIL> = %env<GIT_COMMITTER_EMAIL> = 'test@example.invalid';

    sub git(*@args) {
        my $p = run('git', '-C', $dir.absolute, |@args, :out, :err, :%env);
        $p.out.slurp(:close); $p.err.slurp(:close);
    }

    git('init', '-q');
    # The personal ignore file: the rule that exists on one machine and hides a
    # file from every report anybody would look at. Beside the repository and
    # not in it, because a personal ignore file is not part of a checkout --
    # in it, it would be a stray of its own and the clean case would never be
    # clean.
    $root.child('personal-ignore').spurt("$personal\n");
    git('config', 'core.excludesFile', $root.child('personal-ignore').absolute);

    $dir.child('.gitignore').spurt("generated.txt\nbuilt/\n");
    $dir.child('tracked.txt').spurt("tracked\n");
    git('add', '.gitignore', 'tracked.txt');
    git('commit', '-qm', 'initial');

    # What the build produces: untracked, but declared by the repository.
    $dir.child('generated.txt').spurt("produced by the build\n");
    $dir.child('built').mkdir;
    $dir.child('built/artifact').spurt("produced by the build\n");

    # Staged and never committed: this is how a release is normally built --
    # the tree is tested first and committed afterwards -- and it is the line
    # the check draws, so it is worth an assertion of its own.
    $dir.child('staged-addition.txt').spurt("added, not yet committed\n");
    git('add', 'staged-addition.txt');

    for @strays -> $s {
        my $path = $dir.child($s);
        $path.parent.mkdir unless $path.parent.e;
        $path.spurt("stray\n");
    }
    $dir.child('.git/info/exclude').spurt($exclude) if $exclude;

    return $dir, %env;
}

sub drive($dir, %env is copy, :$key = 'ABCD1234', :$patch = 'n',
          :$answer, Bool :$terminal = False) {
    my $file = $dir.parent.child('drive.sh');
    $file.spurt("#!/usr/bin/env bash\n"
              ~ "set -eu\n"
              ~ "cd '{$dir.absolute}'\n"
              ~ "selected_key='$key'\n"
              ~ "apply_testing_patch='$patch'\n"
              ~ $block ~ "\n"
              ~ "echo REACHED-THE-BUILD\n");
    $file.chmod(0o755);

    # On a terminal the answer is typed, not set: an environment variable would
    # answer the question in advance and the prompt this case exists for would
    # never be reached.
    %env<DITANA_REMOVE_UNVERSIONED>:delete;
    %env<DITANA_REMOVE_UNVERSIONED> = $answer if $answer.defined && !$terminal;

    # The status is reported through the output rather than through the exit
    # code of the process Raku spawned: a Proc that ends non-zero throws when it
    # is sunk, and every refusal this pins ends non-zero.
    #
    # Whether stdin is a terminal is what decides if the block asks at all, so
    # neither case may inherit the one the suite happens to be run from:
    # </dev/null for the machine that has nobody to ask, a pty of its own for
    # the case that pins the question.
    #
    # `script -c` runs what it is given through $SHELL, so the caller's own
    # shell decides whether this works at all: a shell that stops at the first
    # external command exiting non-zero -- nushell does -- never reaches the
    # echo that carries the status back, and script then reports a failure that
    # is the staged refusal and not a defect. Both halves therefore run one
    # external command with no shell syntax in it, and $SHELL is named instead
    # of inherited.
    my $wrapper = $dir.parent.child('wrapper.sh');
    $wrapper.spurt("#!/usr/bin/env bash\nbash '{$file.absolute}'\necho \"EXIT-CODE:\$?\"\n");
    %env<SHELL> = '/bin/bash';

    my $proc = $terminal
        ?? run('script', '-qec', "bash '{$wrapper.absolute}'", '/dev/null', :in, :out, :err, :%env)
        !! run('bash', '-c', "exec </dev/null; exec bash '{$wrapper.absolute}'", :out, :err, :%env);
    if $terminal {
        $proc.in.print("$answer\n") if $answer.defined;
        $proc.in.close;
    }
    my $out = $proc.out.slurp(:close) ~ $proc.err.slurp(:close);
    my $rc = $out ~~ / 'EXIT-CODE:' (\d+) / ?? +$0 !! -1;
    return $out, $rc;
}

sub cleanup($dir) { run('rm', '-rf', $dir.parent.absolute, :out, :err) }

# --- a tree that carries only what it should ---------------------------------

my ($dir, %env) = stage();
my ($out, $rc) = drive($dir, %env);
is $rc, 0, 'a tree with nothing but tracked files and declared products builds';
ok $out.contains('REACHED-THE-BUILD'), 'and the build goes on';
nok $out.contains('are not staged either'), 'nothing is reported, because there is nothing to report';
ok $dir.child('generated.txt').e && $dir.child('built/artifact').e,
    'what the repository declares is left where it is';
ok $dir.child('staged-addition.txt').e,
    'and a file that is staged but not yet committed is not a stray';
cleanup($dir);

# --- the file nobody could see ------------------------------------------------

($dir, %env) = stage(strays => ('airootfs/root/stale.sh.orig',));
($out, $rc) = drive($dir, %env, :answer<n>);
is $rc, 1, 'a file hidden by the personal ignore file stops a signed release';
ok $out.contains('airootfs/root/stale.sh.orig'), 'and is named';
ok $dir.child('airootfs/root/stale.sh.orig').e, 'saying no deletes nothing';
cleanup($dir);

($dir, %env) = stage(strays => <airootfs/root/stale.sh.orig doc/notes.txt>.List);
($out, $rc) = drive($dir, %env, :answer<y>);
is $rc, 0, 'saying yes removes them and the build goes on';
ok $out.contains('REACHED-THE-BUILD'), 'which is the point of asking at all';
nok $dir.child('airootfs/root/stale.sh.orig').e, 'the hidden one is gone';
nok $dir.child('doc/notes.txt').e, 'and so is one that was never hidden';
ok $dir.child('generated.txt').e && $dir.child('built/artifact').e,
    'what the repository declares survives the deletion';
cleanup($dir);

# --- a name that the default output would have quoted -------------------------
# `git status` quotes a path with a space in it, and a quoted name deletes
# nothing, or something else. -z is what keeps this honest.

($dir, %env) = stage(strays => ('airootfs/root/an old copy.sh.orig',));
($out, $rc) = drive($dir, %env, :answer<y>);
is $rc, 0, 'a path with a space is handled rather than tripped over';
nok $dir.child('airootfs/root/an old copy.sh.orig').e, 'and it is the file that goes';
cleanup($dir);

# --- with nobody to ask -------------------------------------------------------

($dir, %env) = stage(strays => ('airootfs/root/stale.sh.orig',));
($out, $rc) = drive($dir, %env);
is $rc, 1, 'a build with no terminal and no answer stops rather than deleting';
ok $dir.child('airootfs/root/stale.sh.orig').e, 'and the file is still there afterwards';
nok $out.contains('REACHED-THE-BUILD'), 'nothing was built';
cleanup($dir);

# --- the question, asked on a terminal ----------------------------------------

($dir, %env) = stage(strays => ('airootfs/root/stale.sh.orig',));
($out, $rc) = drive($dir, %env, :answer<n>, :terminal);
is $rc, 1, 'asked on a terminal, an answer of no stops the build';
ok $out.contains('Delete them and build?'), 'so the prompt is reachable, and is a question';
ok $dir.child('airootfs/root/stale.sh.orig').e, 'and nothing was deleted';
cleanup($dir);

($dir, %env) = stage(strays => ('airootfs/root/stale.sh.orig',));
($out, $rc) = drive($dir, %env, :answer<y>, :terminal);
is $rc, 0, 'and an answer of yes, typed, builds';
nok $dir.child('airootfs/root/stale.sh.orig').e, 'with the file gone';
cleanup($dir);

# --- the builds this does not apply to ----------------------------------------
# A Testing ISO is not a release, and neither is one nobody signs. Both are
# built from trees that are meant to be experimented in.

($dir, %env) = stage(strays => ('airootfs/root/stale.sh.orig',));
($out, $rc) = drive($dir, %env, :patch<y>);
is $rc, 0, 'a Testing ISO is built without the question being asked';
ok $dir.child('airootfs/root/stale.sh.orig').e, 'and nothing is deleted for it';
cleanup($dir);

($dir, %env) = stage(strays => ('airootfs/root/stale.sh.orig',));
($out, $rc) = drive($dir, %env, :key(''));
is $rc, 0, 'and so is an ISO nobody signs';
ok $dir.child('airootfs/root/stale.sh.orig').e, 'with nothing deleted either';
cleanup($dir);

# --- the other place a rule can hide ------------------------------------------

($dir, %env) = stage(exclude => "*.orig\n");
($out, $rc) = drive($dir, %env, :answer<y>);
is $rc, 1, 'a rule in .git/info/exclude stops the release too';
ok $out.contains('.git/info/exclude'), 'and the file is named';
nok $out.contains('REACHED-THE-BUILD'), 'because what it hides cannot be accounted for';
cleanup($dir);

($dir, %env) = stage(exclude => "# only a comment\n\n");
($out, $rc) = drive($dir, %env);
is $rc, 0, 'a comment in it is not a rule';
cleanup($dir);

done-testing;

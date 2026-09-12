use v6.d;
use Test;

# mkarchiso signs the rootfs image as root, and root's gpg-agent needs the
# passphrase in its cache to do it. With an empty cache the agent runs a
# pinentry, and where that pinentry cannot come up it waits sixty seconds and
# reports "signing failed: Timeout" -- sixty seconds that live inside gpg-agent
# and that no option reaches. The build is eleven minutes old by then, and its
# cleanup throws the image away.
#
# So build.sh fills that cache itself, and asks the one question it needs a
# person for at the top of the build rather than in the middle of it. Two things
# have to stay true for that to work, and both are what is tested here: every
# question the build asks gpg carries a `--pinentry-mode`, so that no pinentry is
# ever waited for; and the cache is checked again immediately before mkarchiso,
# because `default-cache-ttl` can be shorter than a build.

my $build = $?FILE.IO.absolute.IO.parent.parent.parent.child('build.sh');
ok $build.e, 'build.sh is where it is expected';

my $text = $build.slurp;

#| Cut one marked block out of build.sh. A block that a test runs is marked
#| `# --- BEGIN <slug>` and `# --- END <slug>`; a plain `# --- Something ---` is
#| a section heading and nothing reads it.
sub lift($slug) {
    $text ~~ / '# --- BEGIN ' $slug .*? '# --- END ' $slug /;
    $/ ?? ~$/ !! ''
}

my $asking = lift('credentials-up-front');
my $priming = lift('prime-root-gpg-agent');
bail-out 'the markers are gone from build.sh; nothing to test'
    unless $asking.chars && $priming.chars;
ok $asking.chars,  'the part that asks can be lifted out';
ok $priming.chars, 'and so can the part that runs before mkarchiso';

# --- when each of them happens -----------------------------------------------
# The ordering is the whole point of the arrangement, and every assertion below
# about what the functions do would still pass with the order restored.

my $ask     = $text.index('ensure_signing_possible');
my $sudo    = $text.index('sudo -n true');
my $cargo   = $text.index('cargo build --release');
my $tests   = $text.index('tests/installer/run-tests');
my $tomty   = $text.index('tomty --color --all');
my $prime   = $text.index('prime_root_gpg_agent "$selected_key"');
my $iso     = $text.index('sudo -E mkarchiso');

ok $sudo.defined && $sudo < $cargo,
    'the sudo password is asked for before the Rust compile, not after it';
ok $ask.defined && $ask < $cargo,
    'and so is the passphrase';
ok $ask < $tests && $ask < $tomty,
    'both are asked before either test run, so a started build can be left alone';
ok $prime.defined && $iso.defined && $prime < $iso,
    'the cache is checked again before mkarchiso, not after it';

my $guard = $text.index('if [[ -n "$selected_key" ]]; then');
ok $guard.defined && $guard < $prime,
    'nothing is signed, and nothing asked, without a key';

# Trying the key as root leaves a root-owned keyboxd holding the lock on the
# keybox database, and the export of the public key further down runs as the
# user.
my $asking-ends = $text.index('# --- END credentials-up-front');
my $cleanup = $text.index('sudo pkill keyboxd', $ask);
my $export  = $text.index('gpg --export --armor', $asking-ends);
ok $cleanup.defined && $export.defined && $cleanup < $export,
    'the keyboxd that answering the question started is gone before the export needs the keybox';

# --- what the two of them do -------------------------------------------------
# Driven with sudo and gpg replaced on PATH, so nothing is signed and nobody is
# asked for anything. `--quick` is passed as the first argument: the block that
# asks is skipped for a quick rebuild, which is what lets the functions be called
# one at a time here -- and it is a property worth having anyway.
#
# The stub gpg models the one thing that matters about the real one: with
# `--pinentry-mode error` it signs only when the passphrase is already cached,
# and with `--pinentry-mode loopback` it asks and puts it there.

sub drive($call, Bool :$cached = False, Bool :$ask-ok = True,
          Bool :$cache-after-ask = True, Bool :$terminal = True,
          Bool :$sudo-free = True) {
    my $tag = ($call, $cached, $ask-ok, $cache-after-ask, $terminal, $sudo-free).join('-').subst(/\W/, '', :g);
    my $dir = $*TMPDIR.child("gpg-priming-{$*PID}-$tag");
    $dir.child('bin').mkdir;
    my $calls = $dir.child('calls');
    my $cache = $dir.child('cache');
    $cache.spurt('') if $cached;

    # The state every one of these functions really starts in: the user's
    # keyboxd is running, because the list of secret keys was just read, and it
    # holds the lock on the keybox database. A gpg running as root cannot have
    # that lock until the daemon is gone.
    my $lock = $dir.child('lock');
    $lock.spurt('');

    # sudo without the privileges: drop -E and run the rest. Three things are
    # answered rather than run -- -n and -v, because they ask about sudo itself
    # (SUDO_FREE=0 plays a host that wants a password for both), and the kill of
    # keyboxd, because the point of that call is the lock it releases and
    # running it for real would kill the keyboxd of whoever runs these tests.
    $dir.child('bin/sudo').spurt: q:to/SH/.subst('__CALLS__', $calls.absolute, :g).subst('__LOCK__', $lock.absolute, :g);
        #!/usr/bin/env bash
        for a in "$@"; do
            case $a in
                -n) [[ "${SUDO_FREE:-1}" == 1 ]] || exit 1 ;;
                -v) [[ "${SUDO_FREE:-1}" == 1 ]] && exit 0
                    echo "sudo: a password is required" >&2; exit 1 ;;
            esac
        done
        if [[ "$*" == *pkill*keyboxd* ]]; then
            printf 'pkill:keyboxd\n' >> "__CALLS__"
            rm -f "__LOCK__"
            exit 0
        fi
        args=()
        for a in "$@"; do [[ $a == -E || $a == -n ]] || args+=("$a"); done
        exec "${args[@]}"
        SH

    # Written without interpolation, because a shell ${VAR:-default} is a Raku
    # block.
    $dir.child('bin/gpg').spurt: q:to/SH/.subst('__CALLS__', $calls.absolute, :g).subst('__CACHE__', $cache.absolute, :g).subst('__LOCK__', $lock.absolute, :g);
        #!/usr/bin/env bash
        printf 'args:%s\n' "$*" >> "__CALLS__"
        if [[ -f "__LOCK__" ]]; then
            echo "gpg: Note: database_open 1 waiting for lock (held by 4071969) ..." >&2
            echo "gpg: key not found: Connection timed out" >&2
            exit 2
        fi
        out=""; prev=""; mode=none
        for a in "$@"; do
            [[ $prev == --output ]] && out=$a
            [[ $prev == --pinentry-mode ]] && mode=$a
            prev=$a
        done
        case $mode in
            error)
                [[ -f "__CACHE__" ]] || exit 2
                ;;
            loopback)
                [[ "${ASK_OK:-1}" == 1 ]] || exit 2
                [[ "${CACHE_AFTER_ASK:-1}" == 1 ]] && : > "__CACHE__"
                ;;
            none)
                # The real gpg starts a pinentry here and waits a minute for it.
                # Nothing in build.sh may reach this.
                echo "gpg: a pinentry would have been started" >&2
                exit 9
                ;;
        esac
        [[ -n $out ]] && echo signature > "$out"
        exit 0
        SH

    .IO.chmod(0o755) for $dir.child('bin/sudo'), $dir.child('bin/gpg');

    my $file = $dir.child('drive.sh');
    $file.spurt("export PATH='{$dir.child('bin')}':\$PATH\n"
              ~ "export ASK_OK={$ask-ok ?? 1 !! 0}\n"
              ~ "export CACHE_AFTER_ASK={$cache-after-ask ?? 1 !! 0}\n"
              ~ "export SUDO_FREE={$sudo-free ?? 1 !! 0}\n"
              ~ $asking ~ "\n"
              ~ $priming ~ "\n"
              ~ "$call && echo OK || echo REFUSED\n");

    # Both halves of `[[ -t 0 ]]` are produced here rather than inherited. `run`
    # hands the child whatever standard input this test process has, which is a
    # terminal when the suite is started from a shell and a pipe when it is
    # started by something else -- so a test that inherits it asserts one thing
    # for one caller and the opposite for another. `script` is the cheapest real
    # terminal there is, and /dev/null the cheapest absence of one.
    #
    # $SHELL is named and not inherited: `script -c` runs what it is given
    # through it, so the shell the suite happens to be started from would
    # otherwise decide how the driven script is run.
    my %env = %*ENV.clone;
    %env<SHELL> = '/bin/bash';
    my $proc = $terminal
        ?? run('script', '-qec', "bash '{$file.absolute}' --quick", '/dev/null', :out, :err, :%env)
        !! run('bash', '-c', "exec </dev/null; bash '{$file.absolute}' --quick", :out, :err, :%env);
    my $out = $proc.out.slurp(:close) ~ $proc.err.slurp(:close);
    my $recorded = $calls.e ?? $calls.slurp !! '';

    .unlink for $dir.child('bin/sudo'), $dir.child('bin/gpg');
    .unlink for ($calls, $cache, $lock, $file).grep(*.e);
    $dir.child('bin').rmdir; $dir.rmdir;
    return $out, $recorded;
}

# A quick rebuild signs nothing, so it must not stop and ask for anything.
my ($out, $calls) = drive('true');
nok $calls.contains('args:'), 'a quick rebuild asks gpg nothing at all';

# --- the question, and the answers it can get --------------------------------

($out, $calls) = drive('ensure_signing_possible TESTKEY', :cached);
ok $out.contains('OK'), 'a key the agent can already use needs no question';
is $calls.lines.grep(*.starts-with('args:')).elems, 1, 'and one call finds that out';
ok $calls.contains('--pinentry-mode error'),
    'asked in the one way that cannot start a pinentry';
nok $out.contains('enter it now'), 'nobody is asked for anything';

($out, $calls) = drive('ensure_signing_possible TESTKEY');
ok $out.contains('OK'), 'a key that needs a passphrase is asked about and then signs';
my @gpg = $calls.lines.grep(*.starts-with('args:'));
is @gpg.elems, 3, 'in three calls: ask the agent, ask the person, ask the agent again';
ok @gpg[0].contains('--pinentry-mode error'), 'the first asks the agent';
ok @gpg[1].contains('--pinentry-mode loopback'),
    'the second lets gpg ask on the terminal, so no pinentry is started';
ok @gpg[2].contains('--pinentry-mode error'),
    'the third is the proof that what was typed reached the cache';
ok all(@gpg.map(*.contains('TESTKEY'))),
    'all three name the key that was chosen, not a default';

# The lock is what every root gpg meets, and what the four test cases of the
# diagnostic all died on: keyboxd holds the keybox database, root cannot share
# the user's, and the loser waits twenty seconds and reports a timed-out
# connection -- which says nothing about keys or passphrases.
ok $calls.lines[0].starts-with('pkill:'),
    'keyboxd is gone before the first gpg that runs as root';
nok $out.contains('waiting for lock'),
    'so no call of this build ever waits for that lock';

# The defect the whole arrangement exists for: a gpg call with no
# --pinentry-mode is one that can wait sixty seconds for a pinentry that cannot
# come up. The stub refuses to be that call.
nok $out.contains('a pinentry would have been started'),
    'no call is left that could wait for a pinentry';

($out, $calls) = drive('ensure_signing_possible TESTKEY', :!ask-ok);
ok $out.contains('REFUSED'), 'a refused passphrase stops the build';
ok $out.contains('could not sign'), 'and says what it would have broken';

($out, $calls) = drive('ensure_signing_possible TESTKEY', :!cache-after-ask);
ok $out.contains('REFUSED'),
    'a passphrase that never reached the cache stops the build too';
ok $out.contains('default-cache-ttl'),
    'and names the setting that decides whether it survives the build';

($out, $calls) = drive('ensure_signing_possible TESTKEY', :!terminal);
ok $out.contains('REFUSED'), 'with nobody to ask, the build stops rather than hangs';
ok $out.contains('no terminal'), 'and says so';
is $calls.lines.grep(*.starts-with('args:')).elems, 1, 'having asked the agent, and nothing else';

# --- and again, immediately before mkarchiso ---------------------------------
# The cache can be gone by then. Checking costs one call when it is not.

($out, $calls) = drive('prime_root_gpg_agent TESTKEY', :cached);
ok $out.contains('OK'), 'before mkarchiso, a cache that still holds it is enough';
is $calls.lines.grep(*.starts-with('args:')).elems, 1, 'and nothing more is asked';

($out, $calls) = drive('prime_root_gpg_agent TESTKEY');
ok $out.contains('OK'), 'a cache that has expired is filled again rather than walked into';
is $calls.lines.grep(*.starts-with('args:')).elems, 3, 'by the same three calls as at the top of the build';

# --- having the sudo password before anything long runs ----------------------
# A host that needs no password for sudo at all -- the build VM, with NOPASSWD
# for everything -- is asked for one by `sudo -v` regardless, and a build there
# would end on that line. So the free pass is tested for first, with `-n`.

($out, $calls) = drive('ensure_sudo', :cached);
ok $out.contains('OK'), 'a host that needs no sudo password is not asked for one';

($out, $calls) = drive('ensure_sudo', :cached, :!sudo-free, :!terminal);
ok $out.contains('OK'),
    'a host that does need one, with nobody to ask, is not refused outright';
ok $out.contains('stop at its first step'),
    'it is told instead where the build will stop';

done-testing;

use v6.d;
use Test;

# mkarchiso signs the rootfs image as root, and root's gpg-agent starts out with
# an empty passphrase cache. It therefore runs a pinentry, and where that
# pinentry cannot come up the agent waits sixty seconds and reports
# "signing failed: Timeout" -- sixty seconds that live inside gpg-agent and that
# no option reaches. Three builds died that way, each after eleven minutes.
#
# So build.sh obtains the passphrase before mkarchiso starts, with a mechanism
# that runs no pinentry at all. What is tested here is not that gpg works but
# that this stays arranged the way it has to be: before mkarchiso, only when a
# key was chosen, and proving the cache rather than assuming it.

my $build = $?FILE.IO.absolute.IO.parent.parent.parent.child('build.sh');
ok $build.e, 'build.sh is where it is expected';

my $text = $build.slurp;
$text ~~ / '# --- prime the root GPG agent' .*? '# --- end of prime the root GPG agent' /;
my $block = $/ ?? ~$/ !! '';
bail-out 'the priming markers are gone from build.sh; nothing to test'
    unless $block.chars;
ok $block.chars, 'the priming can be lifted out';

# --- where it stands ---------------------------------------------------------
# The whole point is the moment: after the sudo password and the key selection,
# before the eleven minutes. A call that drifted below mkarchiso would pass every
# other assertion in this file and restore the bug in full.

my $call  = $text.index('prime_root_gpg_agent "$selected_key"');
my $iso   = $text.index('sudo -E mkarchiso');
ok $call.defined, 'build.sh calls the priming';
ok $iso.defined,  'and still runs mkarchiso';
ok $call < $iso,  'the priming happens before mkarchiso, not after it';

# Only when there is something to sign. A build without a key needs no
# passphrase, and asking for one would be a question nobody can answer.
my $guard = $text.index('if [[ -n "$selected_key" ]]; then');
ok $guard.defined && $guard < $call,
    'it sits inside the branch that has a signing key';

# --- what it does ------------------------------------------------------------
# Driven with sudo and gpg replaced on PATH, so nothing is signed and no
# passphrase is asked for. The stub records what it was called with.

sub drive(Bool :$loopback-ok = True, Bool :$batch-ok = True) {
    my $dir = $*TMPDIR.child("gpg-priming-{$*PID}-{$loopback-ok}-{$batch-ok}");
    $dir.child('bin').mkdir;

    # sudo without the privileges: drop -E and run the rest.
    $dir.child('bin/sudo').spurt: q:to/SH/;
        #!/usr/bin/env bash
        args=()
        for a in "$@"; do [[ $a == -E ]] || args+=("$a"); done
        exec "${args[@]}"
        SH

    # gpg without the signing: note the arguments, write the output file the
    # caller will later remove, and fail where the test asks it to. Written
    # without interpolation, because a shell ${VAR:-default} is a Raku block.
    $dir.child('bin/gpg').spurt: q:to/SH/.subst('__CALLS__', $dir.child('calls').absolute);
        #!/usr/bin/env bash
        printf '%s\n' "$*" >> "__CALLS__"
        out=""; prev=""; mode=batch
        for a in "$@"; do
            [[ $prev == --output ]] && out=$a
            [[ $a == loopback ]] && mode=loopback
            prev=$a
        done
        if [[ $mode == loopback ]]; then
            [[ "${LOOPBACK_OK:-1}" == 1 ]] || exit 2
        else
            [[ "${BATCH_OK:-1}" == 1 ]] || exit 2
        fi
        [[ -n $out ]] && echo signature > "$out"
        exit 0
        SH

    .IO.chmod(0o755) for $dir.child('bin/sudo'), $dir.child('bin/gpg');

    my $script = "export PATH='{$dir.child('bin')}':\$PATH\n"
               ~ "export LOOPBACK_OK={$loopback-ok ?? 1 !! 0}\n"
               ~ "export BATCH_OK={$batch-ok ?? 1 !! 0}\n"
               ~ $block ~ "\n"
               ~ "prime_root_gpg_agent TESTKEY && echo PRIMED || echo REFUSED\n";

    my $proc = run('bash', '-c', $script, :out, :err);
    my $out = $proc.out.slurp(:close) ~ $proc.err.slurp(:close);
    my $calls = $dir.child('calls').e ?? $dir.child('calls').slurp !! '';
    $dir.child('calls').unlink if $dir.child('calls').e;
    .unlink for $dir.child('bin/sudo'), $dir.child('bin/gpg');
    $dir.child('bin').rmdir; $dir.rmdir;
    return $out, $calls;
}

my ($out, $calls) = drive();
ok $out.contains('PRIMED'), 'both calls succeeding is a primed agent';
is $calls.lines.elems, 2, 'and it takes exactly two calls to get there';
ok $calls.lines[0].contains('--pinentry-mode loopback'),
    'the first asks on the terminal, so no pinentry is started';
ok $calls.lines[1].contains('--batch') && !$calls.lines[1].contains('loopback'),
    'the second is what mkarchiso itself runs';
ok all($calls.lines.map(*.contains('TESTKEY'))),
    'both name the key that was chosen, not a default';

# A passphrase nobody typed must stop the build here rather than at the signing
# step, where the eleven minutes are already spent.
($out, $calls) = drive(:!loopback-ok);
ok $out.contains('REFUSED'), 'a refused passphrase stops the build';
ok $out.contains('could not sign'), 'and says what it would have broken';
is $calls.lines.elems, 1, 'and does not go on to the second call';

# The one this exists for: the passphrase was given, but it did not end up where
# mkarchiso will look. Assuming it did is how the sixty-second timeout returns.
($out, $calls) = drive(:!batch-ok);
ok $out.contains('REFUSED'), 'a passphrase that never reached the cache stops the build too';
ok $out.contains('default-cache-ttl'),
    'and names the setting that decides whether it survives the build';

done-testing;

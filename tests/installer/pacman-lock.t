use v6.d;
use Test;

# One pacman at a time: the database is held by whoever is using it, and a
# second one does not queue, it fails with
#
#     error: failed to synchronize all databases (unable to lock database)
#
# On a machine that keeps an AUR repository, update-aurto runs on a timer and
# holds the database for minutes while it builds in a chroot. A build that
# starts beside it would die at its first pacman, a quarter of an hour of ISO
# thrown away for a collision that clears itself.
#
# What must not be waited out is any other failure. A pacman that failed for its
# own reasons has already removed its lock file, and retrying it would repeat
# the error until the deadline.

my $build = $?FILE.IO.absolute.IO.parent.parent.parent.child('build.sh');
ok $build.e, 'build.sh is where it is expected';
my $text = $build.slurp;

$text ~~ / '# --- BEGIN pacman-database-lock' .*? '# --- END pacman-database-lock' /;
my $block = $/ ?? ~$/ !! '';
bail-out 'the pacman-database-lock markers are gone from build.sh'
    unless $block.chars;
ok $block.chars, 'the waiting can be lifted out';

# Every pacman the build runs has to go through it, or the one that does not is
# the one the timer collides with.
nok $text.contains('sudo pacman -'),
    'no pacman in build.sh is run without waiting for the database';

sub drive(Bool :$succeeds = True, Bool :$lock-held = False, Bool :$lock-clears = False) {
    my $dir = $*TMPDIR.child("pacman-lock-{$*PID}-{$succeeds}-{$lock-held}-{$lock-clears}");
    $dir.child('bin').mkdir;
    my $db = $dir.child('db');
    $db.mkdir;
    my $lock = $db.child('db.lck');
    my $calls = $dir.child('calls');
    $lock.spurt('') if $lock-held;

    $dir.child('bin/sudo').spurt: q:to/SH/;
        #!/usr/bin/env bash
        args=()
        for a in "$@"; do [[ $a == -E ]] || args+=("$a"); done
        exec "${args[@]}"
        SH

    # Where the build looks for the lock. A stub, so that the test never has to
    # touch the database of the machine it runs on.
    $dir.child('bin/pacman-conf').spurt: q:to/SH/.subst('__DB__', $db.absolute, :g);
        #!/usr/bin/env bash
        [[ ${1:-} == DBPath ]] && echo "__DB__/"
        SH

    # Fails while the lock is held, and on the call after that succeeds --
    # LOCK_CLEARS decides whether whoever held it lets go.
    $dir.child('bin/pacman').spurt: q:to/SH/.subst('__CALLS__', $calls.absolute, :g).subst('__LOCK__', $lock.absolute, :g);
        #!/usr/bin/env bash
        printf 'pacman:%s\n' "$*" >> "__CALLS__"
        attempt=$(wc -l < "__CALLS__")
        if [[ -e "__LOCK__" ]]; then
            # The holder lets go while the second attempt is being made, not
            # before it: the lock has to still be there when the caller looks,
            # or it cannot tell this apart from a failure of its own.
            if [[ "${LOCK_CLEARS:-0}" == 1 && $attempt -ge 2 ]]; then
                rm -f "__LOCK__"
            else
                echo "error: failed to synchronize all databases (unable to lock database)" >&2
                exit 1
            fi
        fi
        [[ "${PACMAN_OK:-1}" == 1 ]] || { echo "error: something else went wrong" >&2; exit 1; }
        exit 0
        SH

    .IO.chmod(0o755) for $dir.child('bin/sudo'), $dir.child('bin/pacman'), $dir.child('bin/pacman-conf');

    my $file = $dir.child('drive.sh');
    $file.spurt("export PATH='{$dir.child('bin')}':\$PATH\n"
              ~ "export PACMAN_OK={$succeeds ?? 1 !! 0}\n"
              ~ "export LOCK_CLEARS={$lock-clears ?? 1 !! 0}\n"
              ~ "export DITANA_PACMAN_POLL_SECONDS=0\n"
              ~ $block ~ "\n"
              ~ "pacman_waiting -Sy && echo OK || echo REFUSED\n");

    my $proc = run('bash', $file.absolute, :out, :err);
    my $out = $proc.out.slurp(:close) ~ $proc.err.slurp(:close);
    my $recorded = $calls.e ?? $calls.slurp !! '';

    .unlink for ($calls, $lock, $file, $dir.child('bin/sudo'),
                 $dir.child('bin/pacman'), $dir.child('bin/pacman-conf')).grep(*.e);
    $dir.child('bin').rmdir; $db.rmdir; $dir.rmdir;
    return $out, $recorded;
}

my ($out, $calls) = drive();
ok $out.contains('OK'), 'a database nobody holds is used straight away';
is $calls.lines.elems, 1, 'in one call';
nok $out.contains('waiting'), 'and nothing is said about waiting';

($out, $calls) = drive(:lock-held, :lock-clears);
ok $out.contains('OK'), 'a database somebody holds is waited for, and then used';
is $calls.lines.elems, 2, 'the second attempt is the one that gets it';
ok $out.contains('held by another process'),
    'and the wait is announced, so a build that sits there says why';

($out, $calls) = drive(:!succeeds);
ok $out.contains('REFUSED'), 'a pacman that fails for its own reasons is not retried';
is $calls.lines.elems, 1, 'so it is run exactly once';
ok $out.contains('something else went wrong'), 'and its own message is what reaches the screen';

done-testing;

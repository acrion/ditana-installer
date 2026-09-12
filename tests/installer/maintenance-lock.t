use v6.d;
use Test;

# A machine that coordinates its maintenance has one lock for the jobs that must
# not overlap, and an ISO build belongs in that queue: half an hour of building
# is exactly the window in which a system update would reboot the machine
# underneath it.
#
# Conditional, because build.sh has to work on a machine that has no such
# mechanism at all -- and because the lock directory lives on tmpfs and belongs
# to a group, so a machine can have the tool and still not be able to use it.
#
# The other half is that `maintenance-lock run` steps aside rather than waiting
# for ever: it says so and exits 0 without running anything. For a timer that is
# right, and for a build somebody is waiting on it is a success reported for an
# ISO that does not exist.

my $build = $?FILE.IO.absolute.IO.parent.parent.parent.child('build.sh');
ok $build.e, 'build.sh is where it is expected';
my $text = $build.slurp;

$text ~~ / '# --- BEGIN maintenance-lock' .*? '# --- END maintenance-lock' /;
my $block = $/ ?? ~$/ !! '';
bail-out 'the maintenance-lock markers are gone from build.sh' unless $block.chars;
ok $block.chars, 'the block can be lifted out';

# It has to come before everything, or the part of the build that runs outside
# the lock is the part that asks for a passphrase and downloads a configuration.
ok $text.index('# --- BEGIN maintenance-lock') < $text.index('# --- BEGIN credentials-up-front'),
    'the lock is taken before anything else the build does';

# The first directory on PATH that holds $name.
sub which(Str:D $name --> IO::Path) {
    (%*ENV<PATH> // '').split(':').grep(*.chars).map(*.IO.child($name)).first({ .e && .x })
}

sub drive(Bool :$tool = True, Bool :$writable = True, Bool :$busy = False,
          Int :$status = 0) {
    my $dir = $*TMPDIR.child("maintenance-lock-{$*PID}-{$tool}-{$writable}-{$busy}-{$status}");
    $dir.child('bin').mkdir;

    # The whole PATH of the driven script, and nothing else on it. maintenance-lock
    # is installed in /usr/bin, so a PATH that can reach coreutils can reach the
    # machine's own lock as well -- and the case below that stands for a machine
    # without the mechanism would drive it for real. What the block itself needs
    # is bash, mktemp and rm; the rest of it is builtins.
    my @needed = <bash mktemp rm>;
    for @needed -> $name {
        my $real = which($name);
        bail-out "this machine has no $name on PATH" unless $real;
        $real.symlink($dir.child('bin').child($name));
    }
    my $lockdir = $dir.child('run');
    $lockdir.mkdir;
    $lockdir.chmod(0o555) unless $writable;

    if $tool {
        $dir.child('bin/maintenance-lock').spurt: q:to/SH/;
            #!/usr/bin/env bash
            # run <holder> --wait <n> -- <command...>
            shift            # run
            shift            # holder
            [[ ${1:-} == --wait ]] && { shift; shift; }
            [[ ${1:-} == -- ]] && shift
            if [[ "${LOCK_BUSY:-0}" == 1 ]]; then
                echo "maintenance-lock: busy, not starting ditana-iso-build"
                exit 0
            fi
            "$@"
            SH
        $dir.child('bin/maintenance-lock').IO.chmod(0o755);
    }

    # What the wrapper re-runs: this same file, which the second time through
    # finds the guard set, writes the marker and reports what a build would.
    # A shebang and the execute bit, because the block re-runs "$0" directly --
    # which is what build.sh is, and what this stands in for.
    my $file = $dir.child('drive.sh');
    $file.spurt("#!/usr/bin/env bash\n"
              ~ "export PATH='{$dir.child('bin')}'\n"
              ~ "export DITANA_MAINTENANCE_LOCK_DIR='{$lockdir.absolute}'\n"
              ~ "export LOCK_BUSY={$busy ?? 1 !! 0}\n"
              ~ $block ~ "\n"
              ~ "echo INNER-RAN\n"
              ~ "exit $status\n");

    $file.chmod(0o755);

    # The suite is run by build.sh, and by the time it runs, build.sh has taken
    # the lock and exported both of these. Inherited, the first turns the guard
    # off -- so the block under test skips itself and every case here measures
    # the driver rather than the block -- and the second points at the marker of
    # the build that is running the suite, which this would then write for it.
    my %env = %*ENV.clone;
    %env<DITANA_ISO_BUILD_HOLDS_LOCK>:delete;
    %env<DITANA_ISO_BUILD_MARKER>:delete;

    my $proc = run('bash', $file.absolute, :out, :err, :%env);
    my $out = $proc.out.slurp(:close) ~ $proc.err.slurp(:close);
    my $rc = $proc.exitcode;

    $lockdir.chmod(0o755);
    .unlink for ($file, $dir.child('bin/maintenance-lock')).grep(*.e);
    # .e follows a symlink, so the links are removed by name rather than by
    # asking whether what they point at is there.
    $dir.child("bin/$_").unlink for @needed;
    $lockdir.rmdir; $dir.child('bin').rmdir; $dir.rmdir;
    return $out, $rc;
}

my ($out, $rc) = drive(:!tool);
ok $out.contains('INNER-RAN'), 'a machine without the mechanism simply builds';
is $rc, 0, 'and its exit status is the build\'s own';

($out, $rc) = drive(:!writable);
ok $out.contains('INNER-RAN'),
    'so does one that has the tool but cannot write where the lock lives';

($out, $rc) = drive();
ok $out.contains('INNER-RAN'), 'where it can be taken, the build runs under it';
is $out.comb('INNER-RAN').elems, 1, 'once, not twice -- the guard stops the re-entry';
is $rc, 0, 'and the status comes back through the lock';

($out, $rc) = drive(:status(3));
is $rc, 3, 'a build that fails under the lock still reports how it failed';

($out, $rc) = drive(:busy);
nok $out.contains('INNER-RAN'), 'a lock somebody else holds means nothing is built';
is $rc, 1, 'and that is a failure, not the success the lock tool reports';
ok $out.contains('never started'), 'said in a sentence that names what did not happen';

# --- the environment the suite is actually run in -----------------------------
# Not a hypothetical: this is how build.sh runs it on a machine where the lock
# can be taken, and it is what made three of the cases above pass while
# measuring nothing.

my $marker = $*TMPDIR.child("maintenance-lock-marker-{$*PID}");
$marker.spurt('');
%*ENV<DITANA_ISO_BUILD_HOLDS_LOCK> = '1';
%*ENV<DITANA_ISO_BUILD_MARKER> = $marker.absolute;

($out, $rc) = drive(:busy);
nok $out.contains('INNER-RAN'),
    'a suite run from inside a build that holds the lock still measures the block';
is $rc, 1, 'and the busy case is still the failure it is';
is $marker.slurp, '',
    'and nothing was written to the marker of the build running the suite';

%*ENV<DITANA_ISO_BUILD_HOLDS_LOCK>:delete;
%*ENV<DITANA_ISO_BUILD_MARKER>:delete;
$marker.unlink;

done-testing;

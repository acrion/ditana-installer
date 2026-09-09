use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;

# An ISO that carries an answer file installs Ditana on the first machine it is
# booted on, without asking anything. The installer looks for one at
# /root/autoinstall.kdl, which in a checkout is airootfs/root/ -- the directory
# the ISO is built from, and the same path the mechanism is exercised at by
# hand. .gitignore keeps such a file out of the repository and therefore out of
# every review; nothing kept it out of the medium.

my $build = $?FILE.IO.absolute.IO.parent.parent.parent.child('build.sh');
ok $build.e, 'build.sh is where it is expected';

my $text = $build.slurp;
$text ~~ / '# --- no answer file on the medium' .*? '# --- end of answer-file check' /;
my $check = $/ ?? ~$/ !! '';
bail-out 'the answer-file check markers are gone from build.sh; nothing to test'
    unless $check.chars;
ok $check.chars, 'the answer-file check can be lifted out';

#| Run the lifted check in a directory shaped like a checkout.
sub verdict(Bool :$with-answer-file --> Str) {
    my $dir = $*TMPDIR.child("medium-answer-file-{$*PID}-{$with-answer-file}");
    $dir.child('airootfs/root').mkdir;
    $dir.child('airootfs/root/autoinstall.kdl').spurt(q:to/KDL/)
        settings {
            install-disk "nvme1n1"
        }
        KDL
        if $with-answer-file;
    my $proc = run('bash', '-c', "cd '$dir' && $check\necho survived",
                   :out, :err);
    my $out = $proc.out.slurp(:close) ~ $proc.err.slurp(:close);
    $dir.child('airootfs/root/autoinstall.kdl').unlink if $with-answer-file;
    $dir.child('airootfs/root').rmdir;
    $dir.child('airootfs').rmdir;
    $dir.rmdir;
    return 'survived' if $out.contains('survived');
    return $out.lines.first(*.starts-with('Refusing')) // "unexpected: $out";
}

is verdict(:!with-answer-file), 'survived',
    'a checkout without an answer file builds';

is verdict(:with-answer-file),
    'Refusing to build: airootfs/root/autoinstall.kdl exists.',
    'a checkout with one is refused, by name';

# The file this test is about must not be here while the suite runs either --
# the suite runs from build.sh, so this is the same check one step earlier, and
# it is the one that would have caught the real thing.
nok $?FILE.IO.absolute.IO.parent.parent.parent
        .child('airootfs/root/autoinstall.kdl').e,
    'and this checkout carries none';

done-testing;

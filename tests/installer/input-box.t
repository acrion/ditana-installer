use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use AskForSetting;
use Settings;

# The input box associated with an ask-for-setting step, featuring a stand-in
# for dialog(1) on PATH: the actual instance requires a terminal. The stand-in
# types the answers it receives into the box, one per attempt, and records the
# text from each message box.
#
# A sudo-timeout set to 0 causes sudo to request the password each time, and
# the step's range permits this. The type rule for a whole-number box did not:
# it took only positive values, thus preventing anyone from entering 0. An
# answer file is bound by the same rule (answered-setting-rules.t).

my $fixture = $?FILE.IO.absolute.IO.parent.child('fixture').absolute;
chdir $fixture;

my $scratch = $*TMPDIR.child('ditana-input-box-tests');
$scratch.mkdir;
my $bin = $scratch.child('bin');
$bin.mkdir;
my $answers = $scratch.child('answers');
my $shown   = $scratch.child('shown');

$bin.child('dialog').spurt: q:to/SH/.subst('__ANSWERS__', $answers.absolute, :g).subst('__SHOWN__', $shown.absolute, :g);
    #!/bin/sh
    while [ $# -gt 0 ]; do
        case $1 in
            --inputbox)
                [ -s '__ANSWERS__' ] || exit 1
                answer=$(head -n 1 '__ANSWERS__')
                sed -i 1d '__ANSWERS__'
                printf '%s' "$answer" >&2
                exit 0 ;;
            --msgbox)
                printf '%s\n' "$2" >> '__SHOWN__'
                exit 0 ;;
        esac
        shift
    done
    exit 0
    SH
$bin.child('dialog').chmod(0o755);
%*ENV<PATH> = "{$bin.absolute}:{%*ENV<PATH>}";

my $sudo-timeout = Settings.instance.installation-steps{'Advanced Settings'}<categories>
                       .first(*<name> eq 'sudo-timeout');

#| Type these into the box, one at a time, and return what the step returned
#| along with the text from every message box displayed in between.
sub type-into(*@typed) {
    $answers.spurt(@typed.map({ "$_\n" }).join);
    $shown.spurt('');
    my $status = ask-for-setting($sudo-timeout);
    $status, $shown.slurp;
}

my ($status, $objections) = type-into('0');
is $status, 0, 'the box takes 0';
is $objections, '', 'without an objection';
is-deeply Settings.instance.get('sudo-timeout'), 0, 'and stores it as the number 0';

($status, $objections) = type-into('007', '480');
is $objections.lines.elems, 1, 'a leading zero is objected to';
like $objections, /'whole number of 0 or more, without leading zeros'/,
    'with a message that says what the box takes';
is $status, 0, 'and the box asks again';
is-deeply Settings.instance.get('sudo-timeout'), 480, 'until it gets a whole number';

.unlink for $answers, $shown, $bin.child('dialog');
$bin.rmdir;

done-testing;

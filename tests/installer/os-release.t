use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use Chroot;

# The installed system says in /usr/lib/os-release which medium built it and
# which configuration it was built from. One of the two entries is already in
# the file -- the base system ships BUILD_ID=rolling -- so appending is not
# enough: it leaves a file with two BUILD_ID lines. `man os-release` makes the
# later one win, so the value read back is still the right one, but a file that
# contradicts itself only works for a reader who knows that rule, and the next
# reader is a script somebody else wrote.

my $scratch = $*TMPDIR.child("ditana-os-release-{$*PID}");
$scratch.mkdir;

sub with-content(Str $content, Str $name = 'os-release') {
    my $path = $scratch.child($name);
    $path.spurt($content);
    $path
}

# --- replacing what is there -------------------------------------------------

my $file = with-content(qq:to/END/, 'replace');
    NAME="Ditana"
    BUILD_ID=rolling
    ID=ditana
    END

set-os-release-key($file, 'BUILD_ID', '0.9.4-Beta-2026-09-12.08');
my @lines = $file.lines;
is @lines.grep(*.starts-with('BUILD_ID=')).elems, 1, 'an entry that exists is replaced, not doubled';
is @lines[1], 'BUILD_ID=0.9.4-Beta-2026-09-12.08', 'and it keeps the place it had';
is @lines[0], 'NAME="Ditana"', 'what stood before it is untouched';
is @lines[2], 'ID=ditana', 'and so is what stood after it';

# --- adding what is not there ------------------------------------------------

$file = with-content("NAME=\"Ditana\"\nID=ditana\n", 'append');
set-os-release-key($file, 'VERSION_CODENAME', '8f8fa8f');
is $file.lines.elems, 3, 'an entry that is missing is added';
is $file.lines[*-1], 'VERSION_CODENAME=8f8fa8f', 'at the end, where nothing is displaced';

# A file whose last line has no newline: appending to that would glue the new
# assignment onto the old one.
$file = with-content("NAME=\"Ditana\"\nID=ditana", 'no-newline');
set-os-release-key($file, 'BUILD_ID', 'rolling');
is $file.lines.elems, 3, 'a file with no closing newline gains a line rather than a longer one';
is $file.lines[1], 'ID=ditana', 'and the line that had none is left as it was';
ok $file.slurp.ends-with("\n"), 'the file ends with a newline afterwards';

# --- what must not be taken for the entry ------------------------------------

$file = with-content("#BUILD_ID=turned-off\nID=ditana\n", 'commented');
set-os-release-key($file, 'BUILD_ID', 'rolling');
is $file.lines[0], '#BUILD_ID=turned-off',
    'a commented-out entry is not an assignment and is left alone';
is $file.lines[*-1], 'BUILD_ID=rolling', 'the real one is added beside it';

$file = with-content("BUILD_ID_EXTRA=x\n", 'prefix');
set-os-release-key($file, 'BUILD_ID', 'rolling');
is $file.lines[0], 'BUILD_ID_EXTRA=x', 'a longer key that begins the same way is a different key';
is $file.lines.elems, 2, 'so the entry is added rather than overwriting it';

# --- what the installation step writes ---------------------------------------

$file = with-content("NAME=\"Ditana\"\nBUILD_ID=rolling\n", 'add-version');
%*ENV<DITANA_BUILD_ID> = '0.9.4-Beta-2026-09-12.08';
%*ENV<DITANA_CONFIG_HASH> = '8f8fa8f';
add-version($file);
is $file.lines.grep(*.starts-with('BUILD_ID=')).elems, 1,
    'the step leaves one BUILD_ID behind, not two';
is $file.lines.grep(*.starts-with('BUILD_ID=')).head, 'BUILD_ID=0.9.4-Beta-2026-09-12.08',
    'and it is the one this build gave it';
is $file.lines.grep(*.starts-with('VERSION_CODENAME=')).head, 'VERSION_CODENAME=8f8fa8f',
    'the configuration it was built from is recorded';

# Running it twice is what a second installation onto the same tree does.
add-version($file);
is $file.lines.grep(*.starts-with('BUILD_ID=')).elems, 1, 'twice changes no more than once';
is $file.lines.grep(*.starts-with('VERSION_CODENAME=')).elems, 1, 'for either entry';

# "unknown" is what an installer reports that never reached a configuration.
# Writing it would claim a codename that names nothing.
$file = with-content("NAME=\"Ditana\"\n", 'unknown');
%*ENV<DITANA_CONFIG_HASH> = 'unknown';
add-version($file);
nok $file.lines.grep(*.starts-with('VERSION_CODENAME=')),
    'a configuration state of "unknown" is not written at all';

%*ENV<DITANA_CONFIG_HASH>:delete;
%*ENV<DITANA_BUILD_ID>:delete;

# --- how the installer calls it ----------------------------------------------
# main.raku dispatches an installation step of type "procedure" by name and
# branches on the arity: anything with a required parameter is handed the exit
# code of the previous step. The path parameter above is optional so that this
# stays a nullary call; making it required would hand add-version an Int.

is &add-version.arity, 0,
    'add-version still takes no required argument, so the dispatcher calls it bare';

done-testing;

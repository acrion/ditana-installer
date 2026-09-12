use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use ConfigState;

# The installer downloads its configuration once and then restarts itself to
# change the console font. Everything the first process published is gone in
# the second one, and the second one is the one that installs the system.
#
# DITANA_CONFIG_HASH is what Chroot's add-version() reads to write
# VERSION_CODENAME into /mnt/usr/lib/os-release. Published inside the block the
# restart skips, it is unset for every installation that goes through the font
# restart -- which is every installation on a virtual terminal -- and the
# installed system then does not say which configuration built it.

my $scratch = $*TMPDIR.child("ditana-config-state-{$*PID}");
$scratch.mkdir;

# --- reading what ditana-config says about itself ----------------------------

$scratch.child('config_hash.txt').spurt("8f8fa8f\n");
$scratch.child('config_date.txt').spurt("2026-09-08 20:15\n");

my %state = config-state($scratch);
is %state<hash>, '8f8fa8f', 'the configuration commit is read from the file beside the installer';
is %state<date>, '2026-09-08 20:15', 'and so is the date it was published';

# A run whose download failed and that fell back to the bundled archive may
# have neither file. "unknown" is what the installed system is told then, and
# add-version() checks for exactly that string before writing anything.
my $empty = $scratch.child('empty');
$empty.mkdir;
my %nothing = config-state($empty);
is %nothing<hash>, 'unknown', 'a missing hash file reads as unknown, not as an empty string';
is %nothing<date>, 'unknown', 'and so does a missing date file';

# --- publishing it for the rest of the installation --------------------------

%*ENV<DITANA_CONFIG_HASH>:delete;
publish-config-state($scratch);
is %*ENV<DITANA_CONFIG_HASH>, '8f8fa8f',
    'publishing puts the hash where Chroot.rakumod reads it';

publish-config-state($empty);
is %*ENV<DITANA_CONFIG_HASH>, 'unknown',
    'and a run without a configuration state says so rather than keeping the last one';

# --- where it is published ---------------------------------------------------
# This is the assertion the defect was about. main() is indented by four
# spaces; the block that the font restart skips is one level deeper. A call
# that drifts back inside it would pass every other assertion in this file.

my $main = $?FILE.IO.absolute.IO.parent.parent.parent
    .child('airootfs/root/main.raku').slurp;

my @calls = $main.lines.grep(*.contains('publish-config-state('));
is @calls.elems, 1, 'the state is published in exactly one place';
ok @calls[0] ~~ / ^ ' ' ** 4 \S /,
    'and that place is the body of main(), not the block a restart skips';

ok $main.index(q[if !'/tmp/ditana-set-font.sh'.IO.e {]) < $main.index('publish-config-state('),
    'it happens after the configuration has been unpacked';

done-testing;

use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use SelectSwapSize;

# The swap partition is sized to bring the machine up to 32 GiB of total
# memory, bounded by what the disk can spare. Both bounds are subtractions,
# and a disk smaller than the installation itself makes them negative -- which
# is the whole reason this file exists.

is swap-recommendation-gib(4, 240), 28,
    'a small machine with a large disk gets swap up to 32 GiB of total memory';
is swap-recommendation-gib(16, 240), 16,
    'a larger machine needs less of it';
is swap-recommendation-gib(32, 240), 0,
    'a machine that already has 32 GiB gets none';
is swap-recommendation-gib(64, 240), 0,
    'and neither does one with more';

is swap-recommendation-gib(4, 100), 20,
    'no more than a fifth of the disk';
is swap-recommendation-gib(4, 60), 12,
    'and no more than what is left once the installation has its 45 GiB';

# 24 GiB of disk is what an unattended installation in QEMU gets. 24/5 = 4, but
# 24 - 45 = -21, and an unclamped -21 reaches sgdisk as `--new=2:0:+-21G`.
# Partitioning then fails with "Could not create partition 2 from 1050624 to 0"
# -- three lines that name the partition and not one word about why. Any disk
# under 45 GiB does this, not only a test one.
is swap-recommendation-gib(4, 24), 0,
    'a disk smaller than the installation needs gets no swap, not negative swap';
is swap-recommendation-gib(4, 45), 0,
    'nor does a disk of exactly the size the installation needs';

ok swap-recommendation-gib(4, 8) >= 0,
    'no disk size produces a negative recommendation';

done-testing;

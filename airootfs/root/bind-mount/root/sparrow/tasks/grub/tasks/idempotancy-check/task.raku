my $new = config()<path>;
my $old = "{$new}.orig";

my $new-cnt = $new.IO.slurp();

my $old-cnt = $old.IO.slurp();

if $new-cnt ne $old-cnt {
    say "CONFIG CHANGED";
} else {
    say "NO CHANGES";
}
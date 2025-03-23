#!raku

my $enable-multilib = config()<enable_multilib>;

if $enable-multilib eq "y" {
  run_task "enable-arch-multilib-repo";
} elseif $enable-multilib eq "n" {
  run_task "disable-arch-multilib-repo";
} else {
  die "enable_multilib is not set";
}



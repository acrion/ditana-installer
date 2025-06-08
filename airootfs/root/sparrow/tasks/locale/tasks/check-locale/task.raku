#!raku

my $locale = config()<locale>;
my $path = config()<locale_gen_path>;

my $content = $path.IO.slurp;
my $pattern = rx/^^ \s* '#'? \s* $locale '.UTF-8' \s+ 'UTF-8' \s* $$/;

unless $content ~~ $pattern {
  die "Error: {$locale}.UTF-8 UTF-8 does not exist in {$path}";
}

say "note: locale {$locale} found in {$path}";

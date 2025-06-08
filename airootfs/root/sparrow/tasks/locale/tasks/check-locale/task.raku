#!raku

my $locale = config()<locale>;
my $path = config()<locale_gen_path>;

my $content = $path.IO.slurp;
my $pattern = rx/^^ \s* '#'? \s* $locale '.UTF-8' \s+ 'UTF-8' \s* $$/;

unless $content ~~ $pattern {
  die "Error: {$locale}.UTF-8 UTF-8 does not exist in {$path}";
}

# generator: << RAKU
# !raku
# say q[^^ \s*   \x[23]  \s*  %locale% '.UTF-8' \s+ 'UTF-8' \s* $$].subst(“%locale%”, config()<locale>);
# RAKU

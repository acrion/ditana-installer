#!raku
my $i = 1;
for lines(config()<path>.IO) -> $v {
    say "$i $v";
    $i++;
}
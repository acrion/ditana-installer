#!raku

for lines(config()<path>.IO) -> $v {
    say $v;
}
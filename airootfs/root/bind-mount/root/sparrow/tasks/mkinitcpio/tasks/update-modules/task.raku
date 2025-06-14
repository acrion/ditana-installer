#!raku

my $path = config()<path>;
my %modules = config()<modules>;

# Only proceed if ZFS and module not already present
if !(%modules<zfs>:exists) {
    my @lines = $path.IO.lines;
    my $modules-line-idx;
    
    # Find MODULES line
    for @lines.kv -> $idx, $line {
        if $line ~~ /^ \s* "MODULES=" / {
            $modules-line-idx = $idx;
            last;
        }
    }
    
    die "MODULES line not found" unless $modules-line-idx.defined;
    
    # Parse and update
    my $modules-line = @lines[$modules-line-idx];
    if $modules-line ~~ /^ \s* "MODULES=" \s* '(' (.*) ')' \s* $/ {
        my @current-modules = $0.Str.words;
        @current-modules.push('zfs');
        @lines[$modules-line-idx] = "MODULES=(" ~ @current-modules.join(' ') ~ ")";
        $path.IO.spurt(@lines.join("\n") ~ "\n");
        say "Added zfs to MODULES in $path";
    }
} else {
    say "ZFS module already present or not needed";
}

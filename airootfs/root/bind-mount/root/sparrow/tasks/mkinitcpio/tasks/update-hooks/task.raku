#!raku

my $path = config()<path>;
my %hooks = config()<hooks>;
my %hooks_rc = config()<hooks_rc>;

# Helper function to check if hook exists
sub hook-exists($hook) {
    return %hooks_rc{$hook}:exists ?? %hooks_rc{$hook} == 0 !! False;
}

# Read the file
my @lines = $path.IO.lines;
my $hooks-line-idx;

# Find HOOKS line
for @lines.kv -> $idx, $line {
    if $line ~~ /^ \s* "HOOKS=" / {
        $hooks-line-idx = $idx;
        last;
    }
}

die "HOOKS line not found" unless $hooks-line-idx.defined;

# Parse current hooks
my $hooks-line = @lines[$hooks-line-idx];
$hooks-line ~~ /^ \s* "HOOKS=" \s* '(' (.*) ')' \s* $/;
my @current-hooks = $0.Str.words;

# Apply modifications based on configuration
my @new-hooks = @current-hooks;

# Handle ZFS
if config()<zfs_filesystem> eq "y" {
    # Add zfs before filesystems if not present
    unless hook-exists('zfs') {
        my $fs-pos = @new-hooks.first(:k, 'filesystems');
        @new-hooks.splice($fs-pos, 0, 'zfs') if $fs-pos.defined;
    }
    # Remove fsck if present
    @new-hooks = @new-hooks.grep(* ne 'fsck');
}

# Handle encryption for all init systems
if config()<encrypt_root_partition> eq "y" and config()<zfs_filesystem> ne "y" {
    # Add keyboard after kms if not present
    unless hook-exists('keyboard') {
        if config()<nvidia_but_no_nouveau> ne "y" {
            my $kms-pos = @new-hooks.first(:k, 'kms');
            @new-hooks.splice($kms-pos + 1, 0, 'keyboard') if $kms-pos.defined;
        } else {
            # If no kms, add keyboard anyway
            unless 'keyboard' ∈ @new-hooks {
                my $pos = @new-hooks.first(:k, 'microcode') // 0;
                @new-hooks.splice($pos + 1, 0, 'keyboard');
            }
        }
    }
}

# Handle NVIDIA
if config()<nvidia_but_no_nouveau> eq "y" {
    @new-hooks = @new-hooks.grep(* ne 'kms');
}

# Handle BusyBox init system
if config()<use_init_systemd> ne "y" {
    # Replace systemd with udev
    @new-hooks = @new-hooks.map({ $_ eq 'systemd' ?? 'udev' !! $_ });
    
    # For encryption, add keymap and consolefont
    if config()<encrypt_root_partition> eq "y" {
        # Add keymap after keyboard
        unless hook-exists('keymap') {
            my $kb-pos = @new-hooks.first(:k, 'keyboard');
            @new-hooks.splice($kb-pos + 1, 0, 'keymap') if $kb-pos.defined;
        }
        
        # Add consolefont after keymap (non-ZFS only)
        if config()<zfs_filesystem> ne "y" and !hook-exists('consolefont') {
            my $km-pos = @new-hooks.first(:k, 'keymap');
            @new-hooks.splice($km-pos + 1, 0, 'consolefont') if $km-pos.defined;
        }
        
        # Add encrypt before filesystems (non-ZFS only)
        if config()<zfs_filesystem> ne "y" and !hook-exists('encrypt') {
            my $fs-pos = @new-hooks.first(:k, 'filesystems');
            @new-hooks.splice($fs-pos, 0, 'encrypt') if $fs-pos.defined;
        }
    }
}

# Handle systemd init system
if config()<use_init_systemd> eq "y" {
    # Replace udev with systemd
    @new-hooks = @new-hooks.map({ $_ eq 'udev' ?? 'systemd' !! $_ });
    
    # Remove keymap unless encrypted ZFS
    unless config()<encrypt_root_partition> eq "y" and config()<zfs_filesystem> eq "y" {
        @new-hooks = @new-hooks.grep(* ne 'keymap');
    }
    
    # Remove consolefont
    @new-hooks = @new-hooks.grep(* ne 'consolefont');
    
    # For LUKS encryption (non-ZFS)
    if config()<encrypt_root_partition> eq "y" and config()<zfs_filesystem> ne "y" {
        # Add sd-vconsole after keyboard
        unless hook-exists('sd-vconsole') {
            my $kb-pos = @new-hooks.first(:k, 'keyboard');
            @new-hooks.splice($kb-pos + 1, 0, 'sd-vconsole') if $kb-pos.defined;
        }
        
        # Add sd-encrypt before filesystems
        unless hook-exists('sd-encrypt') {
            my $fs-pos = @new-hooks.first(:k, 'filesystems');
            @new-hooks.splice($fs-pos, 0, 'sd-encrypt') if $fs-pos.defined;
        }
    }
}

# Write back if changed
if @new-hooks ne @current-hooks {
    @lines[$hooks-line-idx] = "HOOKS=(" ~ @new-hooks.join(' ') ~ ")";
    $path.IO.spurt(@lines.join("\n") ~ "\n");
    say "Updated HOOKS in $path";
} else {
    say "No changes needed for HOOKS";
}

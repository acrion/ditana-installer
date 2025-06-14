#!raku

# First check requirements
run_task "check-requirements";

# Get the current state after checks
my $state = get_state();

# Update hooks based on configuration
run_task "update-hooks", %(
    hooks => $state<hooks> // %(),
    hooks_rc => $state<hooks_rc> // %()
);

# Update modules if needed
if config()<zfs_filesystem> eq "y" {
    run_task "update-modules", %(
        modules => $state<modules> // %()
    );
}

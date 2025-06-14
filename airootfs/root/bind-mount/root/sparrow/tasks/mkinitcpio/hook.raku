#!raku

# First check requirements
my %state = task-run "check-requirements";

# Update hooks based on configuration
task-run "update-hooks", %(
    hooks => %state<hooks> // %(),
    hooks_rc => %state<hooks_rc> // %()
);

# Update modules if needed
if config()<zfs_filesystem> eq "y" {
    task-run "update-modules", %(
        modules => %state<modules> // %()
    );
}

my $path = config()<path>;

my %vars = %(
    path => $path,
    use_init_systemd => config()<use_init_systemd> eq "y",
    zfs_filesystem => config()<zfs_filesystem> eq "y",
    encrypt_root_partition => config()<encrypt_root_partition> eq "y",
    nvidia_but_no_nouveau => config()<nvidia_but_no_nouveau> eq "y",
);


copy $path, "{$path}.orig";

run_task "patch", %(%vars);

run_task "idempotancy-check", %( path => $path );
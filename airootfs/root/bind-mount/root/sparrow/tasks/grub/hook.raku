my $path = config()<path>;

copy $path, "{$path}.orig";

run_task "patch";

run_task "idempotancy-check";
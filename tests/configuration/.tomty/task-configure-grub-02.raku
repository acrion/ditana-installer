#!raku

# Test that GRUB_DISTRIBUTOR is set to Ditana

=begin tomty
%(
  tag => ["grub"]
);
=end tomty

copy "examples/grub", "/tmp/grub-distributor";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/grub>,
  vars => "path=/tmp/grub-distributor,kernel_options=quiet,encrypt_root_partition=n,enable_os_prober=n",
);

task-run "tasks/grub-config-check", %(
  :path</tmp/grub-distributor>,
  :20timeout,
  :kernel_options<quiet>,
);

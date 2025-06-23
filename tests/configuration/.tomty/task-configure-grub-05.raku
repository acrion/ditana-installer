#!raku

# Test configuration with empty kernel options

=begin tomty
%(
  tag => ["grub"]
);
=end tomty

copy "examples/grub", "/tmp/grub-empty-kernel";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/grub>,
  vars => "path=/tmp/grub-empty-kernel,kernel_options=,encrypt_root_partition=n,enable_os_prober=n",
);

task-run "tasks/grub-empty-kernel-check", %(
  :path</tmp/grub-empty-kernel>,
);

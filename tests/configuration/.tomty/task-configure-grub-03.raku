#!raku

# Test configuration without encryption

=begin tomty
%(
  tag => ["grub"]
);
=end tomty


copy "examples/grub", "/tmp/grub-no-crypto";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/grub>,
  vars => "path=/tmp/grub-no-crypto,kernel_options=quiet\ splash,encrypt_root_partition=n,enable_os_prober=n",
);

task-run "tasks/grub-no-crypto-check", %(
  :path</tmp/grub-no-crypto>,
  :kernel_options<quiet splash>,
);
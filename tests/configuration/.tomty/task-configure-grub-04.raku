#!raku

# Test configuration without OS prober

=begin tomty
%(
  tag => ["grub"]
);
=end tomty

copy "examples/grub", "/tmp/grub-no-osprober";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/grub>,
  vars => "path=/tmp/grub-no-osprober,kernel_options=loglevel=3,encrypt_root_partition=y,enable_os_prober=n",
);

task-run "tasks/grub-no-osprober-check", %(
  :path</tmp/grub-no-osprober>,
);

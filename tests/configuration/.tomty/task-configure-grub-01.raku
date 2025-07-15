#!raku

=begin tomty
%(
  tag => ["grub"]
);
=end tomty

copy "examples/grub", "/tmp/grub";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/grub>,
  vars => "path=/tmp/grub,kernel_options=abc,encrypt_root_partition=y,enable_os_prober=y",
);

task-run "tasks/grub-config-check", %(
  :path</tmp/grub>,
  :20timeout,
  :kernel_options<abc>,
  :enable_crypto_disk,
  :enable_os_prober,
);


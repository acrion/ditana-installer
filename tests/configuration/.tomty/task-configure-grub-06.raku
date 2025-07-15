#!raku

# Comprehensive test with all settings enabled

=begin tomty
%(
  tag => ["grub"]
);
=end tomty

copy "examples/grub", "/tmp/grub-comprehensive";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/grub>,
  vars => "path=/tmp/grub-comprehensive,kernel_options=quiet\ splash\ loglevel=3\ rd.systemd.show_status=false,encrypt_root_partition=y,enable_os_prober=y",  
);

task-run "tasks/grub-config-check", %(
  :path</tmp/grub-comprehensive>,
  :20timeout,
  kernel_options => "quiet splash loglevel=3 rd.systemd.show_status=false",
  :enable_crypto_disk,
  :enable_os_prober,
);


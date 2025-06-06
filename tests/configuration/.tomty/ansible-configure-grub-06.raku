#!raku

# Comprehensive test with all settings enabled

copy "examples/grub", "/tmp/grub-comprehensive";

task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/bind-mount/root/configure-grub.yaml>,
  vars => "grub_path=/tmp/grub-comprehensive kernel_options='quiet splash loglevel=3 rd.systemd.show_status=false' encrypt_root_partition=y enable_os_prober=y",
);

task-run "tasks/grub-config-check", %(
  :path</tmp/grub-comprehensive>,
  :20timeout,
  kernel_options => "quiet splash loglevel=3 rd.systemd.show_status=false"
  :enable_crypto_disk,
  :enable_os_prober,
);


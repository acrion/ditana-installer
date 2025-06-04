#!raku

copy "examples/grub", "/tmp/grub";

task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/bind-mount/root/configure-grub.yaml>,
  vars => "grub_path=/tmp/grub kernel_options=abc encrypt_root_partition=y enable_os_prober=y",

);

task-run "tasks/grub-config-check", %(
  :path</tmp/grub>,
  :20timeout,
  :kernel_options<abc>,
  :enable_crypto_disk,
);


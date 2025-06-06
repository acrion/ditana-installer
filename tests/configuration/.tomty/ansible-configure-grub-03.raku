#!raku

# Test configuration without encryption

copy "examples/grub", "/tmp/grub-no-crypto";

task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/bind-mount/root/configure-grub.yaml>,
  vars => "grub_path=/tmp/grub-no-crypto kernel_options='quiet splash' encrypt_root_partition=n enable_os_prober=n",
);

task-run "tasks/grub-no-crypto-check", %(
  :path</tmp/grub-no-crypto>,
  :kernel_options<quiet splash>,
);
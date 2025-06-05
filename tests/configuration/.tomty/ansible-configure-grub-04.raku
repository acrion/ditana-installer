#!raku

# Test configuration without OS prober

copy "examples/grub", "/tmp/grub-no-osprober";

task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/bind-mount/root/configure-grub.yaml>,
  vars => "grub_path=/tmp/grub-no-osprober kernel_options='loglevel=3' encrypt_root_partition=y enable_os_prober=n",
);

task-run "tasks/grub-no-osprober-check", %(
  :path</tmp/grub-no-osprober>,
);

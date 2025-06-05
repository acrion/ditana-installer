#!raku

# Test that GRUB_DISTRIBUTOR is set to Ditana

copy "examples/grub", "/tmp/grub-distributor";

task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/bind-mount/root/configure-grub.yaml>,
  vars => "grub_path=/tmp/grub-distributor kernel_options=quiet encrypt_root_partition=n enable_os_prober=n",
);

task-run "tasks/grub-distributor-check", %(
  :path</tmp/grub-distributor>,
);

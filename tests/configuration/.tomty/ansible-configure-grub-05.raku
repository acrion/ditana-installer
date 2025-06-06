#!raku

# Test configuration with empty kernel options

copy "examples/grub", "/tmp/grub-empty-kernel";

task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/bind-mount/root/configure-grub.yaml>,
  vars => "grub_path=/tmp/grub-empty-kernel kernel_options= encrypt_root_partition=n enable_os_prober=n",
);

task-run "tasks/grub-empty-kernel-check", (
  :path</tmp/grub-empty-kernel>,
);

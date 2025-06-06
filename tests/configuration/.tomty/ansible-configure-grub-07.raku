#!raku

# Test idempotency - run the playbook twice and check that nothing changes the second time

copy "examples/grub", "/tmp/grub-idempotent";

# First run
task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/bind-mount/root/configure-grub.yaml>,
  vars => "grub_path=/tmp/grub-idempotent kernel_options='quiet splash' encrypt_root_partition=y enable_os_prober=y",
);

# Second run - should not change anything
task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/bind-mount/root/configure-grub.yaml>,
  vars => "grub_path=/tmp/grub-idempotent kernel_options='quiet splash' encrypt_root_partition=y enable_os_prober=y",
  :with-idempotency,
);

task-run "tasks/grub-config-check", %(
  :path</tmp/grub-idempotent>,
  :20timeout,
  kernel_options => "quiet splash",
  :enable_crypto_disk,
  :enable_os_prober,
);


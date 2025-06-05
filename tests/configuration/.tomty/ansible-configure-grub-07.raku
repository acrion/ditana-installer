#!raku

# Test idempotency - run the playbook twice and check that nothing changes the second time

copy "examples/grub", "/tmp/grub-idempotent";

# First run
task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/bind-mount/root/configure-grub.yaml>,
  vars => "grub_path=/tmp/grub-idempotent kernel_options='quiet splash' encrypt_root_partition=y enable_os_prober=y",
);

# Second run - should not change anything
task-run "tasks/run-ansible-idempotent", %(
  :playbook<../../airootfs/root/bind-mount/root/configure-grub.yaml>,
  vars => "grub_path=/tmp/grub-idempotent kernel_options='quiet splash' encrypt_root_partition=y enable_os_prober=y",
);

task-run "tasks/grub-idempotent-check", %(
  :path</tmp/grub-idempotent>,
);

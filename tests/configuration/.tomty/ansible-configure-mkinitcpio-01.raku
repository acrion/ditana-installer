#!raku

copy "examples/mkinitcpio.conf", "/tmp/mkinitcpio.conf";

task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/bind-mount/root/configure-mkinitcpio.yaml>,
  vars => "path=/tmp/mkinitcpio.conf zfs_filesystem=y encrypt_root_partition=n use_init_systemd=y nvidia_but_no_nouveau=n",
);

task-run "tasks/mkinitcpio-config-check", %(
  :path</tmp/mkinitcpio.conf>,
  :with-zfs,
);


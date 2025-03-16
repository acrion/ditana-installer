#!raku

copy "examples/pacman2.conf", "/tmp/pacman.conf";

task-run "tasks/run-ansible", %(
  :should_fail,
  :playbook<../../airootfs//root/bind-mount/root/enable-arch-multilib-repo.yaml>,
  vars => "enable_multilib=n config_path=/tmp/pacman.conf",
  :error_message<Missing multilib configuration in pacman.conf>,
);


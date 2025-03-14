#!raku

copy "examples/pacman3.conf", "/tmp/pacman.conf";

task-run "tasks/run-ansible", %(
  :playbook<../../airootfs//root/bind-mount/root/enable-arch-multilib-repo.yaml>,
  vars => "enable_multilib=y config_path=/tmp/pacman.conf",
);

task-run "tasks/arch-multilib-repo-is-enabled", %(
  :path</tmp/pacman.conf>,
);

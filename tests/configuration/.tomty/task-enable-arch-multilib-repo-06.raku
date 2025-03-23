#!raku

copy "examples/pacman3.conf", "/tmp/pacman.conf";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/pacman>,
  vars => "enable_multilib=n,path=/tmp/pacman.conf",
);

task-run "tasks/arch-multilib-repo-is-disabled", %(
  :path</tmp/pacman.conf>,
);
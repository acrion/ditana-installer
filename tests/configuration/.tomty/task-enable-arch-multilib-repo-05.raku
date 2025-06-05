#!raku

copy "examples/pacman3.conf", "/tmp/pacman.conf";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/pacman>,
  vars => "enable_multilib=y,path=/tmp/pacman.conf",
);

task-run "tasks/arch-multilib-repo-is-enabled", %(
  :path</tmp/pacman.conf>,
);
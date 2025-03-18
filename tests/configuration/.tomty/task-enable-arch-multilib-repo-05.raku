#!raku

copy "examples/pacman3.conf", "/tmp/pacman.conf";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/enable-arch-multilib-repo>,
  vars => "enable_multilib=y,path=/tmp/pacman.conf",
  :should_fail,
  :error_message<Missing multilib configuration in pacman.conf>,
);


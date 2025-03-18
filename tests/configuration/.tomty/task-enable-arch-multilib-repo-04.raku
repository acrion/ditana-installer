#!raku

copy "examples/pacman2.conf", "/tmp/pacman.conf";

task-run "tasks/run-task", %(
  :should_fail, 
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/enable-arch-multilib-repo>,
  vars => "enable_multilib=n,path=/tmp/pacman.conf",
  :error_message<Missing multilib configuration in pacman.conf>,
);

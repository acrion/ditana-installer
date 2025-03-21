#!raku

copy "examples/pacman1.conf", "/tmp/pacman.conf";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/pacman>,
  vars => "action=enable-arch-multilib-repo,enable_multilib=n,path=/tmp/pacman.conf",
);

task-run "tasks/arch-multilib-repo-is-commented", %(
  :path</tmp/pacman.conf>,
);

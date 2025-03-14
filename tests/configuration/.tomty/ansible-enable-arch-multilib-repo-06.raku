#!raku

copy "examples/pacman3.conf", "/tmp/pacman.conf";

bash q:to /CODE/, %( :description<run ansible> );
  ansible-playbook -i localhost, \
  ../../airootfs//root/bind-mount/root/enable-arch-multilib-repo.yaml \
  -e "enable_multilib=n config_path=/tmp/pacman.conf"
CODE

task-run "tasks/arch-multilib-repo-is-commented", %(
  :path</tmp/pacman.conf>,
);

#!raku

copy "examples/pacman2.conf", "/tmp/pacman.conf";

bash q:to /CODE/, %( :description<run ansible> );
  ansible-playbook -i localhost, \
  ../../airootfs//root/bind-mount/root/enable-arch-multilib-repo.yaml \
  -e "enable_multilib=y config_path=/tmp/pacman.conf"
CODE

task-run "tasks/arch-multilib-repo-is-enabled", %(
  :path</tmp/pacman.conf>,
);

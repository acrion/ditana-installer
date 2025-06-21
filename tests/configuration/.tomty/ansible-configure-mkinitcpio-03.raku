#!raku

=begin tomty
%(
  tag => ["mkinitcpio", "busybox", "without-zfs", "without-encrypt-root-partition","with-nvidia-but-no-nouveau"]
);
=end tomty

copy "examples/mkinitcpio.conf", "/tmp/mkinitcpio.conf";

my $s = task-run "tasks/mkinitcpio-config-parser", %(
  :path</tmp/mkinitcpio.conf>,
);

my $hooks = $s<hooks>;
my $mods = $s<mods>;

task-run "tasks/run-task", %(
  :task<../../airootfs/root/sparrow/tasks/mkinitcpio>,
  vars => "path=/tmp/mkinitcpio.conf,zfs_filesystem=n,encrypt_root_partition=n,use_init_systemd=n,nvidia_but_no_nouveau=y",
);

task-run "tasks/mkinitcpio-config-check", %(
  :path</tmp/mkinitcpio.conf>,
  :!with-zfs,
  :!use-init-systemd,
  :nvidia-but-no-nouveau,
  :$hooks,
  :$mods,
);


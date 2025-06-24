#!raku

=begin tomty
%(
  tag => ["mkinitcpio", "systemd", "with-zfs", "with-encrypt-root-partition","without-nvidia-but-no-nouveau"]
);
=end tomty

copy "examples/mkinitcpio.conf", "/tmp/mkinitcpio.conf";

my $s = task-run "tasks/mkinitcpio-config-parser", %(
  :path</tmp/mkinitcpio.conf>,
);

my $hooks = $s<hooks>;
my $mods = $s<mods>;

task-run '../../airootfs/root/bind-mount/root/sparrow/tasks/mkinitcpio', %(
  path => '/tmp/mkinitcpio.conf',
  zfs_filesystem => 'y',
  encrypt_root_partition => 'y',
  use_init_systemd => 'y',
  nvidia_but_no_nouveau => 'n',
);

task-run "tasks/mkinitcpio-config-check", %(
  :path</tmp/mkinitcpio.conf>,
  :with-zfs,
  :use-init-systemd,
  :encrypt-root-partition,
  :$hooks,
  :$mods,
);

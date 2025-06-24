#!raku

=begin tomty
%(
  tag => ["mkinitcpio", "idempotance"]
);
=end tomty

copy "examples/mkinitcpio.conf", "/tmp/mkinitcpio.conf";

my $s = task-run '../../airootfs/root/bind-mount/root/sparrow/tasks/mkinitcpio', %(
  path => '/tmp/mkinitcpio.conf',
  zfs_filesystem => 'y',
  encrypt_root_partition => 'n',
  use_init_systemd => 'y',
  nvidia_but_no_nouveau => 'n',
);

die "state should change" unless $s<changed>;

$s = task-run '../../airootfs/root/bind-mount/root/sparrow/tasks/mkinitcpio', %(
  path => '/tmp/mkinitcpio.conf',
  zfs_filesystem => 'y',
  encrypt_root_partition => 'n',
  use_init_systemd => 'y',
  nvidia_but_no_nouveau => 'n',
);

die "state should not change" if $s<changed>;

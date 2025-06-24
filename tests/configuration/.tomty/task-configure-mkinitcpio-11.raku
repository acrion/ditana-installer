#!raku

=begin tomty
%(
  tag => ["mkinitcpio", "negative"]
);
=end tomty

copy "examples/mkinitcpio.broken.conf", "/tmp/mkinitcpio.conf";

my $s = task-run "tasks/mkinitcpio-config-parser", %(
  :path</tmp/mkinitcpio.conf>,
);

my $hooks = $s<hooks>;
my $mods = $s<mods>;

task-run "tasks/run-task", %(
  :should_fail,
  :error_message<TASK CHECK FAIL>,
  :task<../../airootfs/root/bind-mount/root/sparrow/tasks/mkinitcpio>,
  vars => "path=/tmp/mkinitcpio.conf,zfs_filesystem=n,encrypt_root_partition=y,use_init_systemd=y,nvidia_but_no_nouveau=y",
);


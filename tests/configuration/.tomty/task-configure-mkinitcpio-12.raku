#!raku

=begin tomty
%(
  tag => ["mkinitcpio", "negative"]
);
=end tomty

copy "examples/mkinitcpio.broken.conf", "/tmp/mkinitcpio.conf";

task-run "tasks/run-task", %(
  task => '../../airootfs/root/bind-mount/root/sparrow/tasks/mkinitcpio',
  :should_fail,
  :error_message<TASK CHECK FAIL>,
  vars => "path=/tmp/mkinitcpio.conf",
);


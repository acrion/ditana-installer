#!raku

copy "examples/locale.conf", "/tmp/locale.conf";
copy "examples/locale.gen", "/tmp/locale.gen";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/sparrow/tasks/locale>,
  vars => "locale=en_US,use_c_utf8=n,locale_gen_path=/tmp/locale.gen,locale_conf_path=/tmp/locale.conf",
);

task-run "tasks/locale-is-activated", %(
  :path</tmp/locale.gen>,
  :locale<en_US>,
);

task-run "tasks/locale-conf-uses-user-locale", %(
  :path</tmp/locale.conf>,
  :locale<en_US>,
);

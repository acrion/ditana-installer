#!raku

copy "examples/locale.conf", "/tmp/locale.conf";
copy "examples/locale.gen", "/tmp/locale.gen";

task-run "tasks/run-task", %(
  :task<../../airootfs/root/sparrow/tasks/locale>,
  vars => "locale=de_DE,use_c_utf8=y,locale_gen_path=/tmp/locale.gen,locale_conf_path=/tmp/locale.conf",
);

task-run "tasks/locale-is-activated", %(
  :path</tmp/locale.gen>,
  :locale<de_DE>,
);

task-run "tasks/locale-conf-uses-c-utf8", %(
  :path</tmp/locale.conf>,
  :locale<de_DE>,
);

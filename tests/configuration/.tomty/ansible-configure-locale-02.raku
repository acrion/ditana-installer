#!raku

copy "examples/locale.gen", "/tmp/locale.gen";

task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/ansible/configure_locale.yaml>,
  vars => "locale=de_DE use_c_utf8=y locale_gen_path=/tmp/locale.gen locale_conf_path=/tmp/locale.conf",
);

task-run "tasks/locale-is-activated", %(
  :path</tmp/locale.gen>,
  :locale<de_DE>,
);

task-run "tasks/locale-conf-uses-c-utf8", %(
  :path</tmp/locale.conf>,
  :locale<de_DE>,
);

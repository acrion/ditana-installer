#!raku

copy "examples/locale.gen", "/tmp/locale.gen";

task-run "tasks/run-ansible", %(
  :playbook<../../airootfs/root/ansible/configure_locale.yaml>,
  vars => "locale=fr_FR use_c_utf8=n locale_gen_path=/tmp/locale.gen locale_conf_path=/tmp/locale.conf",
);

task-run "tasks/locale-is-activated", %(
  :path</tmp/locale.gen>,
  :locale<fr_FR>,
);

task-run "tasks/locale-conf-uses-user-locale", %(
  :path</tmp/locale.conf>,
  :locale<fr_FR>,
);
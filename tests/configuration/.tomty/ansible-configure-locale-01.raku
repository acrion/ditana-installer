#!raku

copy "examples/locale.conf", "/tmp/locale.conf";
copy "examples/locale.gen", "/tmp/locale.gen";

task-run "tasks/run-ansible", %(
  :should_fail,
  :playbook<../../airootfs/root/ansible/configure_locale.yaml>,
  vars => "locale=invalid_locale use_c_utf8=y locale_gen_path=/tmp/locale.gen locale_conf_path=/tmp/locale.conf",
  :error_message<Error: invalid_locale.UTF-8 UTF-8 does not exist in /tmp/locale.gen>,
);

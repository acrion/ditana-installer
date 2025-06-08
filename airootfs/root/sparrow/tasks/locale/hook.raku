#!raku

set_stdout("configuring locale $(config()<locale>) (use_c_utf8: $(config()<use_c_utf8>))");

run_task "check-locale";
run_task "activate-locale";
run_task "write-locale-conf";

# Always activate en_US if it's not the selected locale
if config()<locale> ne 'en_US' {
  run_task "activate-en-us";
}

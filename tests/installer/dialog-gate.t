use v6.d;
use lib $?FILE.IO.absolute.IO.parent.parent.parent.child('airootfs/root').absolute;
use Test;
use Dialogs;

# show-dialog-raw is where an unattended run either skips a box or stops at
# it. Which of the two it does is decided by dialog-is-a-question, and that
# decision is what is tested here -- running dialog itself would need a
# terminal and would prove nothing about the choice.

ok dialog-is-a-question(<--menu Pick 20 70 4 1 one>), 'a menu asks';
ok dialog-is-a-question(<--yesno Really? 5 40>), 'a yes/no box asks';
ok dialog-is-a-question(<--inputbox Name 10 50>), 'an input box asks';
ok dialog-is-a-question(<--passwordbox Passphrase 10 50>), 'a passphrase box asks';
ok dialog-is-a-question(<--checklist Pick 20 70 4 1 one off>), 'a checklist asks';
ok dialog-is-a-question(<--radiolist Pick 20 70 4 1 one off>), 'a radiolist asks';
ok dialog-is-a-question(<--editbox /tmp/x 20 70>), 'an edit box asks';

nok dialog-is-a-question(<--infobox Working 4 65>), 'an info box tells';
nok dialog-is-a-question(<--msgbox Hello 10 50>), 'a message box tells';
nok dialog-is-a-question(<--gauge Working 7 60 0>), 'a gauge tells';
nok dialog-is-a-question(<--programbox Output 20 70>), 'a program box tells';

# The welcome screen is a --msgbox preceded by --no-collapse. Taking the
# first option that is not --title for the box type made it look like a
# question, so an answer file that had nothing left to answer still stopped
# on the very first screen.
nok dialog-is-a-question(('--no-collapse', '--msgbox', 'Welcome to Ditana', 40, 98)),
    'a common option before the box does not turn a message into a question';

# The same mistake the other way round: the timezone menu is preceded by
# --title and --default-item, and it does ask.
ok dialog-is-a-question(('--title', 'Time Zone', '--default-item', '3', '--menu', 'Select:', 21, 70, 18)),
    'options before a menu do not hide that it asks';

# A dialog whose box option is not recognised is treated as a question. The
# two mistakes do not cost the same: stopping wrongly leaves a message naming
# the box, while skipping wrongly installs a machine to an answer nobody gave.
ok dialog-is-a-question(<--title Something --some-future-box text>),
    'an unrecognised box is assumed to ask';

is dialog-box-option(('--title', 'Time Zone', '--menu', 'Select:')), '--menu',
    'the box option is reported by name, so the error message can carry it';

done-testing;

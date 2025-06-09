#!raku

my $locale = config()<locale>;
my $use-c-utf8 = config()<use_c_utf8>;
my $path = config()<locale_conf_path>;

my $c-or-locale-collate = $use-c-utf8 eq 'y' ?? 'C' !! $locale;
my $c-or-locale-ctype = $use-c-utf8 eq 'y' ?? 'C' !! $locale;
my $c-or-locale-messages = $use-c-utf8 eq 'y' ?? 'C' !! $locale;
my $c-or-locale-numeric = $use-c-utf8 eq 'y' ?? 'C' !! $locale;

my $content = q:to/LOCALE/;
# This configuration explicitly sets the LC_COLLATE, LC_CTYPE, LC_NUMERIC, and LC_MESSAGES
# environment variables to C.UTF-8 if the use_c_utf8 flag is 'y', regardless of the user-defined
# locale setting. This approach ensures uniform behavior across various C and C++ library functions.
# This avoids discrepancies that can arise from differing regional settings.
#
# - Setting LC_COLLATE to C.UTF-8 ensures consistent sorting order across different languages.
#   Affected C functions include strcoll and wcscoll.
#
# - LC_CTYPE set to C.UTF-8 guarantees consistent character classification and conversion, which is
#   crucial for string manipulation and text processing. Affected C functions include isalpha, isdigit,
#   isspace, toupper, and tolower.
#
# - LC_NUMERIC set to C.UTF-8 ensures numerical data is consistently formatted and parsed, for example,
#   no thousands separator as in en_US.UTF-8 and period (.) as the decimal separator.
#   Affected C functions include atof, strtod, printf, and scanf.
#
# - LC_MESSAGES set to C.UTF-8 provides consistent system messages in English, making it easier for
#   developers to search for solutions to errors online.
#
# If use_c_utf8 is not 'y', the user's locale settings will be used, providing a fully localized experience.
LOCALE

$content ~= "LANG={$locale}.UTF-8\n";
$content ~= "LC_ADDRESS={$locale}.UTF-8\n";
$content ~= "LC_COLLATE={$c-or-locale-collate}.UTF-8\n";
$content ~= "LC_CTYPE={$c-or-locale-ctype}.UTF-8\n";
$content ~= "LC_IDENTIFICATION={$locale}.UTF-8\n";
$content ~= "LC_MEASUREMENT={$locale}.UTF-8\n";
$content ~= "LC_MESSAGES={$c-or-locale-messages}.UTF-8\n";
$content ~= "LC_MONETARY={$locale}.UTF-8\n";
$content ~= "LC_NAME={$locale}.UTF-8\n";
$content ~= "LC_NUMERIC={$c-or-locale-numeric}.UTF-8\n";
$content ~= "LC_PAPER={$locale}.UTF-8\n";
$content ~= "LC_TELEPHONE={$locale}.UTF-8\n";
$content ~= "LC_TIME={$locale}.UTF-8\n";

$path.IO.spurt($content);
$path.IO.chmod(0o644);

say "note: wrote locale configuration to $path";

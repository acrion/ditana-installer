# Copyright (c) 2024, 2025 acrion innovations GmbH
# Authors: Stefan Zipproth, s.zipproth@acrion.ch
#
# This file is part of Ditana Installer, see
# https://github.com/acrion/ditana-installer and https://ditana.org/installer.
#
# Ditana Installer is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ditana Installer is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ditana Installer. If not, see <https://www.gnu.org/licenses/>.

use v6.d;
use JSON::Fast;
use MONKEY-SEE-NO-EVAL;
use Tristate;
use Logging;
use InsertionOrderedHash;

subset SettingValue where Int | Rat | Str | Tristate;

class Setting {
    has Str $.name is required;
    has Str $.category;
    has Str $.dialog-name = "";
    has Str $.available is rw;
    has Str $.short-description = "";
    has Str $.long-description = "";
    has Str $.license-category = 'FOSS';
    has Str $.spdx-identifiers = "";
    has Bool $.required-by-chroot = False;
    has Array @.arch-packages = [];
    has Array @.aur-packages = [];
    has SettingValue $.default-value is rw;
    has SettingValue $.current-value is rw;
    has Array @.files = [];
    has Array @.chroot-script = [];
    has Array @.root-script = [];
    has Array @.session-setup = [];
    has Array @.session-setup-script = [];
    has Array @.autostart = [];  # list of [onlyshowin, script-path] pairs
}

class Settings {
    my Settings $instance;
    method new {!!!}
    submethod instance {
        $instance = Settings.bless unless $instance;
        $instance;
    }
    has %!settings is InsertionOrderedHash;
    has %.installation-steps is InsertionOrderedHash;
    has SetHash $!evaluated-expressions;
    has SetHash $!modified-settings;
    
    submethod TWEAK() {
        self.load();
    }
    
    method load() {
        %!settings = InsertionOrderedHash.new;
        %!installation-steps = InsertionOrderedHash.new;
        $!modified-settings = SetHash.new;

        my $converter = $*PROGRAM.parent.child('json-kdl-converter').resolve.absolute;
        my $json = run($converter, 'kdlset2json', '.', :out).out.slurp(:close);
        my $data = from-json($json);

        Logging.log("Loading installation steps...");

        if !$data<installation-steps>.defined {
            die "Missing 'installation-steps' section in settings.json";
        }

        for $data<installation-steps>.list -> $installation-step-data {
            if !$installation-step-data<name>.defined {
                die "Installation step without 'name' field found";
            }
            my $name = $installation-step-data<name>;
            %!installation-steps{$name} = $installation-step-data;
            Logging.log("Loaded installation step $name");
        }

        Logging.log("Dialog order after loading:");
        for %!installation-steps.kv -> $name,$installation-step-data {
            Logging.log($name);
        }
        
        Logging.log("Detecting hardware...");
        
        if !$data<settings>.defined {
            die "Missing 'settings' section in settings.json";
        }
        
        for $data<settings>.list -> $setting-data {
            if $setting-data<detect>.defined {
                if !$setting-data<name>.defined {
                    die "Setting with 'detect' field but without 'name' found";
                }
                my $name=$setting-data<name>;
                Logging.log("$name: $setting-data<detect>");
                my $detection-code=$setting-data<detect>;
                my $detected-value=EVAL($detection-code);
                Logging.log(" ==> $detected-value");
                %!settings{$name} = Setting.new(
                    |$setting-data,
                    default-value => $detected-value,
                    current-value => $detected-value
                );
            };
        }
        Logging.log("Loading settings...");
        
        for $data<settings>.list -> $setting-data {
            if $setting-data<detect>.defined {
                next
            }
            if !$setting-data<name>.defined {
                die "Setting without 'name' field found";
            }
            my $name = $setting-data<name>;
            Logging.log("Loading setting $name");

            CATCH {
                when X::TypeCheck && SettingValue ~~ *.expected && Any ~~ *.got {
                    die "Missing initialization of '$name': $_";
                }
                default {
                    die "Error loading setting '$name': $_";
                    next;
                }
            }

            $!modified-settings.set($name);
            if $setting-data<default-value> !~~ Str or $setting-data<default-value> !~~ /^ '`' .* '`' $/
            {
                %!settings{$name} = Setting.new(
                    |$setting-data,
                    current-value => $setting-data<default-value>
                );
                Logging.log("Loaded setting $name = {$setting-data<default-value>}");
            } else {
                %!settings{$name} = Setting.new(|$setting-data);
                Logging.log("Loaded setting $name, its value will be calculated later.");
            }
        }
        
        self!update-dependent-settings();
    }

    method get-installation-steps(::?CLASS:U:) {
        return self.instance.installation-steps.values;
    }

    method get-installed-native-packages() {
        my Str @packages;

        for %!settings.values -> $setting {
            Logging.log("Checking setting: {$setting.name}");
            if $setting.arch-packages && $setting.current-value && $setting.arch-packages[0] {
                for @($setting.arch-packages[0]) -> $package {
                    if $package && $package.Str {
                        Logging.log("Adding package: $package");
                        @packages.push($package.Str);
                    }
                }
            }
        }

        return @packages;
    }

    method get-installed-aur-packages() {
        my Str @packages;

        for %!settings.values -> $setting {
            Logging.log("Checking setting: {$setting.name}");
            if $setting.aur-packages && $setting.current-value && $setting.aur-packages[0] {
                for @($setting.aur-packages[0]) -> $package {
                    if $package && $package.Str {
                        Logging.log("Adding package: $package");
                        @packages.push($package.Str);
                    }
                }
            }
        }

        return @packages;
    }
    
    method get-required-by-chroot() {
        my Str @result;

        for %!settings.values -> $setting {
            Logging.log("Settings.get-required-by-chroot: {$setting.gist}");
            @result.push($setting.name) if $setting.required-by-chroot;
        }

        return @result;
    }
    
    method get-files-for-enabled-settings() {
        my Str @files;
        for %!settings.values -> $setting {
            next unless $setting.current-value;
            next unless $setting.files && $setting.files[0];
            for @($setting.files[0]) -> $file {
                @files.push($file.Str) if $file;
            }
        }
        return @files;
    }

    method validate-referenced-files() {
        my @missing;
        for %!settings.values -> $setting {
            next unless $setting.files && $setting.files[0];
            for @($setting.files[0]) -> $file {
                next unless $file;
                my $path = "folders{$file.Str}";
                unless $path.IO.e {
                    @missing.push("{$setting.name}: $path");
                }
            }
        }
        if @missing {
            die "The following files referenced in settings.json are missing:\n"
              ~ @missing.join("\n");
        }
    }
    
    method !resolve-script-line(Str $line --> Str) {
        if self!is-code($line) {
            my $code = $line.substr(1, *-1);
            CATCH {
                die "Error evaluating chroot/root-script line: `$code`\n$_";
            }
            return EVAL('qq«' ~ $code ~ '»');
        }
        return $line;
    }

    method get-chroot-script-steps() {
        my Str @steps;
        for %!settings.values -> $setting {
            next unless $setting.current-value;
            next unless $setting.chroot-script && $setting.chroot-script[0];
            @steps.push('echo -e "\033[32m--- Chroot steps for ' ~ $setting.name ~ ' ---\033[0m"');
            for @($setting.chroot-script[0]) -> $line {
                next unless $line;
                @steps.push(self!resolve-script-line($line.Str));
            }
        }
        return @steps;
    }

    method get-root-script-steps() {
        my Str @steps;
        for %!settings.values -> $setting {
            next unless $setting.current-value;
            next unless $setting.root-script && $setting.root-script[0];
            @steps.push('echo "--- Root script steps for ' ~ $setting.name ~ ' ---"');
            for @($setting.root-script[0]) -> $line {
                next unless $line;
                @steps.push(self!resolve-script-line($line.Str));
            }
        }
        return @steps;
    }

    method get-session-setups() {
        my @scripts;
        for %!settings.values -> $setting {
            next unless $setting.current-value;
            next unless $setting.session-setup && $setting.session-setup[0];
            for @($setting.session-setup[0]) -> $entry {
                if $entry ~~ Str {
                    die "Setting '{$setting.name}': 'session-setup' entries must be "
                      ~ "[path, once-flag] tuples, not bare strings. Got: '$entry'";
                }
                @scripts.push($entry) if $entry;
            }
        }
        return @scripts;
    }

    method get-session-setup-scripts() {
        my @results;
        for %!settings.values -> $setting {
            next unless $setting.current-value;
            next unless $setting.session-setup-script && $setting.session-setup-script[0];
            my @data = @($setting.session-setup-script[0]);
            if @data.elems < 2 {
                die "Setting '{$setting.name}': 'session-setup-script' must be "
                  ~ "[[line, ...], once-flag(bool)], got only {@data.elems} element(s)";
            }
            my $once = @data[*-1];
            unless $once ~~ Bool {
                die "Setting '{$setting.name}': last element of 'session-setup-script' "
                  ~ "must be a boolean (once-flag), got: {$once.raku}";
            }
            my @line-groups = @data[0..^(*-1)];
            for @line-groups -> $group {
                @results.push([@($group), $once]);
            }
        }
        return @results;
    }

    method get-autostart-entries() {
        my @entries;
        for %!settings.values -> $setting {
            next unless $setting.current-value;
            next unless $setting.autostart && $setting.autostart[0];
            for @($setting.autostart[0]) -> $entry {
                @entries.push($entry);
            }
        }
        return @entries;
    }

    method get($name) {
        die "Unknown setting: $name" unless %!settings{$name}:exists;
        return %!settings{$name}.current-value;
    }

    method different-value($setting-name, $new-value) {
        my $current-value = self.get($setting-name);
        $current-value.defined ^^ $new-value.defined || ($new-value.defined && $new-value ne $current-value)
    }
    
    method set($name, $value) {
        if self.different-value($name, $value) {
            $!modified-settings = SetHash.new;
            self!set-setting($name, $value);
        }
    }

    method reset($name, $value) {
        $!modified-settings = SetHash.new;
        self!set-setting($name, $value);
    }

    method !is-code($str) {
        return $str ~~ /^ '`' .* '`' $/;
    }
    
    method set-to-default($var) {
        my $default-value = %!settings{$var}.default-value;
        
        while self!is-code($default-value) {
            $default-value = self!evaluate-logical-dependency($var, $default-value);
        }

        self.set($var, $default-value)
    }
    
    method !set-setting($name, $value) {
        die "Unknown setting: $name" unless %!settings{$name}:exists;
        
        Logging.log("Setting $name to $value");
        %!settings{$name}.current-value = $value;
        $!modified-settings.set($name);
        
        self!update-dependent-settings($name);
    }
    
    method !update-dependent-settings($name=Nil) {
        if $name {
            Logging.log("Updating settings that depend on $name...");
        } else {
            Logging.log("Updating all dependent settings...");
        }
        for %!settings.kv -> $dependent-name, $setting {
            next if $!modified-settings{$dependent-name} && %!settings{$dependent-name}.current-value.defined; # Skip settings that have already been assigned a value in the context of recursive calls
            my $expr = $setting.default-value;
            next if $expr !~~ Str;
            next unless self!is-code($expr); # Skip settings that do not depend on code
            next if $name && $expr !~~ /$name/;  # Skip if this setting isn’t part of the expression
            my $new-value = self!evaluate-logical-dependency($dependent-name, $expr);
            if $new-value.defined {
                Logging.log("Setting $dependent-name to $new-value");
                self!set-setting($dependent-name, $new-value);
            } else {
                Logging.log("Value for dependent setting $dependent-name could not be determined due to undefined dependent settings.")
            }
        }
        Logging.log("Finished update of dependencies.")
    }

    method is-available($name) {
        my $available = %!settings{$name}.available;

        return True unless $available; # if there is no `available` entry, default is true

        Logging.log("is-available($name): $available");

        unless self!is-code($available) {
            my $error-message = "$name has an invalid `available` condition, because it is no code (not enclosed in backticks): $available";
            Logging.log($error-message);
            die $error-message
        }

        self!evaluate-logical-dependency($name, $available);
    }
    
    method installation-step-is-available($name) is export {
        my $available = %!installation-steps{$name}<available>;

        return True unless $available; # if there is no `available` entry, default is true

        Logging.log("is-available($name): $available");

        unless self!is-code($available) {
            my $error-message = "$name has an invalid `available` condition, because it is no code (not enclosed in backticks): $available";
            Logging.log($error-message);
            die $error-message
        }

        my $result = self!evaluate-logical-dependency($name, $available);
        Logging.log("Re-evaluated availability of installation step $name ==> $result");
        return $result;
    }

    method get-installation-step(@path, $name) {
        my $current = %!installation-steps;
        
        for @path -> $path-segment {
            if $current{$path-segment} && $current{$path-segment}<type> eq 'categories' {
                $current = $current{$path-segment}<categories>;
                next;
            }
            
            my $found = False;
            for $current.list -> $item {
                if $item<name> eq $path-segment {
                    if $item<type> eq 'categories' {
                        $current = $item<categories>;
                        $found = True;
                        last;
                    }
                }
            }
            die "get-installation-step: Did not find '$path-segment' in list" unless $found;
        }
        
        for $current.list -> $item {
            return $item if $item<name> eq $name;
        }
        
        die "get-installation-step: did not find '$name' in '{@path.gist}'";
    }

    method modify-installation-step(@path, $name, $attribute, $value) is export {
        my $installation-step = self.get-installation-step(@path, $name);
        die "Attribute '$attribute' in installation step '$name' of '{@path.gist}' is undefined." unless $installation-step{$attribute}.defined;
        $installation-step{$attribute} = $value;
    }
    
    method modify-setting($name, $attribute, $value) is export {
        die "Setting '$name' not found" unless %!settings{$name}:exists;
        die "Attribute '$attribute' in setting '$name' is undefined." 
            unless %!settings{$name}."$attribute"().defined;
        %!settings{$name}."$attribute"() = $value;
    }

    method !evaluate-logical-dependency($name-of-setting, $code-including-backticks) {
        $!evaluated-expressions = SetHash.new;
        return self!evaluate-logical-dependency-internal($name-of-setting, $code-including-backticks);
    }

    method !evaluate-logical-dependency-internal($name-of-setting, $code-including-backticks) {
        my $indent = ' ' x ($!evaluated-expressions.elems * 2);
        
        if $!evaluated-expressions{$code-including-backticks} {
            Logging.log("$indent  Circular dependency detected for: $code-including-backticks");
            return Any;
        }
        $!evaluated-expressions.set($code-including-backticks);

        my $code = $code-including-backticks.substr(1, *-1); # remove backticks
        
        # Check for common configuration errors
        if $code eq 'true' || $code eq 'false' {
            die "Error in '$name-of-setting': Boolean literals 'true' or 'false' must not be enclosed in backticks. " ~
                "Use plain boolean values in JSON: true or false (without quotes or backticks).";
        }
        
        if $code ~~ /^\d+$/ {
            die "Error in '$name-of-setting': Numeric literals must not be enclosed in backticks. " ~
                "Use plain numeric values in JSON: $code (without quotes or backticks).";
        }
        
        my @variables = $code.match(/<[a..z A..Z _]><[a..z A..Z 0..9 \-_]>*/, :g)
                            .grep(* !~~ any('OR', 'AND', 'NOT', 'True', 'False'))
                            .map(*.Str);
        
        Logging.log("$indent  $name-of-setting = $code (found variables: {@variables})");
        
        my $evaluated = $code;
        for @variables -> $var {
            my $val = %!settings{$var};
            if !$val {
                die "Error in '$name-of-setting': Referenced variable '$var' does not exist. " ~
                    "Check for typos in: $code";
            } elsif $val.defined {
                my $value;
                if $val.current-value.defined {
                    $value = $val.current-value;
                    if $value ~~ Str {
                        $value = $value.so;
                        Logging.log("$indent  Detected type string of value of $var");
                    }
                    Logging.log("$indent  current value of $var is defined: {$val.current-value} ($value)");
                } elsif $val.default-value ~~ Str && self!is-code($val.default-value) {
                    Logging.log("$indent  current value of $var is undefined, doing recursive call");
                    $value = self!evaluate-logical-dependency-internal($var, $val.default-value);
                    if $value.defined {
                        Logging.log("$indent  Recursive evaluation of $var returned: $value");
                        $!modified-settings.set($var);
                        %!settings{$var}.current-value = $value
                    } else {
                        Logging.log("$indent  Recursive evaluation of $var returned undefined");
                    }
                }

                if $value.defined {
                    my $modified-value = $value ~~ Bool ?? "Tristate.new(" ~ $value ~ ")" !! $value;
                    $evaluated ~~ s:g/<<$var>>/$modified-value/;
                } else {
                    $evaluated ~~ s:g/<<$var>>/Tristate.new(Any)/;
                }
            } else {
                Logging.log("$indent  Dependent variable $var is undefined.");
                return Any
            }
        }
        
        CATCH {
            die "$_: Code: '$code', evaluated to '$evaluated'";
        }

        my $result = EVAL($evaluated).Bool;
        $evaluated = $evaluated.subst("Tristate.new(Any)", "Unknown", :g);
        $evaluated = $evaluated.subst("Tristate.new(True)", "True", :g);
        $evaluated = $evaluated.subst("Tristate.new(False)", "False", :g);
        Logging.log("$indent  $name-of-setting = $evaluated = $result");
        return $result
    }    

    method get-dialog($dialog-name) {
        %!settings.pairs.map(*.value).grep({ 
            .dialog-name eq $dialog-name && self.is-available(.name)
        }).List;
    }

    method get-unavailable-dialog-settings($dialog-name) {
        %!settings.pairs.map(*.value).grep({ 
            .dialog-name eq $dialog-name && !self.is-available(.name)
        }).List;
    }

    method clone() {
        my %cloned = InsertionOrderedHash.new;
        for %!settings.kv -> $name, $setting {
            %cloned{$name} = Setting.new(
                name => $setting.name,
                category => $setting.category,
                dialog-name => $setting.dialog-name,
                available => $setting.available,
                short-description => $setting.short-description,
                long-description => $setting.long-description,
                license-category => $setting.license-category,
                spdx-identifiers => $setting.spdx-identifiers,
                required-by-chroot => $setting.required-by-chroot,
                arch-packages => $setting.arch-packages.deepmap(*.clone),
                aur-packages => $setting.aur-packages.deepmap(*.clone),
                default-value => $setting.default-value,
                current-value => $setting.current-value
            );
        }
        return %( settings => %cloned, order => %!settings.get-order() );
    }

    method restore(%backup) {
        if !%backup<settings>.defined || !%backup<order>.defined {
            die "Invalid backup structure: missing 'settings' or 'order' key";
        }
        
        %!settings = InsertionOrderedHash.new;
        for @(%backup<order>) -> $key {
            if !%backup<settings>{$key}.defined {
                die "Backup corrupted: setting '$key' in order list but not in settings";
            }
            %!settings{$key} = %backup<settings>{$key};
        }
    }

    method compare(%other) {
        my $normal-differences = '';
        my $internal-differences = '';

        for %!settings.kv -> $name, $setting {
            next unless %other{$name}:exists;
            
            my $other-value = %other{$name}.current-value;
            my $current-value = $setting.current-value;

            my $is-internal = !$setting.short-description;
            my $dialog-description = $setting.dialog-name ?? "{$setting.dialog-name} " !! "";
            
            my $difference-line = '';
            if !$other-value.defined {
                $difference-line = "{$dialog-description}«{$setting.name}»: undefined --> $current-value\n" if $current-value.defined;
            }
            elsif !$current-value.defined {
                $difference-line = "{$dialog-description}«{$setting.name}»: $other-value --> undefined\n";
            }
            elsif $other-value ne $current-value {
                my $description = $is-internal ?? $setting.name !! $setting.short-description;
                $difference-line = "{$dialog-description}«{$description}»: $other-value --> $current-value\n";
            }
            
            if $difference-line {
                if $is-internal {
                    $internal-differences ~= $difference-line;
                } else {
                    $normal-differences ~= $difference-line;
                }
            }
        }
        
        my $output = '';
        $output ~= "\nThe following related settings will be updated and can be reviewed or adjusted in the corresponding dialogs:\n\n" ~ $normal-differences if $normal-differences;
        $output ~= "\n" if $output && $internal-differences;
        $output ~= "Required System Adjustments:\n\n" ~ $internal-differences if $internal-differences;
        
        return $output;
    }

    method substitute-setting-refs(Str $line --> Str) is export {
        my $result = $line;
        my @matches = $result.match(/\$\{(<[a..zA..Z0..9\-]>+)\}/, :g);
        for @matches -> $match {
            my $name = $match[0].Str;
            my $value = self.get($name);
            $result = $result.subst('${' ~ $name ~ '}', $value.defined ?? $value.Str !! '', :g);
        }
        return $result;
    }
}

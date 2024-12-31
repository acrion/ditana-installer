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
        my $json = slurp 'settings.json';
        my $data = from-json($json, :allow-jsonc);

        Logging.log("Loading installation steps...");
        
        for $data<installation-steps>.list -> $installation-step-data {
            my $name = $installation-step-data<name>;
            %!installation-steps{$name} = $installation-step-data;
            Logging.log("Loaded installation step $name");
        }

        Logging.log("Dialog order after loading:");
        for %!installation-steps.kv -> $name,$installation-step-data {
            Logging.log($name);
        }
        
        Logging.log("Detecting hardware...");
        
        for $data<settings>.list -> $setting-data {
            if $setting-data<detect>.defined {
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
            return Any;
        }
        $!evaluated-expressions.set($code-including-backticks);

        my $code = $code-including-backticks.substr(1, *-1); # remove backticks
        my @variables = $code.match(/<[a..z A..Z _]><[a..z A..Z 0..9 \-_]>*/, :g)
                            .grep(* !~~ any('OR', 'AND', 'NOT'))
                            .map(*.Str);
        
        Logging.log("$indent  $name-of-setting = $code (found variables: {@variables})");
        
        my $evaluated = $code;
        for @variables -> $var {
            my $val = %!settings{$var};
            if !$val {
                Logging.log("$indent  Dependent variable $var does not exist.");
                return Any;
            } elsif $val.defined {
                my $value;
                if $val.current-value.defined {
                    $value = $val.current-value;
                    if $value ~~ Str {
                        $value = $value.so;
                        Logging.log("Detected type string of value of $var");
                    }
                    Logging.log("current value of $var is defined: {$val.current-value} ($value)");
                } elsif $val.default-value ~~ Str && self!is-code($val.default-value) {
                    Logging.log("current value of $var is undefined, doing recursive call");
                    $value = self!evaluate-logical-dependency-internal($var, $val.default-value);
                    if $value.defined {
                        $!modified-settings.set($var);
                        %!settings{$var}.current-value = $value
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
        %!settings = InsertionOrderedHash.new;
        for @(%backup<order>) -> $key {
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
}

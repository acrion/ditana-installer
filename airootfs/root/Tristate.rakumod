# Copyright (c) 2024, 2025, 2026 acrion innovations GmbH
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
subset TriValue where Any:U | True | False;

class Tristate {
    has TriValue $.value;
    
    method new(TriValue $val) {
        self.bless(value => $val);
    }
    
    multi method or(Tristate $other) {
        if $.value.defined && $other.defined {
            return Tristate.new($.value || $other.value);
        } else {
            return Tristate.new(True) if $.value.defined && $.value;
            return Tristate.new(True) if $other.value.defined && $other.value;
            return Tristate.new(Any);
        }
    }

    multi method or(Bool $other) {
    return self.or(Tristate.new($other));
}
    
    multi method and(Tristate $other) {
        if $.value.defined && $other.defined {
            return Tristate.new($.value && $other.value);
        } else {
            return Tristate.new(False) if $.value.defined && !$.value;
            return Tristate.new(False) if $other.value.defined && !$other.value;
            return Tristate.new(Any);
        }
    }

    multi method and(Bool:D $other) {
        return self.and(Tristate.new($other));
    }
    
    multi method not() {
        return Tristate.new(Any) unless $.value.defined;
        return Tristate.new(!$.value);
    }

    method Bool() {
        die "Tristate: Tried to cast an unknown value to Bool" unless $.value.defined;
        return $.value;
    }

    method Str() {
        my $type = $.value.WHAT;
        
        return '(Any)' if $type === Any;
        return 'True' if $type === Bool && $.value === True;
        return 'False' if $type === Bool && $.value === False;
        
        die "Unexpected value type: $type";
    }

    method gist() {
        return $.value.gist()
    }

    multi sub infix:<AND> (Tristate $a, Tristate $b) is equiv(&infix:<&&>) is export { $a.and($b) }
    multi sub infix:<AND>(Tristate $a, Bool $b) is equiv(&infix:<&&>) is export { $a.and($b) }
    multi sub infix:<AND>(Bool $a, Tristate $b) is equiv(&infix:<&&>) is export { $b.and($a) }
    multi sub infix:<AND>(Bool $a, Bool $b) is equiv(&infix:<&&>) is export { $b.and($a) }

    multi sub infix:<OR>(Tristate $a, Tristate $b) is equiv(&infix:<||>) is export { $a.or($b) }
    multi sub infix:<OR>(Tristate $a, Bool $b) is equiv(&infix:<||>) is export { $a.or($b) }
    multi sub infix:<OR>(Bool $a, Tristate $b) is equiv(&infix:<||>) is export { $b.or($a) }
    multi sub infix:<OR>(Bool $a, Bool $b) is equiv(&infix:<||>) is export { $b.or($a) }

    multi sub prefix:<NOT>(Tristate $a) is equiv(&prefix:<!>) is export { $a.not }
    multi sub prefix:<NOT>(Bool $a) is equiv(&prefix:<!>) is export { $a.not }

    CHECK
        my $t = Tristate.new(True);
        my $f = Tristate.new(False);
        my $u = Tristate.new(Any);
        
        my @tests = (
            [$f AND $u, 'False', 'False and Any'],
            [$u AND $f, 'False', 'Any and False'],
            [$t AND $u, '(Any)', 'True and Any'],
            [$u AND $t, '(Any)', 'Any and True'],
            [$t OR $u,  'True',  'True or Any'],
            [$u OR $t,  'True',  'Any or True'],
            [$f OR $u,  '(Any)', 'False or Any'],
            [$u OR $f,  '(Any)', 'Any or False'],
            [NOT $u,    '(Any)', 'not Any'],
            [NOT ($u OR $u OR $t or $u), 'False', 'not (Any or Any or True or Any)']
        );

        for @tests -> [$result, $expected, $description] {
            unless $result.Str eq $expected {
                die "Test '$description' failed:\n  Expected: $expected\n  Got: $result.Str()";
            }
        }
}

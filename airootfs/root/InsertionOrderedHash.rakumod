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

class InsertionOrderedHash is Hash {
    has @!order;
    
    method STORE(\SELF: \pairs --> Hash:D) {
        @!order = [];
        
        my @pairs = pairs.List;
        for @pairs -> $pair {
            next unless $pair ~~ Pair;
            my $key = $pair.key;
            my $value = $pair.value;
            @!order.push($key);
            self.AT-KEY($key) = $value;
        }
        
        self
    }
    
    method ASSIGN-KEY($key, $value) {
        unless @!order.grep($key) {
            @!order.push($key);
        }
        self.AT-KEY($key) = $value;
    }
    
    method AT-KEY($key) is rw {
        callsame
    }
    
    method keys() {
        @!order.List
    }
    
    method pairs() {
        @!order.map({ $_ => self.AT-KEY($_) }).List
    }
    
    method kv() {
        gather for @!order -> $key {
            take $key;
            take self.AT-KEY($key);
        }
    }

    method values() {
        @!order.map({ self.AT-KEY($_) }).List
    }

    method get-order() {
        @!order.clone
    }

    method set-order(@new-order) {
        @!order = @new-order.clone
    }
}

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
use Logging;

sub filter-lines($input, $pattern-list) {
    my @results;
    
    for $input.lines -> $line {
        for @($pattern-list) -> $pattern {
            if $line ~~ $pattern -> $match {
                @results.push($match.Str);
            }
        }
    }
    
    return @results.unique.join("\n");
}

# --- Open-source GPU list (from open-gpu-kernel-modules README.md) ---

sub download-and-filter-nvidia-open-page($print-messages=False) is export {
    my $url = 'https://raw.githubusercontent.com/NVIDIA/open-gpu-kernel-modules/refs/heads/main/README.md';
    my $nvidia_open_gpu_page = "/tmp/nvidia_open_gpu_page.txt"; # this path is referenced hard coded in build.sh

    my $success = False;

    my $curl-result = run('curl', '-s', '--fail', '--retry', '3',
                         '--retry-connrefused', '--location',
                         $url, '-o', '/tmp/nvidia_open_gpu_page_raw.md', :out, :err);

    if $curl-result.exitcode == 0 {
        # Extract unique 4-digit hex PCI device IDs from the README table.
        # Table format: "| Product Name | 1E02 |" or "| Product Name | 1E30 1028 129E |"
        # We extract the primary PCI device ID (first 4 hex chars in the PCI ID column).
        my @pci-ids;
        for '/tmp/nvidia_open_gpu_page_raw.md'.IO.lines -> $line {
            my @cols = $line.split('|');
            if @cols.elems >= 3 {
                my $pci-col = @cols[2].trim;
                if $pci-col ~~ /^ (<[0..9 A..F a..f]> ** 4) [\s|$]/ {
                    @pci-ids.push($0.Str.uc);
                }
            }
        }

        $nvidia_open_gpu_page.IO.spurt(@pci-ids.unique.sort.join("\n"));

        if test-nvidia-open-page($nvidia_open_gpu_page) {
            $success = True;
            my $msg = "download-and-filter-nvidia-open-page: Downloaded, filtered and validated open GPU list from $url.";
            $print-messages ?? note $msg !! Logging.log($msg);
        }
        else {
            my $msg = "download-and-filter-nvidia-open-page: Warning: Open GPU list from $url has unexpected content.";
            $print-messages ?? note $msg !! Logging.log($msg);
        }
    }
    else {
        my $msg = "download-and-filter-nvidia-open-page: Warning: Download of $url failed.";
        $print-messages ?? note $msg !! Logging.log($msg);
    }

    return $success ?? $nvidia_open_gpu_page !! "";
}

sub parse-nvidia-open-page($path-to-txt, $pci-id) is export {
    my $target = $pci-id.uc;
    for $path-to-txt.IO.lines -> $line {
        return True if $line.trim.uc eq $target;
    }
    return False;
}

sub test-nvidia-open-page-for-id($path-to-txt, $test-pci-id, Bool $expected-found, $print-messages) {
    my $found = parse-nvidia-open-page($path-to-txt, $test-pci-id);
    if $found != $expected-found {
        my $errmsg = "test-nvidia-open-page: PCI ID $test-pci-id expected "
                     ~ ($expected-found ?? "found" !! "not found")
                     ~ " but was "
                     ~ ($found ?? "found" !! "not found")
                     ~ ".";
        $print-messages ?? note $errmsg !! Logging.log($errmsg);
        return False;
    }
    return True;
}

sub test-nvidia-open-page($path-to-txt, $print-messages = False) is export {
    return test-nvidia-open-page-for-id($path-to-txt, "1E02", True, $print-messages)   # TITAN RTX (Turing) - must be in open list
        && test-nvidia-open-page-for-id($path-to-txt, "2684", True, $print-messages)   # RTX 4090 (Ada) - must be in open list
        && test-nvidia-open-page-for-id($path-to-txt, "1C03", False, $print-messages)  # GTX 1060 6GB (Pascal) - must NOT be in open list
        && test-nvidia-open-page-for-id($path-to-txt, "11B6", False, $print-messages)  # Quadro K3100M (Kepler) - must NOT be in open list
        && test-nvidia-open-page-for-id($path-to-txt, "0425", False, $print-messages); # very old GPU - must NOT be in open list
}

sub download-and-test-nvidia-open-page() is export {
    my $path = download-and-filter-nvidia-open-page(True);
    unless $path {
        exit(1);
    }
    exit(test-nvidia-open-page($path, True) ?? 0 !! 1);
}

# --- Legacy GPU page (from nvidia.com) ---

sub download-and-filter-nvidia-legacy-page($print-messages=False) is export {
    my $url = 'https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/';
    my $nvidia_legacy_gpu_page = "/tmp/nvidia_legacy_gpu_page.html"; # this path is referenced hard coded in build.sh

    my $success = False;
    my $html-content;

    my $curl-result = run('curl', '-s', '--fail', '--retry', '3', 
                         '--retry-connrefused', '--location', 
                         $url, '-o', $nvidia_legacy_gpu_page, :out, :err);
    
    if $curl-result.exitcode == 0 {
        # Filter the page so that only the lines relevant to parse-nvidia-page() are left.
        $nvidia_legacy_gpu_page.IO.spurt(filter-lines($nvidia_legacy_gpu_page.IO.slurp,
            ( # examples: `<td class="text" width="32%" valign="top">11B6 </td> `
              #           `<td class="text" width="32%" valign="top">0x0425</td> `
                rx/ <[ x> ]>                 # x or closing angle bracket
                   \s*                       # blanks (or nothing)
                   <[ 0..9 A..F a..f ]> ** 4 # hex number with 4 digits
                   \s* \< /,                 # blanks (or nothing) and opening angle bracket
              # examples: `<p align="left"> <b>The 470.xx driver supports the following set of GPUs.</b> </p> `
              #           `<p> <b>The 390.xx driver supports the following set of GPUs.</b> </p> `
            rx/ \s+       # at least one blank
                \d\d+     # decimal number with a least two digits
                \.xx/))); # decimal point followed by two x

        if test-nvidia-page($nvidia_legacy_gpu_page) {
            $success = True;
            my $msg = "get-nvidia-driver-version: Downloaded, filtered and validated current version of $url.";
            $print-messages ?? note $msg !! Logging.log($msg);
        }
        else {
            my $msg = "get-nvidia-driver-version: Warning: Current version of $url has unexpected content.";
            $print-messages ?? note $msg !! Logging.log($msg);
        }
    }
    else {
        my $msg = "get-nvidia-driver-version: Warning: Download of current version of $url failed.";
        $print-messages ?? note $msg !! Logging.log($msg);
    }

    return $success ?? $nvidia_legacy_gpu_page !! "";
}

sub parse-nvidia-page($path-to-html, $pci-id) is export {
    my $html-content = $path-to-html.IO.slurp;

    # examples: `<td class="text" width="32%" valign="top">11B6 </td> `
    #           `<td class="text" width="32%" valign="top">0x0425</td> `
    my $match = $html-content.match(rx:i/ <[ x> ]>   # x or closing angle bracket
                                          \s*        # blanks (or nothing)
                                          $pci-id
                                          \s* \< /); # blanks (or nothing) and opening angle bracket
    
    if $match {
        my $content-until-match = $html-content.substr(0, $match.from);

        # examples: `<p align="left"> <b>The 470.xx driver supports the following set of GPUs.</b> </p> `
        #           `<p> <b>The 390.xx driver supports the following set of GPUs.</b> </p> `
        my $legacy-driver-version = $content-until-match.match(rx/ \s+     # at least one blank
                                                                   (\d\d+) # decimal number with a least two digits
                                                                   \.xx/,  # decimal point followed by two x
                                                               :g).tail.tail;
        
        Logging.log("parse-nvidia-page: Identified driver version '$legacy-driver-version' for PCI ID '$pci-id'.");
        return $legacy-driver-version;
    } else {
        Logging.log("parse-nvidia-page: PCI ID '$pci-id' does not require a legacy driver.");
        return 'latest'; # this is evaluated in check-nvidia()
    }
}

sub test-nvidia-page-for-driver($path-to-html, $test-pci-id, $correct-driver, $print-messages) {
    my $driver-version = parse-nvidia-page($path-to-html, $test-pci-id);
    if $driver-version ne $correct-driver {
        my $errmsg = "test-nvidia-page-for-driver: unexpected HTML content. Driver version for pci-id $test-pci-id should be $correct-driver, but is $driver-version.";
        if $print-messages {
            note $errmsg;
        } else {
            Logging.log($errmsg);
        }
        return False;
    }

    return True;
}

sub test-nvidia-page($path-to-html, $print-messages = False) is export {
    # Note: As of 2025-12, the NVIDIA legacy page does NOT yet list 580.xx as a legacy tier.
    # Maxwell/Pascal/Volta GPUs still return "latest" from this page. Once NVIDIA updates the
    # page to include 580.xx, add a test like:
    #   && test-nvidia-page-for-driver($path-to-html, "1c03", "580", $print-messages)
    # For now, this case is handled in check-nvidia() by cross-referencing with the open GPU list.
    return test-nvidia-page-for-driver($path-to-html, "21c4", "latest", $print-messages)
        && test-nvidia-page-for-driver($path-to-html, "1f07", "latest", $print-messages)
        && test-nvidia-page-for-driver($path-to-html, "11b6", "470", $print-messages)
        && test-nvidia-page-for-driver($path-to-html, "0425", "340", $print-messages);
}

sub download-and-test-nvidia-page() is export {
    my $path-to-nvidia-legacy-page = download-and-filter-nvidia-legacy-page(True);
    unless $path-to-nvidia-legacy-page {
        exit(1);
    }

    exit(test-nvidia-page($path-to-nvidia-legacy-page, True) ?? 0 !! 1);
}
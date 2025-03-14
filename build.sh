#!/usr/bin/env bash

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

set -e
set -u

sudo -k

if ! pacman -Qi python-gnupg &>/dev/null; then
    echo "The 'python-gnupg' package is not installed. Installing it now..."
    sudo pacman -S python-gnupg
fi

function list_gpg_keys() {
    # Terminate any running keyboxd process to prevent conflicts with the following user-level GPG operations.
    # The keyboxd daemon is part of the GnuPG package and is started automatically by GPG whenever the keybox database is accessed.
    # If a root-owned keyboxd process is running, it holds locks or permissions that interfere with user-level operations
    # in mkarchiso, leading to conflicts.
    sudo pkill keyboxd || true

    python3 -c "
import gnupg

gpg = gnupg.GPG()
keys = gpg.list_keys()
for key in keys:
    key_id = key['keyid']
    full_uid = key['uids'][0]
    print(f'{key_id},{full_uid}')
"
}

list_special_packages() {
    local firmware_pkgs=()
    local module_pkgs=()
    
    sudo pkgfile --update &>/dev/null
    
    while read -r package; do
        if pkg_files=$(pkgfile -l "$package" 2>/dev/null); then
            if echo "$pkg_files" | grep -q "/usr/lib/firmware"; then
                firmware_pkgs+=("$package")
            fi
            if echo "$pkg_files" | grep -q "/usr/lib/modules"; then
                module_pkgs+=("$package")
            fi
        fi
    done < "packages.x86_64"
    
    echo -n "These packages of packages.x86_64 install into /usr/lib/firmware:"
    printf " %s" "${firmware_pkgs[@]}"
    echo
    
    echo -n "These packages of packages.x86_64 install into /usr/lib/modules:"
    printf " %s" "${module_pkgs[@]}"
    echo
}

raku -e "use v6.d; use lib 'airootfs/root'; use NvidiaParser; download-and-test-nvidia-page"

mv /tmp/nvidia_legacy_gpu_page.html airootfs/root/cached_legacy_gpu_page.html

# Export the GPG key to be used as a fallback during installation in case keyserver.ubuntu.com is down
sudo pacman-key --export 3056513887B78AEB | tee airootfs/root/bind-mount/root/chaotic-aur-key.asc >/dev/null

sudo pacman -Sy
TMP_ISO=/tmp/ditana-iso
if [[ -n "$TMP_ISO" ]]; then
    sudo rm -rf "$TMP_ISO"
fi
sudo rm -rf out

list_special_packages

current_branch=$(git rev-parse --abbrev-ref HEAD)

cleanup() {
    trap - EXIT ERR

    if [[ "$current_branch" != "main" ]]; then
        git status
        echo "Reversing patch..."
        git apply --reverse use-testing-repo.patch
        echo "Finished reversing patch."
        git status
    fi

    if [[ -n "$TMP_ISO" ]]; then
        sudo rm -rf "$TMP_ISO"
    fi

    # After mkarchiso completes or is interrupted, terminate any remaining keyboxd process that was started under the root context.
    # This ensures that subsequent GPG commands executed by the user do not encounter issues with keyboxd running as root,
    # which could otherwise lead to permission conflicts or locked databases.
    sudo pkill keyboxd || true
}

trap cleanup EXIT ERR

LABEL="Ditana"

if [[ "$current_branch" != "main" ]]; then
    echo "Applying patch to use testing repo..."
    git apply use-testing-repo.patch
    git status
    LABEL+="-Testing"
fi

mapfile -t key_list < <(list_gpg_keys)

echo "Available GPG keys for signing (ID - Name <Email>):"
for i in "${!key_list[@]}"; do
    IFS=',' read -r key_id full_uid <<< "${key_list[i]}"
    echo "$((i+1))) $key_id - $full_uid"
done
echo "$(( ${#key_list[@]} + 1 ))) No signing"

read -rp "Choose a key by number for signing or select 'No signing': " choice
if [[ "$choice" -gt 0 && "$choice" -le "${#key_list[@]}" ]]; then
    IFS=',' read -r selected_key selected_signer <<< "${key_list[$((choice - 1))]}"
    echo "Selected GPG Key ID: $selected_key"
else
    echo "No signing selected."
    selected_signer="(none)"
    selected_key=""
fi

# Terminate any running keyboxd process to prevent conflicts with root-level GPG operations in mkarchiso.
# The keyboxd daemon is part of the GnuPG package and is started automatically by GPG whenever the keybox database is accessed.
# Currently, a user-owned keyboxd process is running, because we accessed it above. It holds locks or permissions that interfere
# with root-level operations in mkarchiso, leading to conflicts.
sudo pkill keyboxd

mkdir -p airootfs/root/.raku
zef --force-install -to="inst#/$(realpath airootfs/root/.raku)" install JSON::Fast Tomty

# Delete temporary files from test installations
rm -f airootfs/root/bind-mount/root/installation-steps.sh
rm -f airootfs/root/bind-mount/root/settings.sh

source version.sh
export DITANA_BUILD_ID=${DITANA_VERSION}-$(TZ=UTC date +%Y-%m-%d.%H)
echo "export DITANA_VERSION=$DITANA_VERSION"    >airootfs/root/ditana-version.sh
echo "export DITANA_BUILD_ID=$DITANA_BUILD_ID" >>airootfs/root/ditana-version.sh

echo "Creating ISO..."

echo "selected_signer: '$selected_signer'"
echo "selected_key:    '$selected_key'"
echo "LABEL:           '$LABEL'"
echo "TMP_ISO:         '$TMP_ISO'"

# Execute mkarchiso with elevated privileges, while preserving the current user’s environment (-E).
# The GNUPGHOME environment variable points to the user’s GPG home directory, ensuring that GPG operations within mkarchiso
# continue to use the user’s keyring and associated permissions.
if [[ -n "$selected_key" ]]; then
    sudo -E mkarchiso -v -C pacman.conf -L "$LABEL" -w "$TMP_ISO" -P "$selected_signer" -G "$selected_signer" -g "$selected_key" .
else
    sudo -E mkarchiso -v -C pacman.conf -L "$LABEL" -w "$TMP_ISO" .
fi

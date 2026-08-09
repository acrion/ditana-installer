#!/usr/bin/env bash

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
set -e
set -u

sudo -k

ensure_package_installed() {
    if ! pacman -Qi "$1" &>/dev/null; then
        echo "The '$1' package is not installed. Installing it now..."
        sudo pacman -S "$1"
    fi
}

ensure_package_installed python-gnupg
ensure_package_installed gnupg
ensure_package_installed pkgfile
ensure_package_installed zfs-dkms

# Delete temporary files from simulated installations
rm -f  airootfs/root/bind-mount/root/installation-steps.sh
rm -f  airootfs/root/bind-mount/root/settings.sh
rm -f  airootfs/root/installation-steps.kdl
rm -rf airootfs/root/settings/
rm -rf airootfs/root/folders/

current_branch=$(git rev-parse --abbrev-ref HEAD)

source version.sh
export DITANA_BUILD_ID=${DITANA_VERSION}-$(TZ=UTC date +%Y-%m-%d.%H)
echo "export DITANA_VERSION=$DITANA_VERSION"    >airootfs/root/ditana-version.sh
echo "export DITANA_BUILD_ID=$DITANA_BUILD_ID" >>airootfs/root/ditana-version.sh
echo "export DITANA_BRANCH=$current_branch"    >>airootfs/root/ditana-version.sh

# --- Apply testing-repo patch (shared by quick and full build) -----------------
# Both build modes need the patch applied: the full build because mkarchiso
# consumes the patched files, and the quick build because airootfs/root is
# copied into the ISO verbatim. The patch is reverted via the shared helper
# below — an early EXIT trap catches failures that happen before the
# mode-specific cleanup trap takes over.
#
# use-testing-repo.patch covers two independent things: which pacman repository
# the ISO installs from (enable-ditana.sh, packages.x86_64, pacman.conf) and how
# the ISO is named (profiledef.sh). They are separable, because an ISO built
# from a branch is sometimes needed to test the installer itself against the
# packages real users actually get. Only the repository part is optional; the
# "Testing" name and version always stay, since such a build skips various
# checks regardless of where its packages came from.
#
# The choice is offered only when a Testing ISO is being built. Set
# DITANA_USE_OFFICIAL_REPO=y or =n to answer it non-interactively; a build with
# no terminal attached keeps the previous behaviour and uses the testing
# repository, so unattended builds are unaffected.
TESTING_PATCH_ARGS=()

select_testing_repository() {
    local answer

    if [[ -n "${DITANA_USE_OFFICIAL_REPO:-}" ]]; then
        answer="$DITANA_USE_OFFICIAL_REPO"
    elif [[ -t 0 ]]; then
        echo
        echo "Branch '$current_branch' builds a Testing ISO."
        echo "  N) install from the ditana-testing repository (default)"
        echo "  y) install from the official ditana repository"
        read -r -p "Use the official repository? [y/N] " answer
    else
        answer="n"
    fi

    if [[ "${answer,,}" == y* ]]; then
        echo "Using the official Ditana repository; patching the ISO name only."
        TESTING_PATCH_ARGS=(--include=profiledef.sh)
    else
        echo "Using the ditana-testing repository."
    fi
}

reverse_patch_if_needed() {
    if [[ "$current_branch" != "main" ]]; then
        git status
        echo "Reversing patch..."
        git apply --reverse "${TESTING_PATCH_ARGS[@]}" use-testing-repo.patch
        echo "Finished reversing patch."
        git status
    fi
}

if [[ "$current_branch" != "main" ]]; then
    select_testing_repository
    echo "Applying patch..."
    git apply "${TESTING_PATCH_ARGS[@]}" use-testing-repo.patch
    # Register an early cleanup so failures between here and the mode-specific
    # cleanup trap (set further below) still revert the patch.
    trap reverse_patch_if_needed EXIT
    git status
    # The configuration tarball follows the branch, not the package repository:
    # a branch build tests the installer configuration of that branch.
    DITANA_CONFIG_TAG="develop-latest"
else
    DITANA_CONFIG_TAG="latest"
fi

# --- Download latest Ditana configuration and build json-kdl-converter --------
# Done before the quick-build branch so that a quick rebuild also picks up a
# freshly built converter binary in airootfs/root.
DITANA_CONFIG_URL="https://github.com/acrion/ditana-config/releases/download/${DITANA_CONFIG_TAG}/ditana-config.tar.gz"
echo "Downloading Ditana configuration from ${DITANA_CONFIG_TAG}..."
if curl -fSL "$DITANA_CONFIG_URL" -o airootfs/root/ditana-config.tar.gz; then
    echo "Configuration downloaded."
else
    echo "ERROR: Failed to download configuration."
    exit 1
fi

# Extract the converter source from the config archive and compile it for the ISO
echo "Extracting and building json-kdl-converter from configuration archive..."
tar -xzf airootfs/root/ditana-config.tar.gz -C /tmp json-kdl-converter
pushd /tmp/json-kdl-converter
cargo build --release
popd
cp /tmp/json-kdl-converter/target/release/json-kdl-converter airootfs/root/
rm -rf /tmp/json-kdl-converter

if [[ "${1:-}" == "--quick" ]]; then
    # --- Quick rebuild mode: only replace airootfs/root in existing ISO ---
    ensure_package_installed squashfs-tools
    ensure_package_installed libisoburn

    ISO_FILE=$(find out/ -maxdepth 1 -name "*.iso" ! -name "*_backup*" -print -quit 2>/dev/null)
    if [[ -z "$ISO_FILE" ]]; then
        echo "ERROR: No existing ISO found in out/. Run a full build first."
        exit 1
    fi

    echo "Quick rebuild: updating /root in $(basename "$ISO_FILE")..."

    QUICK_TMP=$(mktemp -d)

    cleanup_quick() {
        reverse_patch_if_needed
        sudo rm -rf "$QUICK_TMP"
    }
    trap cleanup_quick EXIT

    # Auto-detect the squashfs path inside the ISO
    SFS_ISO_PATH=$(bsdtar -tf "$ISO_FILE" | grep 'airootfs\.sfs$' | head -1 || true)
    if [[ -z "$SFS_ISO_PATH" ]]; then
        echo "ERROR: Could not find airootfs.sfs inside the ISO."
        exit 1
    fi
    SFS_ISO_PATH="/${SFS_ISO_PATH}"
    echo "Found squashfs at: $SFS_ISO_PATH"

    # Step 1: Extract squashfs from ISO
    echo "[1/4] Extracting squashfs from ISO..."
    xorriso -osirrox on -indev "$ISO_FILE" \
        -extract "$SFS_ISO_PATH" "$QUICK_TMP/airootfs.sfs"

    # Step 2: Unsquash filesystem
    echo "[2/4] Unsquashing filesystem..."
    sudo unsquashfs -d "$QUICK_TMP/squashfs-root" "$QUICK_TMP/airootfs.sfs"

    # Step 3: Replace /root and rebuild squashfs
    echo "[3/4] Replacing /root and rebuilding squashfs..."
    sudo rm -rf "$QUICK_TMP/squashfs-root/root"
    sudo cp -a airootfs/root "$QUICK_TMP/squashfs-root/root"
    sudo rm "$QUICK_TMP/airootfs.sfs"
    # Use low compression for speed — this is a dev build
    sudo mksquashfs "$QUICK_TMP/squashfs-root" "$QUICK_TMP/airootfs.sfs" \
        -comp zstd -Xcompression-level 1 -b 1M
    sudo rm -rf "$QUICK_TMP/squashfs-root"

    # Step 4: Patch the squashfs back into the ISO
    echo "[4/4] Updating ISO..."
    xorriso -indev "$ISO_FILE" \
        -outdev "${ISO_FILE}.tmp" \
        -boot_image any replay \
        -update "$QUICK_TMP/airootfs.sfs" "$SFS_ISO_PATH" \
        -end
    mv "${ISO_FILE}.tmp" "$ISO_FILE"

    # Update checksum if it exists
    SHA_FILE="${ISO_FILE}.sha256"
    if [[ -f "$SHA_FILE" ]]; then
        pushd out
        sha256sum "$(basename "$ISO_FILE")" > "$(basename "$SHA_FILE")"
        popd
    fi

    echo "Quick rebuild complete: $ISO_FILE"
    exit 0
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
keys = gpg.list_keys(True)
for key in keys:
    key_id = key['keyid']
    full_uid = key['uids'][0]
    print(f'{key_id},{full_uid}')
"
}

list_special_packages() {
    echo "Identifying special packages..."
    local firmware_pkgs=()
    local module_pkgs=()

    sudo pacman -Fy >/dev/null
    sudo pkgfile --update >/dev/null

    while read -r package; do
        if pkg_files=$(timeout 3s pkgfile -l "$package" 2>/dev/null); then
            if echo "$pkg_files" | grep -q "/usr/lib/firmware"; then
                firmware_pkgs+=("$package")
            fi
            if echo "$pkg_files" | grep -q "/usr/lib/modules"; then
                module_pkgs+=("$package")
            fi
        elif pkg_files=$(pacman -Fl "$package" 2>/dev/null); then
            # pacman -Fl output doesn't have leading slashes
            if echo "$pkg_files" | grep -q "usr/lib/firmware"; then
                firmware_pkgs+=("$package")
            fi
            if echo "$pkg_files" | grep -q "usr/lib/modules"; then
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

raku -e "use v6.d; use lib 'airootfs/root'; use NvidiaParser; download-and-test-nvidia-open-page"
mv /tmp/nvidia_open_gpu_page.txt airootfs/root/cached_open_gpu_page.txt

gpg --export --armor 3F8054C3FF755E5544E68516BC333E9AE877D45A >airootfs/root/bind-mount/root/ditana-key.asc

sudo pacman -Sy
TMP_ISO=/tmp/ditana-iso
if [[ -n "$TMP_ISO" ]]; then
    sudo rm -rf "$TMP_ISO"
fi
sudo rm -rf out

# --- GPG key selection (moved before list_special_packages) ---

mapfile -t key_list < <(list_gpg_keys)

echo "Available GPG keys for signing (ID - Name <Email>):"
for i in "${!key_list[@]}"; do
    IFS=',' read -r key_id full_uid <<< "${key_list[i]}"
    echo "$((i+1))) $key_id - $full_uid"
done
echo "$(( ${#key_list[@]} + 1 ))) No signing"

ZEF_SWITCHES=""

read -rp "Choose a key by number for signing or press enter for 'No signing': " choice
if [[ "$choice" -gt 0 && "$choice" -le "${#key_list[@]}" ]]; then
    IFS=',' read -r selected_key selected_signer <<< "${key_list[$((choice - 1))]}"
    echo "Selected GPG Key ID: $selected_key"


    zef upgrade Sparrow6
    zef upgrade Tomty
    pushd tests/configuration
    tomty --color --all
    popd
    list_special_packages
else
    echo "No signing selected."
    selected_signer="(none)"
    selected_key=""
    ZEF_SWITCHES="--/test --/test-depends"
fi

cleanup() {
    trap - EXIT ERR

    reverse_patch_if_needed

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
    LABEL+="-Testing"
fi

mkdir -p airootfs/root/.raku
zef --force-install --contained $ZEF_SWITCHES -to="inst#/$(realpath airootfs/root/.raku)" install JSON::Fast Sparrow6

# Terminate any running keyboxd process to prevent conflicts with root-level GPG operations in mkarchiso.
# The keyboxd daemon is part of the GnuPG package and is started automatically by GPG whenever the keybox database is accessed.
# Currently, a root-owned keyboxd process is running, because we accessed it above. It holds locks or permissions that interfere
# with root-level operations in mkarchiso, leading to conflicts.
sudo pkill keyboxd

echo "Creating ISO..."

echo "selected_signer: '$selected_signer'"
echo "selected_key:    '$selected_key'"
echo "LABEL:           '$LABEL'"
echo "TMP_ISO:         '$TMP_ISO'"

# Execute mkarchiso with elevated privileges, while preserving the current user's environment (-E).
# The GNUPGHOME environment variable points to the user's GPG home directory, ensuring that GPG operations within mkarchiso
# continue to use the user's keyring and associated permissions.
if [[ -n "$selected_key" ]]; then
    sudo -E mkarchiso -v -C pacman.conf -L "$LABEL" -w "$TMP_ISO" -P "$selected_signer" -G "$selected_signer" -g "$selected_key" .
    sudo chown -R "$USER:$USER" out/
    pushd out
    ISO_FILE=$(ls ./*.iso)

    # Terminate any running keyboxd process to prevent conflicts with root-level GPG operations in mkarchiso.
    # The keyboxd daemon is part of the GnuPG package and is started automatically by GPG whenever the keybox database is accessed.
    # Currently, a root-owned keyboxd process is running, because we accessed it via mkarchiso. It holds locks or permissions that interfere
    # with below user-level operation, leading to conflicts, e.g. `gpg: Note: database_open xy waiting for lock (held by xy) ...`
   sudo pkill keyboxd

    gpg --default-key "$selected_key" --detach-sign --output "${ISO_FILE}.sig" "$ISO_FILE"
    sha256sum "$ISO_FILE" > "${ISO_FILE}.sha256"

    gpg --verify "${ISO_FILE}.sig" "$ISO_FILE"
    sha256sum -c "${ISO_FILE}.sha256"

    popd
else
    sudo -E mkarchiso -v -C pacman.conf -L "$LABEL" -w "$TMP_ISO" .
    sudo chown -R "$USER:$USER" out/
fi

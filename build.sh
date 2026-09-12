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

# --- BEGIN maintenance-lock --------------------------------------------------
# Lifted by tests/installer/maintenance-lock.t, which cuts between BEGIN and END.
#
# On a Ditana build server the system update and the package builds must not
# overlap, and maintenance-lock is what arranges that. An ISO build belongs in
# the same queue: half an hour of building is exactly the window in which an
# update would reboot the machine underneath it.
#
# Conditional, because the mechanism is not on every machine that builds an ISO.
# It needs /run/ditana-maintenance, which only root creates, so a workstation
# without it simply builds -- and `command -v` alone would not have noticed,
# since the tool is there and fails at the lock file.
#
# `maintenance-lock run` leaves a job that loses the race alone: it says so and
# exits 0, which is right for a timer that will tick again and wrong for a build
# somebody is waiting on. The marker is how this run tells the difference
# between "built" and "was not started", so that nothing reports success for an
# ISO that does not exist.
#| DITANA_MAINTENANCE_LOCK_DIR names the directory; the tests point it at one
#| they can create.
maintenance_lock_usable() {
    command -v maintenance-lock >/dev/null 2>&1 || return 1
    [[ -w "${DITANA_MAINTENANCE_LOCK_DIR:-/run/ditana-maintenance}" ]]
}

if [[ -z "${DITANA_ISO_BUILD_HOLDS_LOCK:-}" ]] && maintenance_lock_usable; then
    export DITANA_ISO_BUILD_HOLDS_LOCK=1
    DITANA_ISO_BUILD_MARKER=$(mktemp)
    export DITANA_ISO_BUILD_MARKER

    # `|| build_status=$?` and not a bare call: under `set -e` a non-zero exit
    # would end this script before the status could be looked at.
    build_status=0
    maintenance-lock run ditana-iso-build --wait 1800 -- "$0" "$@" || build_status=$?

    if [[ ! -s "$DITANA_ISO_BUILD_MARKER" ]]; then
        rm -f "$DITANA_ISO_BUILD_MARKER"
        echo "ERROR: the maintenance lock was held for the whole wait, so this" >&2
        echo "       build never started. Nothing was built." >&2
        exit 1
    fi
    rm -f "$DITANA_ISO_BUILD_MARKER"
    exit $build_status
fi

# The run that holds the lock says so, for the wrapper above to read. An `if`
# and not `[[ ... ]] && ...`, because the second form is a statement that fails
# when the condition is false, and `set -e` ends the build on it -- on every
# machine that has no maintenance lock, which is most of them.
if [[ -n "${DITANA_ISO_BUILD_MARKER:-}" ]]; then
    echo started > "$DITANA_ISO_BUILD_MARKER"
fi
# --- END maintenance-lock ----------------------------------------------------

sudo -k

# --- BEGIN pacman-database-lock ----------------------------------------------
# Lifted by tests/installer/pacman-lock.t, which cuts between BEGIN and END.
#
# One pacman at a time: the database is held by whoever is using it, and a
# second one does not queue, it fails.
#
#     error: failed to synchronize all databases (unable to lock database)
#
# On a machine that keeps an AUR repository, `update-aurto` runs on a timer and
# holds the database for minutes while it builds in a chroot. A build that
# starts beside it dies at its first pacman, which is a quarter of an hour of
# ISO thrown away for a collision that clears itself.
#
# Only the lock is waited out. Any other failure is returned at once, because a
# pacman that failed for its own reasons has already removed its lock file, and
# retrying it would only repeat the error.
#| DITANA_PACMAN_POLL_SECONDS says how often to look; the tests set it to zero.
pacman_waiting() {
    local waited=0 poll=${DITANA_PACMAN_POLL_SECONDS:-10} lock
    # Beside the database, wherever that is: pacman.conf can move it, and a
    # hard-coded path would watch a file nobody writes.
    lock="$(pacman-conf DBPath 2>/dev/null || echo /var/lib/pacman)/db.lck"
    lock=${lock//\/\//\/}
    while true; do
        sudo pacman "$@" && return 0
        [[ -e $lock ]] || return 1
        (( waited )) || echo "The pacman database is held by another process; waiting for it."
        sleep "$poll"
        waited=$((waited + poll))
        if (( waited >= 900 )); then
            echo "ERROR: the pacman database stayed locked for fifteen minutes." >&2
            echo "       Whoever holds /var/lib/pacman/db.lck is not letting go." >&2
            return 1
        fi
    done
}
# --- END pacman-database-lock ------------------------------------------------

ensure_package_installed() {
    if ! pacman -Qi "$1" &>/dev/null; then
        echo "The '$1' package is not installed. Installing it now..."
        pacman_waiting -S "$1"
    fi
}

ensure_package_installed python-gnupg
ensure_package_installed gnupg
ensure_package_installed pkgfile
ensure_package_installed zfs-dkms

# --- BEGIN credentials-up-front ----------------------------------------------
# Lifted by tests/installer/gpg-priming.t, which cuts between BEGIN and END.
#
# Everything the build needs a person for is asked here, before the first long
# step. The passphrase is not kept anywhere: gpg asks for it on the terminal and
# root's gpg-agent holds it from then on, which is where mkarchiso looks for it.
# prime_root_gpg_agent asks the same question again immediately before
# mkarchiso, in case the agent has let it go by then.

list_gpg_keys() {
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

#| Can root sign with this key right now, without anybody being asked anything?
#|
#| `--pinentry-mode error` makes gpg fail rather than start a pinentry, so this
#| answers in a moment and in every case that matters: yes when the key has no
#| passphrase, yes when the agent already holds it, no when somebody would have
#| to type it. Plain `--batch` cannot be used to ask the question -- it starts
#| the pinentry that cannot come up as root, and gpg-agent then waits sixty
#| seconds for it.
#|
#| As root, and not as the user, because root is who signs: this also catches an
#| ownership or keyring problem in the first seconds rather than at the signing
#| step.
root_can_sign_now() {
    local key=$1 probe sig failed=0
    probe=$(mktemp) || return 1
    sig="$probe.sig"
    echo "ditana-build" > "$probe"
    sudo -E gpg --batch --pinentry-mode error --no-armor --output "$sig" \
         --detach-sign --default-key "$key" "$probe" >/dev/null 2>&1 || failed=1
    sudo rm -f "$probe" "$sig"
    return $failed
}

#| Have the sudo password now, if it is going to be needed at all.
#|
#| `sudo -n true` decides that, and not `sudo -v`: on a host where sudo needs
#| no password at all -- the build VM has NOPASSWD for everything -- `sudo -v`
#| insists on one anyway.
#|
#| With neither a free pass nor a terminal this only says so, and the build
#| stops at its first step that needs root. That is better than refusing a host
#| whose sudoers covers each of those steps one by one.
ensure_sudo() {
    if sudo -n true 2>/dev/null; then
        return 0
    fi

    if [[ -t 0 ]]; then
        sudo -v
        return
    fi

    echo "WARNING: sudo needs a password and there is no terminal to ask on;" >&2
    echo "         this build will stop at its first step that needs root." >&2
}

select_signing_key() {
    local key_list choice key_id full_uid i
    mapfile -t key_list < <(list_gpg_keys)

    echo "Available GPG keys for signing (ID - Name <Email>):"
    for i in "${!key_list[@]}"; do
        IFS=',' read -r key_id full_uid <<< "${key_list[i]}"
        echo "$((i+1))) $key_id - $full_uid"
    done
    echo "$(( ${#key_list[@]} + 1 ))) No signing"

    # With no terminal attached, read fails and `set -e` would end the build
    # here. Falling through to "No signing" is the honest answer: a machine with
    # no terminal has nobody to pick a key. DITANA_SIGNING_CHOICE answers the
    # prompt in advance, the same way DITANA_USE_OFFICIAL_REPO answers the
    # repository one.
    choice="${DITANA_SIGNING_CHOICE:-}"
    if [[ -z "$choice" && -t 0 ]]; then
        read -rp "Choose a key by number for signing or press enter for 'No signing': " choice
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 0 && choice <= ${#key_list[@]} )); then
        IFS=',' read -r selected_key selected_signer <<< "${key_list[$((choice - 1))]}"
        echo "Selected GPG Key ID: $selected_key"
    else
        echo "No signing selected."
        selected_signer="(none)"
        selected_key=""
    fi
}

#| Make sure root can sign, asking for the passphrase if it has to.
#|
#| Called twice: once at the top of the build, and once immediately before
#| mkarchiso. The second call costs nothing while the agent still holds the
#| passphrase, and asks again if `default-cache-ttl` in ~/.gnupg/gpg-agent.conf
#| is shorter than this build.
#|
#| gpg does the asking itself, on the terminal: `--pinentry-mode loopback`
#| starts no pinentry, and what is typed lands in the cache of the very agent
#| mkarchiso will use. Nothing keeps the passphrase anywhere else.
ensure_signing_possible() {
    local key=$1 probe sig

    # Before any gpg that runs as root, and this is not optional. keyboxd holds
    # an exclusive lock on ~/.gnupg/public-keys.d/pubring.db, root cannot share
    # the one belonging to the user -- the socket paths differ, so it starts its
    # own -- and the one that loses waits twenty seconds and then reports
    #
    #     gpg: Note: database_open ... waiting for lock (held by <pid>)
    #     gpg: key "..." not found: Connection timed out
    #     gpg: signing failed: Connection timed out
    #
    # which says nothing about keys or passphrases and is not what it looks
    # like. Reading the list of secret keys just above here is what starts the
    # user's keyboxd, so the lock is always held by the time this runs.
    #
    # gpg-agent is a different daemon and survives this, which is why the
    # passphrase obtained below is still in its cache afterwards.
    sudo pkill keyboxd || true

    root_can_sign_now "$key" && return 0

    if [[ ! -t 0 ]]; then
        echo "ERROR: $key needs a passphrase and there is no terminal to ask" >&2
        echo "       on. Choose 'No signing', or start the build where you can" >&2
        echo "       type." >&2
        return 1
    fi

    echo "The ISO is signed by mkarchiso running as root, which cannot ask for"
    echo "the passphrase later. Please enter it now, once."

    probe=$(mktemp) || return 1
    sig="$probe.sig"
    echo "ditana-build" > "$probe"
    if ! sudo -E gpg --pinentry-mode loopback --no-armor --output "$sig" \
             --detach-sign --default-key "$key" "$probe"; then
        sudo rm -f "$probe" "$sig"
        echo "ERROR: no passphrase, so mkarchiso could not sign either." >&2
        return 1
    fi
    sudo rm -f "$probe" "$sig"

    # The proof: the same question as at the start, which now has to answer yes.
    # A passphrase that did not reach the cache stops the build here rather than
    # eleven minutes later, at the signing step.
    if ! root_can_sign_now "$key"; then
        echo "ERROR: the passphrase did not reach the agent that mkarchiso will" >&2
        echo "       use, so the build would stop at the signing step. Check" >&2
        echo "       default-cache-ttl in ~/.gnupg/gpg-agent.conf." >&2
        return 1
    fi
    echo "Passphrase accepted; the build runs unattended from here."
}

selected_key=""
selected_signer="(none)"

# A quick rebuild replaces /root inside an existing image and signs nothing, so
# it is asked nothing.
if [[ "${1:-}" != "--quick" ]]; then
    ensure_sudo

    # The sudo timestamp expires long before mkarchiso needs it, so it is kept
    # warm here. The loop watches this shell rather than hanging off a trap,
    # because the build installs EXIT traps of its own further down and the
    # last one would win.
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null || true; sleep 50; done ) &

    select_signing_key
    [[ -z "$selected_key" ]] || ensure_signing_possible "$selected_key"

    # Clean up after the question. Trying the key as root starts a keyboxd that
    # belongs to root and holds the lock on ~/.gnupg/public-keys.d/pubring.db,
    # and `gpg --export --armor` further down runs as the user: it would sit
    # there waiting for that lock and report
    #
    #     gpg: Note: database_open ... waiting for lock (held by <pid>)
    #     gpg: key export failed: Connection timed out
    #
    # which is a build that dies for a reason having nothing to do with the key
    # it just checked.
    sudo pkill keyboxd || true
fi
# --- END credentials-up-front ------------------------------------------------

# Delete temporary files from simulated installations
rm -f  airootfs/root/bind-mount/root/installation-steps.sh
rm -f  airootfs/root/bind-mount/root/settings.sh
rm -f  airootfs/root/installation-steps.kdl
rm -rf airootfs/root/settings/
rm -rf airootfs/root/folders/

# Where the several gigabytes an ISO build needs are put down. /var/tmp and
# not /tmp, because /tmp is a tmpfs on Arch and this does not fit in RAM with
# room to spare: a quick rebuild holds the unpacked tree and a new squashfs at
# the same time, which on the build VM came to 5.0 of its 5.9 GiB. The full
# build's own work directory reached 4.1 GiB in the same place. Neither has
# failed for want of space yet; both are one larger package set away from it.
BUILD_TMP=${DITANA_BUILD_TMP:-/var/tmp}

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
    if [[ "$apply_testing_patch" == "y" ]]; then
        git status
        echo "Reversing patch..."
        git apply --reverse "${TESTING_PATCH_ARGS[@]}" use-testing-repo.patch
        echo "Finished reversing patch."
        git status
    fi
}

# Which package repository the ISO installs from, and which branch the
# installer comes from, are two different things -- use-testing-repo.patch
# swaps the mirrorlist in three files and renames the ISO, and nothing else.
# Made into one decision, they leave a combination unbuildable: the installer
# and configuration users actually have, installing the packages that are about
# to become production. That is precisely what the nightly release gate has to
# try, so it is what DITANA_BUILD_TESTING_ISO builds.
#
# The name stays "Ditana_Testing" for such an ISO, deliberately: it must never
# be mistaken for one that installs from the production repository.
#
# The configuration tag still follows the branch and not the patch. A main
# build takes 'latest' either way -- that is what users get, and testing
# against anything else would defeat the purpose.
apply_testing_patch=n
if [[ "$current_branch" != "main" ]]; then
    apply_testing_patch=y
elif [[ "${DITANA_BUILD_TESTING_ISO:-n}" == y* ]]; then
    apply_testing_patch=y
    echo "Building from main, but installing from the ditana-testing repository."
fi

# --- BEGIN versioned-tree ----------------------------------------------------
# Lifted by tests/installer/versioned-tree.t, which cuts between BEGIN and END.
#
# A signed release medium has to be the versioned state, and mkarchiso makes
# that easy to lose: it copies the profile's airootfs into the system image
# whole, so whatever lies there travels with it. A stale .orig beside a script
# rode along that way for months, in every medium built, and nothing said so.
#
# What made it invisible is a personal ignore rule -- core.excludesFile in the
# user's own configuration, `*.orig` in this case. Every `git status` on that
# machine honours it and no other machine has it, so the file is missing from
# the one report anybody would have looked at. The check therefore asks git the
# same question with that file switched off: whatever is still untracked then
# is declared nowhere in the repository, and has no business in a release.
#
# What the build itself produces is not a stray. Every one of those is named in
# the repository's own .gitignore -- the configuration archive, the extracted
# settings, ditana-version.sh, the compiled converter -- and a rule that travels
# with the repository is a declaration. That is the whole distinction: declared
# in the repository, or not declared at all.
#
# Modified tracked files are deliberately not refused, and neither are staged
# ones. A release is built and tested before it is committed, so the tree is
# expected to differ from HEAD -- and a modification stands in `git status` for
# anyone to see, which is exactly what the files this check is about do not.
# Staging is where somebody said what this file is; the line runs there.
UNVERSIONED=()
collect_unversioned() {
    local -a entries=()
    # -z, so that a path with a space or a quote in it arrives as it is: the
    # default format quotes such a name, and a quoted name would then be deleted
    # under a name that does not exist.
    mapfile -d '' -t entries < <(
        git -c core.excludesFile=/dev/null status --porcelain -z --untracked-files=all
    )
    UNVERSIONED=()
    local e
    for e in ${entries[@]+"${entries[@]}"}; do
        if [[ $e == '?? '* ]]; then UNVERSIONED+=("${e#?? }"); fi
    done
}

if [[ -n "$selected_key" && "$apply_testing_patch" == "n" ]]; then
    # .git/info/exclude does the same as the personal ignore file and travels
    # with no clone either. Empty in this repository, and the check says so
    # rather than silently trusting it.
    exclude_rules=$(grep -cvE '^[[:space:]]*(#|$)' .git/info/exclude 2>/dev/null || true)
    if (( ${exclude_rules:-0} > 0 )); then
        echo "Refusing to build: .git/info/exclude carries ${exclude_rules} rule(s)." >&2
        echo "       They hide files from this check and exist only on this machine," >&2
        echo "       so what they hide cannot be accounted for. Move them to .gitignore." >&2
        exit 1
    fi

    collect_unversioned
    if (( ${#UNVERSIONED[@]} > 0 )); then
        echo
        echo "These files are in the working tree, are not staged either, and no rule"
        echo "in the repository declares them. A release medium is the versioned state,"
        echo "and mkarchiso copies airootfs/ into it whole:"
        printf '  %s\n' "${UNVERSIONED[@]}"
        echo

        # Answered in advance the same way the signing key and the repository
        # are. With no terminal and no answer the build stops: deleting files
        # nobody was asked about is the one thing this must not do.
        remove_answer="${DITANA_REMOVE_UNVERSIONED:-}"
        if [[ -z "$remove_answer" && -t 0 ]]; then
            read -r -p "Delete them and build? [y/N] " remove_answer
        fi
        if [[ "${remove_answer,,}" != y* ]]; then
            echo "Refusing to build: a signed release must carry nothing but what is versioned." >&2
            echo "       What belongs in it wants 'git add' -- staging is the declaration," >&2
            echo "       a commit is not needed. What does not belongs deleted." >&2
            exit 1
        fi

        rm -f -- "${UNVERSIONED[@]}"
        # Asked again rather than assumed: a file that survived deletion --
        # unwritable directory, a race -- would otherwise be signed into the ISO
        # by a build that has just reported removing it.
        collect_unversioned
        if (( ${#UNVERSIONED[@]} > 0 )); then
            echo "Refusing to build: these are still in the tree after being deleted:" >&2
            printf '  %s\n' "${UNVERSIONED[@]}" >&2
            exit 1
        fi
        echo "Deleted. The working tree carries nothing the repository does not declare."
    fi
fi
# --- END versioned-tree ------------------------------------------------------

if [[ "$apply_testing_patch" == "y" ]]; then
    # The patched pacman.conf includes /etc/pacman.d/ditana-testing-mirrorlist,
    # and mkarchiso reads that file on the *host*. A host that installs from the
    # production repository has no reason to carry it, which is how the first
    # Testing ISO on the build VM failed -- with "no usable package
    # repositories configured", several minutes in and naming nothing.
    # Installing it changes no repository the host itself uses: it puts a
    # mirrorlist in place that the host's own pacman.conf does not include.
    ensure_package_installed ditana-testing-mirrorlist
    # The choice between the testing and the official repository belongs to a
    # branch build, which is the one that might want either. A main build that
    # asked for the testing repository asked for exactly that.
    if [[ "$current_branch" != "main" ]]; then
        select_testing_repository
    fi
    echo "Applying patch..."
    git apply "${TESTING_PATCH_ARGS[@]}" use-testing-repo.patch
    # Register an early cleanup so failures between here and the mode-specific
    # cleanup trap (set further below) still revert the patch.
    trap reverse_patch_if_needed EXIT
    git status
fi

# The configuration tarball follows the branch, not the package repository: a
# branch build tests the installer configuration of that branch, a main build
# the one users get.
if [[ "$current_branch" != "main" ]]; then
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

# The Raku modules the installer uses. airootfs/root/.raku becomes /root/.raku
# in the ISO and is therefore the ordinary home repository there.
#
# This has to happen before the tests below and not only before the ISO: on a
# host whose Raku carries no JSON::Fast of its own -- the build VM -- the
# tests would otherwise fail on a missing module instead of on anything they
# assert. Module tests of the third-party distributions are skipped, as they
# always were for a build nobody signs; the tests that matter here are
# Ditana's own.
mkdir -p airootfs/root/.raku
zef --force-install --contained --/test --/test-depends \
    -to="inst#/$(realpath airootfs/root/.raku)" install JSON::Fast Sparrow6

# The answer-file tests run on every build, including a quick one and one
# nobody signs. They take a couple of seconds, need neither network nor root,
# and they guard the point at which an unattended installation either proceeds
# on an answer it was given or stops -- an ISO that gets that wrong is one
# nobody can safely leave alone, which is the only kind this ISO gets used for.

# --- BEGIN no-answer-file-on-the-medium --------------------------------------
# Lifted by tests/installer/medium-answer-file.t, which cuts between BEGIN and
# END.
#
# The two marker lines are not decoration: medium-answer-file.t cuts the check
# out between them and runs it, so that what is tested is what runs here.
# Without them the suite exercises an empty string and reports that a directory
# holding an answer file is fine.
#
# Why the check exists is in that test, at length.
if [[ -e airootfs/root/autoinstall.kdl ]]; then
    echo "Refusing to build: airootfs/root/autoinstall.kdl exists." >&2
    echo "An ISO carrying it installs Ditana unattended on the first machine it" >&2
    echo "boots on, with no question asked. Move it aside for the build." >&2
    exit 1
fi
# --- END no-answer-file-on-the-medium ----------------------------------------

# Not left to `set -e`: a suite that fails would end the build with no message
# at all, several hundred lines below the failure it is about.
if ! tests/installer/run-tests; then
    echo "Refusing to build: the installer tests above did not pass." >&2
    exit 1
fi

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

    QUICK_TMP=$(mktemp -d -p "$BUILD_TMP")

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
    # mksquashfs has to run as root to read the tree, and root's umask on
    # Ditana is 027, so what it leaves behind is -rw-r----- root:root. Step 4
    # runs xorriso as the build user, which then cannot open the file it is
    # asked to put into the ISO -- and says so as "Problems with reading disk
    # file", after 0.0 seconds and with no mention of permissions.
    sudo chown "$(id -u):$(id -g)" "$QUICK_TMP/airootfs.sfs"
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

list_special_packages() {
    echo "Identifying special packages..."
    local firmware_pkgs=()
    local module_pkgs=()

    pacman_waiting -Fy >/dev/null
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

pacman_waiting -Sy
TMP_ISO=$BUILD_TMP/ditana-iso
if [[ -n "$TMP_ISO" ]]; then
    sudo rm -rf "$TMP_ISO"
fi
sudo rm -rf out

# The key was chosen at the top of the build, together with the sudo password
# and the passphrase. What that choice causes belongs here: these two take
# minutes, and nobody has to be present for them.
if [[ -n "$selected_key" ]]; then
    zef upgrade Sparrow6
    zef upgrade Tomty
    pushd tests/configuration
    tomty --color --all
    popd
    list_special_packages
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

if [[ "$apply_testing_patch" == "y" ]]; then
    LABEL+="-Testing"
fi

# Terminate any running keyboxd process to prevent conflicts with root-level GPG operations in mkarchiso.
# The keyboxd daemon is part of the GnuPG package and is started automatically by GPG whenever the keybox database is accessed.
# Currently, a root-owned keyboxd process is running, because we accessed it above. It holds locks or permissions that interfere
# with root-level operations in mkarchiso, leading to conflicts.
sudo pkill keyboxd

# The ISO boots the LTS kernel, because OpenZFS regularly lags behind a new
# mainline release and a medium whose kernel it does not support cannot create a
# pool. The mainline kernel is nevertheless installed: b43-firmware depends on
# `linux>=3.2`, so pacstrap pulls it in, and DKMS then builds the ZFS module for
# the LTS kernel only.
#
# Boot entries naming the mainline kernel therefore produce a medium that boots
# but cannot install onto ZFS. That is not hypothetical: syncing the archiso
# profile to a new upstream release has already reverted these four files once,
# and the ISO built from them failed at `zpool create`. The build refuses now
# rather than in a VM an hour later.
check_boot_entries_use_lts() {
    local offenders
    offenders=$(grep -lE '(vmlinuz-linux|initramfs-linux\.img)([^-]|$)' \
        syslinux/archiso_sys-linux.cfg \
        syslinux/archiso_pxe-linux.cfg \
        efiboot/loader/entries/*.conf 2>/dev/null || true)

    if [[ -n "$offenders" ]]; then
        echo "ERROR: these boot entries reference the mainline kernel, but the ISO ships linux-lts:" >&2
        echo "$offenders" | sed 's/^/  /' >&2
        echo "Point them at vmlinuz-linux-lts / initramfs-linux-lts.img." >&2
        exit 1
    fi
}
check_boot_entries_use_lts

echo "Creating ISO..."

echo "selected_signer: '$selected_signer'"
echo "selected_key:    '$selected_key'"
echo "LABEL:           '$LABEL'"
echo "TMP_ISO:         '$TMP_ISO'"

# --- BEGIN prime-root-gpg-agent ----------------------------------------------
# Lifted by tests/installer/gpg-priming.t, which cuts between BEGIN and END.
#
# mkarchiso signs the rootfs image itself, as root, with `gpg --batch`. Root
# gets a gpg-agent of its own -- /run/user/0 does not exist, so its socket lands
# in $GNUPGHOME beside the user's -- and that agent needs the passphrase in its
# cache. With an empty cache it runs a pinentry, and on a workstation with a GTK
# pinentry and an icon theme made of SVGs that pinentry dies before it can ask
# anything: GTK loads the icon through glycin, glycin runs its loader in bwrap,
# and the loader exits with status 1. gpg-agent then waits sixty seconds for an
# answer that will never come and reports
#
#     gpg: signing failed: Timeout
#
# Those sixty seconds are inside gpg-agent and no option reaches them.
# `pinentry-timeout` is its only timeout setting, it applies to the pinentry
# rather than to this wait, and its value of 0 means "I request no timeout"
# rather than "wait forever".
#
# The cache is filled at the top of the build, where everything that needs a
# person is asked. This call is what makes sure it is still filled: it costs
# nothing when it is, and asks again when `default-cache-ttl` is shorter than
# the build. Either way mkarchiso never meets an empty cache.
prime_root_gpg_agent() {
    ensure_signing_possible "$1"
}
# --- END prime-root-gpg-agent ------------------------------------------------

# Execute mkarchiso with elevated privileges, while preserving the current user's environment (-E).
# The GNUPGHOME environment variable points to the user's GPG home directory, ensuring that GPG operations within mkarchiso
# continue to use the user's keyring and associated permissions.
if [[ -n "$selected_key" ]]; then
    prime_root_gpg_agent "$selected_key"
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

#!/usr/bin/env bash

# Copyright (c) 2026 acrion innovations GmbH
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

usage() {
    cat <<'EOF'
diagnose-boot.sh [--to DIR]            read-only diagnosis, from the live medium
diagnose-boot.sh --repair [--dry-run]  diagnose, then rebuild what is missing
diagnose-boot.sh --root DIR ...        use a root tree that is already mounted
                                       and leave every pool alone

--to DIR copies the report as a tarball to DIR, a second stick for instance:
the medium itself is read-only, and the report is otherwise lost at reboot.

With --dry-run the exit status says whether a repair is due: 3 if there is
something to repair, 0 if there is not.
EOF
}

# Discovers the reason an installed Ditana system on ZFS fails to boot and,
# with --repair, carries out rebuilds for what an interrupted update omitted.
# The diagnosis changes nothing: the pool is imported read-only, and exported
# again thereafter.
#
# The checks follow the failure this was written for. After an update the
# kernel panicked in the initramfs with "Attempted to kill init!
# exitcode=0x00000100" and "Not tainted", fifteen seconds after the NVMe
# partitions had appeared. Fifteen seconds is how long the zfs hook waits for
# /dev/zfs before it gives up, and its `exit 1` ends PID 1. "Not tainted" says
# that no ZFS module was ever loaded, because zfs.ko taints the kernel when it
# loads. The update had been interrupted while it was running. So the questions
# are: is there a zfs.ko for the kernel in /boot, does its initramfs carry one,
# and did the update run to its end?

set -uo pipefail

POOL=ditana-root
ROOT_DATASET="$POOL/ROOT/default"
# The same place rescue.sh uses, so that either may find what the other did.
ALTROOT=/mnt

root_dir=""
copy_to=""
repair=0
dry_run=0
while (( $# > 0 )); do
    case "$1" in
        --root)    root_dir="${2:?--root needs a directory}"; shift 2 ;;
        --to)      copy_to="${2:?--to needs a directory}"; shift 2 ;;
        --repair)  repair=1; shift ;;
        --dry-run) dry_run=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
given_root="$root_dir"

REPORT="${DITANA_DIAGNOSE_REPORT:-/root/ditana-diagnosis-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$REPORT"
FINDINGS="$REPORT/00-findings.txt"
: > "$FINDINGS"

finding() { printf '%s\n' "$*" | tee -a "$FINDINGS"; }

# Every command's output goes to a file of its own, named after what it shows,
# so that the report can be read without this script beside it.
record() {
    local name="$1"; shift
    { printf '$ %s\n' "$*"; "$@" 2>&1; printf '[exit %s]\n' "$?"; } > "$REPORT/$name.txt"
}

imported_here=0
cleanup() {
    if (( imported_here )); then
        umount -R "$ALTROOT" 2>/dev/null
        zpool export "$POOL" 2>/dev/null
    fi
}
trap cleanup EXIT

# --- The pool ----------------------------------------------------------------

# $1 is ro or rw. A pool that rescue.sh has already imported is used as it
# stands, unless it is read-only and a repair needs to write.
import_pool() {
    local mode="$1"
    if zpool list -H "$POOL" >/dev/null 2>&1; then
        if [[ $mode == rw && "$(zpool get -H -o value readonly "$POOL")" == on ]]; then
            umount -R "$ALTROOT" 2>/dev/null
            zpool export "$POOL" || { finding "pool: $POOL is imported read-only and cannot be exported"; return 1; }
        else
            root_dir="$(zpool get -H -o value altroot "$POOL")"
            [[ $root_dir == - ]] && root_dir=/
            finding "pool: $POOL was already imported (altroot $root_dir) and is used as it is"
            mountpoint -q "$root_dir" || zfs mount "$ROOT_DATASET"
            return 0
        fi
    fi

    record zpool-import-list zpool import
    local -a opts=(-f -N -R "$ALTROOT" -d /dev/disk/by-id)
    # -f because the pool was last imported by the installed system, not by this
    # medium. For the diagnosis that is harmless: readonly=on writes nothing,
    # the host id in the labels included.
    [[ $mode == ro ]] && opts+=(-o readonly=on)
    if ! zpool import "${opts[@]}" "$POOL" > "$REPORT/zpool-import.txt" 2>&1; then
        finding "pool: $POOL could not be imported, see zpool-import.txt"
        return 1
    fi
    imported_here=1
    finding "pool: $POOL imported $([[ $mode == ro ]] && echo read-only || echo read-write) at $ALTROOT"

    local keyroot
    keyroot="$(zfs get -H -o value encryptionroot "$ROOT_DATASET" 2>/dev/null)"
    if [[ -n $keyroot && $keyroot != - ]] \
       && [[ "$(zfs get -H -o value keystatus "$keyroot")" != available ]]; then
        echo "The system is encrypted. Passphrase for $keyroot (the keyboard layout is US):"
        zfs load-key "$keyroot" || { finding "pool: the key for $keyroot was not loaded"; return 1; }
    fi

    if ! zfs mount "$ROOT_DATASET" > "$REPORT/zfs-mount.txt" 2>&1; then
        finding "pool: $ROOT_DATASET could not be mounted, see zfs-mount.txt"
        return 1
    fi
    root_dir="$ALTROOT"
}

record_pool() {
    record zpool-status zpool status -v "$POOL"
    record zpool-history-tail sh -c "zpool history $POOL | tail -n 300"
    record zfs-list zfs list -o name,used,mountpoint,canmount,encryption,keystatus -r "$POOL"
    record zfs-properties-local zfs get -s local all -r "$POOL/ROOT"
    # The snapshots zfs-autosnap creates prior to each pacman transaction are
    # the means to recover if a repair does not succeed. ZFSBootMenu can boot
    # them.
    record zfs-snapshots zfs list -t snapshot -o name,creation,used -s creation -r "$POOL/ROOT"
}

record_machine() {
    record live-kernel uname -a
    record lsblk lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL
    record lspci lspci -nnk
    record efibootmgr efibootmgr -v
    record dmesg-live dmesg
}

# --- The installed system ----------------------------------------------------

# Which module tree a kernel in /boot belongs to. The file name is the same for
# every version of linux-lts, so it is matched by content: the install hook of
# mkinitcpio copies /usr/lib/modules/<version>/vmlinuz to /boot.
kernel_version_of() {
    local image="$1" dir
    for dir in "$R"/usr/lib/modules/*/; do
        if [[ -f "$dir/vmlinuz" ]] && cmp -s "$image" "$dir/vmlinuz"; then
            basename "$dir"
            return 0
        fi
    done
    return 1
}

has_zfs_module() {
    [[ -n "$(find "$R/usr/lib/modules/$1" -name 'zfs.ko*' -print -quit 2>/dev/null)" ]]
}

# The last pacman transaction, from its start to the end of the log.
last_transaction() {
    awk '/\[ALPM\] transaction started/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$1"
}

# What assess() learns, and what the repair plan is built from.
BROKEN_MODULE=()      # kernel versions without a zfs.ko
BROKEN_INITRAMFS=()   # kernel versions whose initramfs carries no zfs.ko for them
MISSING_HEADERS=()    # kernel packages whose headers a DKMS build lacks
STRAY_KERNELS=()      # kernel packages whose image in /boot has no module tree
UNLISTED_MODULE=()    # kernel versions whose zfs.ko depmod has not indexed
DB_LOCK=0
TXN_INCOMPLETE=0

assess() {
    local image kver initramfs listing any=0

    BROKEN_MODULE=(); BROKEN_INITRAMFS=(); MISSING_HEADERS=(); STRAY_KERNELS=()
    UNLISTED_MODULE=(); DB_LOCK=0; TXN_INCOMPLETE=0

    for image in "$R"/boot/vmlinuz-*; do
        [[ -e $image ]] || continue
        any=1
        if ! kver="$(kernel_version_of "$image")"; then
            STRAY_KERNELS+=("${image##*/vmlinuz-}")
            finding "kernel: $(basename "$image") matches no tree in /usr/lib/modules -- the kernel in /boot is not the installed one"
            continue
        fi
        finding "kernel: $(basename "$image") is $kver"

        if has_zfs_module "$kver"; then
            finding "  zfs.ko for $kver: present"
            # modinfo and modprobe find a module by name using the index
            # depmod writes, and so does mkinitcpio. A zfs.ko that arrived
            # after the last depmod is present on disk and invisible to all
            # three.
            if ! grep -q 'zfs\.ko' "$R/usr/lib/modules/$kver/modules.dep" 2>/dev/null; then
                UNLISTED_MODULE+=("$kver")
                finding "  MISSING: zfs.ko is not in modules.dep for $kver -- depmod has not indexed it, so mkinitcpio cannot find it"
            fi
        else
            BROKEN_MODULE+=("$kver")
            finding "  MISSING: no zfs.ko under /usr/lib/modules/$kver -- the ZFS module was not built for this kernel"
            if [[ ! -d "$R/usr/lib/modules/$kver/build" ]]; then
                MISSING_HEADERS+=("$(cat "$R/usr/lib/modules/$kver/pkgbase" 2>/dev/null || echo "${image##*/vmlinuz-}")")
                finding "  MISSING: no headers for $kver, which the ZFS build needs"
            fi
        fi

        initramfs="$R/boot/initramfs-${image##*/vmlinuz-}.img"
        listing="$REPORT/initramfs-$(basename "$initramfs").txt"
        if [[ ! -e $initramfs ]]; then
            BROKEN_INITRAMFS+=("$kver")
            finding "  MISSING: $(basename "$initramfs") does not exist"
        elif ! command -v lsinitcpio >/dev/null; then
            finding "  initramfs: lsinitcpio is not available, the contents were not checked"
        elif ! lsinitcpio -l "$initramfs" > "$listing" 2>&1; then
            BROKEN_INITRAMFS+=("$kver")
            finding "  UNREADABLE: $(basename "$initramfs"), see $(basename "$listing")"
        elif grep -F "usr/lib/modules/$kver/" "$listing" | grep -q 'zfs\.ko'; then
            finding "  $(basename "$initramfs"): carries zfs.ko for $kver"
        else
            BROKEN_INITRAMFS+=("$kver")
            finding "  MISSING: $(basename "$initramfs") carries no zfs.ko for $kver -- the zfs hook then waits 15 s for /dev/zfs and init exits"
        fi
    done
    (( any )) || finding "kernel: there is no vmlinuz in /boot"

    # The lock is removed when pacman ends, however it ends, unless it is killed
    # outright or the machine goes down while it runs.
    if [[ -e "$R/var/lib/pacman/db.lck" ]]; then
        DB_LOCK=1
        finding "pacman: db.lck is present -- a pacman run did not end ($(stat -c %y "$R/var/lib/pacman/db.lck" | cut -d. -f1))"
    fi

    if [[ -r "$R/var/log/pacman.log" ]]; then
        last_transaction "$R/var/log/pacman.log" > "$REPORT/pacman-last-transaction.txt"
        # pacman logs "transaction completed" once the packages are in place and
        # before the hooks run. Missing, it means the packages themselves were
        # interrupted.
        if grep -q '\[ALPM\] transaction started' "$REPORT/pacman-last-transaction.txt" \
           && ! grep -q '\[ALPM\] transaction completed' "$REPORT/pacman-last-transaction.txt"; then
            TXN_INCOMPLETE=1
            finding "pacman: the last transaction was interrupted while it installed packages"
        fi
        local hooks
        hooks="$(sed -n "s/.*\[ALPM\] running '\(.*\)'\.\.\./\1/p" "$REPORT/pacman-last-transaction.txt" | tr '\n' ' ')"
        [[ -n $hooks ]] && finding "pacman: hooks of the last transaction: $hooks"
    fi
}

examine_root() {
    record os-release cat "$R/etc/os-release"
    record boot-listing ls -la "$R/boot"
    record modules-listing ls -la "$R/usr/lib/modules"
    record mkinitcpio-conf sh -c "grep -E '^(MODULES|HOOKS|BINARIES|FILES)=' '$R/etc/mkinitcpio.conf'; ls -la '$R/etc/mkinitcpio.conf.d' '$R/etc/mkinitcpio.d'; cat '$R'/etc/mkinitcpio.d/*.preset"
    record packages pacman --root "$R" --dbpath "$R/var/lib/pacman" -Q \
        linux-lts linux-lts-headers linux linux-headers zfs-dkms zfs-utils \
        zfs-linux-lts zfs-linux dkms mkinitcpio zfsbootmenu ditana-userns-guard
    record packages-missing-files sh -c "pacman --root '$R' --dbpath '$R/var/lib/pacman' -Qk 2>&1 | grep -v ' 0 missing files'"
    record dkms-tree sh -c "ls -laR '$R/var/lib/dkms/zfs' 2>&1 | head -n 300"
    local make_log
    for make_log in "$R"/var/lib/dkms/zfs/*/build/make.log; do
        [[ -e $make_log ]] && cp "$make_log" "$REPORT/dkms-make-$(basename "$(dirname "$(dirname "$make_log")")").log"
    done
    record pacman-log-tail tail -n 400 "$R/var/log/pacman.log"
    record userns-guard sh -c "cat '$R/etc/ditana/userns-allow.conf'; ls -la '$R/etc/systemd/system/sysinit.target.wants/'; grep -rH . '$R/etc/sysctl.d'"
    record journal-boots journalctl -D "$R/var/log/journal" --list-boots
    record journal-last-boot journalctl -D "$R/var/log/journal" -b -1 -p warning --no-pager
    assess
}

# --- The repair --------------------------------------------------------------

# Two phases, since the second can only be scheduled after the first is
# completed. The first brings the packages to a consistent state: an
# interrupted transaction is finalized, a kernel whose image in /boot lacks a
# module tree is reinstalled, and missing headers are installed. pacman's
# internal hooks then build the module and the initramfs, frequently resulting
# in the second phase having nothing to execute. The second phase builds
# whatever is still missing.
package_steps() {
    local pkg
    PLAN=()
    (( DB_LOCK )) && PLAN+=("rm -f /var/lib/pacman/db.lck")
    (( TXN_INCOMPLETE )) && PLAN+=("pacman -Syu")
    for pkg in "${STRAY_KERNELS[@]}"; do PLAN+=("pacman -S $pkg"); done
    for pkg in "${MISSING_HEADERS[@]}"; do PLAN+=("pacman -S $pkg-headers"); done
}

build_steps() {
    local kver zfs_version
    PLAN=()
    zfs_version="$(find "$R/usr/src" -maxdepth 1 -name 'zfs-*' -printf '%f\n' 2>/dev/null | sed 's/^zfs-//' | sort -V | tail -n 1)"
    for kver in "${BROKEN_MODULE[@]}"; do
        if [[ -n $zfs_version ]]; then
            PLAN+=("dkms install --force zfs/$zfs_version -k $kver")
        else
            PLAN+=("pacman -S zfs-dkms")
        fi
    done
    for kver in "${UNLISTED_MODULE[@]}"; do
        PLAN+=("depmod $kver")
    done
    if (( ${#BROKEN_MODULE[@]} || ${#BROKEN_INITRAMFS[@]} || ${#UNLISTED_MODULE[@]} )); then
        PLAN+=("mkinitcpio -P")
    fi
}

run_steps() {
    local step
    for step in "${PLAN[@]}"; do
        echo
        echo ">>> $step"
        case "$step" in
            dkms*) echo "    Building the ZFS module takes several minutes and prints nothing meanwhile. Do not interrupt it." ;;
            pacman*) echo "    This needs a network connection (ethernet, or iwctl for Wi-Fi)." ;;
        esac
        if ! arch-chroot "$R" sh -c "$step"; then
            echo
            echo "The step failed: $step"
            echo "The pool stays imported at $ALTROOT; arch-chroot $ALTROOT opens a shell in the system."
            imported_here=0
            return 1
        fi
    done
}

still_broken() {
    (( ${#BROKEN_MODULE[@]} || ${#BROKEN_INITRAMFS[@]} || ${#STRAY_KERNELS[@]} || ${#UNLISTED_MODULE[@]} || DB_LOCK || TXN_INCOMPLETE ))
}

repair_system() {
    package_steps
    local packages=("${PLAN[@]}")
    build_steps
    local builds=("${PLAN[@]}")

    echo
    if (( ${#packages[@]} == 0 && ${#builds[@]} == 0 )); then
        echo "Nothing to repair: the kernel in /boot has its zfs.ko, the initramfs carries it,"
        echo "and the last update ran to its end. The cause lies elsewhere; the report has the rest."
        return 0
    fi
    echo "Repair plan, run inside the installed system:"
    printf '  %s\n' "${packages[@]}" "${builds[@]}"
    if (( ${#packages[@]} && ${#builds[@]} )); then
        echo "  (the build steps are decided again once the package steps are done)"
    fi
    (( dry_run )) && return 3

    if [[ -n "$(blkid -L ditana-efi 2>/dev/null)" ]] && ! mountpoint -q "$R/boot/efi"; then
        mkdir -p "$R/boot/efi" && mount "$(blkid -L ditana-efi)" "$R/boot/efi"
    fi

    if (( ${#packages[@]} )); then
        PLAN=("${packages[@]}")
        run_steps || return 1
        echo
        echo "Checking again after the package steps:"
        assess
        build_steps
    fi
    run_steps || return 1

    echo
    echo "Checking again:"
    assess
    if still_broken; then
        echo "Not repaired. The pool stays imported at $ALTROOT; arch-chroot $ALTROOT opens a shell in the system."
        imported_here=0
        return 1
    fi
    umount -R "$ALTROOT" 2>/dev/null
    if zpool export "$POOL"; then
        imported_here=0
        echo
        echo "Repaired, and the pool is exported. Remove the stick and reboot."
    else
        imported_here=0
        echo "Repaired, but the pool could not be exported. Run: zpool export $POOL" >&2
    fi
}

# --- Run ---------------------------------------------------------------------

if [[ -z $given_root ]]; then
    if (( EUID != 0 )); then
        echo "Run this as root, from the Ditana live medium." >&2
        exit 1
    fi
    record_machine
    mode=ro
    (( repair && ! dry_run )) && mode=rw
    import_pool "$mode" && record_pool
fi

R="$root_dir"
if [[ -n $R && -d "$R/usr/lib/modules" ]]; then
    examine_root
else
    finding "system: there was no installed root tree to examine"
    exit 1
fi

echo
echo "Findings (also in $FINDINGS):"
sed 's/^/  /' "$FINDINGS"

tarball="$REPORT.tar.gz"
tar -czf "$tarball" -C "$(dirname "$REPORT")" "$(basename "$REPORT")"
echo
echo "Full report: $tarball"
if [[ -n $copy_to ]]; then
    if cp "$tarball" "$copy_to"/ && sync; then
        echo "Copied to $copy_to/$(basename "$tarball")"
    else
        echo "Could not copy it to $copy_to" >&2
    fi
fi

(( repair )) || exit 0
repair_system

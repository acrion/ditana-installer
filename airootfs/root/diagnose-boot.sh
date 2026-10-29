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
diagnose-boot.sh [--to DIR]...          read-only diagnosis, from the live medium
diagnose-boot.sh --repair [--dry-run]   diagnose, then do what an interrupted update left undone
diagnose-boot.sh --root DIR ...         use a root tree that is already mounted
                                        and leave every pool alone

--to DIR copies the report as a tarball to DIR, and may be given more than
once: the medium itself is read-only, and the report is otherwise lost at
reboot. A repair copies it again when it ends, with what the repair printed.

With --dry-run the exit status says whether a repair is due: 3 if there is
something to repair, 0 if there is not.
EOF
}

# Discovers the cause why an installed Ditana system fails to boot and, with
# --repair, performs what an interrupted update left undone. The diagnosis
# changes nothing: the pool is imported in read-only mode, and re-exported
# thereafter.
#
# The checks follow the failure this was written for. After an update, the
# kernel panicked in the initramfs with "Attempted to kill init!
# exitcode=0x00000100" and "Not tainted", fifteen seconds after the NVMe
# partitions became visible. Fifteen seconds is the duration the zfs hook waits
# for /dev/zfs before abandoning the attempt, and its `exit 1` ends PID 1. "Not
# tainted" says that no ZFS module was ever loaded, as zfs.ko taints the kernel
# upon loading. The update had been interrupted during execution. Thus, the
# inquiries are: is there a zfs.ko for the kernel located in /boot, does the
# initramfs carry one, and did the update complete its run?
#
# Only the initial two inquiries pertain to ZFS. An interrupted update leaves a
# system on btrfs, ext4, or xfs equally unable to start: a kernel in /boot
# whose modules do not align, no kernel in /boot whatsoever, or an initramfs
# that is absent. These validations therefore execute across every filesystem,
# with the ZFS-specific checks applying to an installed system that constructs
# its initramfs using the zfs hook.

set -uo pipefail

POOL=ditana-root
ROOT_DATASET="$POOL/ROOT/default"
# The same place rescue.sh uses, so that either may find what the other did.
ALTROOT=/mnt
# What runs a repair step within the installed system. The tests replace it,
# as they replace the report's location.
CHROOT="${DITANA_DIAGNOSE_CHROOT:-arch-chroot}"
# Below this amount, a DKMS build or the kernel's initramfs may run out of
# space.
MIN_FREE_MB="${DITANA_DIAGNOSE_MIN_FREE_MB:-1024}"

root_dir=""
copy_to=()
repair=0
dry_run=0
while (( $# > 0 )); do
    case "$1" in
        --root)    root_dir="${2:?--root needs a directory}"; shift 2 ;;
        --to)      copy_to+=("${2:?--to needs a directory}"); shift 2 ;;
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

# A finding that keeps the system from starting, or keeps a repair from
# working. They are listed once again under "Problems:", the section the rescue
# system shows in its dialog, and likewise the root reasons under "Cause:".
PROBLEMS=()
CAUSES=()
problem() { local text="$*"; finding "$text"; PROBLEMS+=("${text#"${text%%[! ]*}"}"); }
cause()   { local text="$*"; finding "$text"; CAUSES+=("${text#"${text%%[! ]*}"}"); }

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
    record zpool-history-tail sh -c "zpool history $POOL | tail -n 1000"
    record zfs-list zfs list -o name,used,avail,mountpoint,canmount,encryption,keystatus -r "$POOL"
    record zpool-properties zpool get bootfs,compatibility,readonly,health "$POOL"
    record zfs-properties-local zfs get -s local all -r "$POOL/ROOT"
    # zfs-autosnap captures the system via snapshots before each upgrade
    # transaction. A snapshot serves as a recovery path should a repair
    # fail: ZFSBootMenu can boot from it once it has been cloned or reverted
    # to.
    record zfs-snapshots zfs list -t snapshot -o name,creation,used -s creation -r "$POOL/ROOT"
}

record_machine() {
    record live-kernel uname -a
    record lsblk lsblk -o NAME,SIZE,TYPE,TRAN,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL
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

# Whether the initramfs ($1) listing includes module $3 within the kernel $2
# directory. One awk command instead of a grep into grep -q: under pipefail,
# the first grep may terminate due to SIGPIPE once the second has gathered
# sufficient data, leading to a module that is present being reported as
# missing.
image_carries() {
    awk -v dir="usr/lib/modules/$2/" -v module="/$3.ko" \
        'index($0, dir) && index($0, module) { found = 1 } END { exit !found }' "$1"
}

# The version of an installed package, read from pacman's local database.
installed_version() {
    local desc
    for desc in "$R"/var/lib/pacman/local/"$1"-*/desc; do
        [[ -f $desc ]] || continue
        awk -v name="$1" '
            /^%NAME%$/    { getline; n = $0 }
            /^%VERSION%$/ { getline; v = $0 }
            END { if (n == name) print v }' "$desc" | grep . && return 0
    done
    return 1
}

# The last pacman transaction, from its start to the end of the log.
last_transaction() {
    awk '/\[ALPM\] transaction started/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$1"
}

# How every build from the most recent execution of the DKMS install hook
# ended, one line per build: date, module/version, kernel, outcome. The hook
# logs "==> dkms install" before initiating a build, issues a WARNING
# containing the exit code following a failed build, and outputs one "==>
# depmod <kernel>" once all builds for a specific kernel have been finalized.
# Builds proceed sequentially, so a build immediately followed by the next
# indicates the prior was finished; a build followed by nothing before the
# next hook implies it was interrupted. That is precisely what occurs when the
# terminal is closed or Ctrl+C is pressed during an update: the signal kills
# the hook, pacman detects the interruption and proceeds with the remaining
# hooks, then logs "transaction completed" as though no issue had happened.
dkms_outcomes() {
    awk '
        function start(line) {
            n = 0; when = substr(line, 2, 19)
            split("", mod); split("", kv); split("", res)
        }
        function finish() {
            if (n == 0) return
            out = ""
            for (i = 1; i <= n; i++) out = out when " " mod[i] " " kv[i] " " res[i] "\n"
            last = out
        }
        function parse(text,    i, f, m) {
            m = split(text, f, /[ `'"'"']+/)
            pm = ""; pk = ""
            for (i = 1; i <= m; i++) {
                if (f[i] == "-k") pk = f[i + 1]
                else if (f[i] ~ /\// && pm == "") pm = f[i]
            }
        }
        /\[ALPM\] running .70-dkms-install\.hook/ { finish(); start($0); inhook = 1; next }
        /\[ALPM\] (running|transaction started)/  { if (inhook) finish(); inhook = 0; next }
        !inhook { next }
        /==> dkms install / {
            if (n && res[n] == "running") res[n] = "built-not-indexed"
            parse(substr($0, index($0, "dkms install")))
            n++; mod[n] = pm; kv[n] = pk; res[n] = "running"
            next
        }
        /==> WARNING: `dkms install / {
            parse(substr($0, index($0, "dkms install")))
            for (i = 1; i <= n; i++) if (mod[i] == pm && kv[i] == pk) res[i] = "failed-" $NF
            next
        }
        /==> depmod / {
            for (i = 1; i <= n; i++) if (kv[i] == $NF && (res[i] == "running" || res[i] == "built-not-indexed")) res[i] = "built"
            next
        }
        /==> ERROR: Missing .* kernel headers for module / {
            k = $0; sub(/.*Missing /, "", k); sub(/ .*/, "", k)
            m = $NF; sub(/\.$/, "", m)
            n++; mod[n] = m; kv[n] = k; res[n] = "no-headers"
            next
        }
        END { if (inhook) finish(); printf "%s", last }
    ' "$1"
}

# What assess() learns, and what the repair plan is built from.
BROKEN_MODULE=()      # kernel versions without a zfs.ko
BROKEN_INITRAMFS=()   # kernel versions whose initramfs is missing, unreadable, or lacks a module it needs
MISSING_HEADERS=()    # kernel packages whose headers a DKMS build lacks
STRAY_KERNELS=()      # kernel packages whose image in /boot has no module tree
MISSING_KERNELS=()    # kernel packages that are installed and have no image in /boot
UNLISTED_MODULE=()    # kernel versions whose zfs.ko depmod has not indexed
DB_LOCK=0
TXN_INCOMPLETE=0
NEEDS_ZFS=0

assess() {
    local image kver initramfs listing tree pkgbase line any=0

    BROKEN_MODULE=(); BROKEN_INITRAMFS=(); MISSING_HEADERS=(); STRAY_KERNELS=()
    MISSING_KERNELS=(); UNLISTED_MODULE=(); DB_LOCK=0; TXN_INCOMPLETE=0
    PROBLEMS=(); CAUSES=()

    NEEDS_ZFS=0
    if grep -qw zfs < <(grep -hsE '^[[:space:]]*(HOOKS|MODULES)' "$R/etc/mkinitcpio.conf" "$R"/etc/mkinitcpio.conf.d/*.conf); then
        NEEDS_ZFS=1
        finding "system: the initramfs is built with the zfs hook, so every kernel needs its zfs.ko"
    else
        finding "system: the initramfs is built without the zfs hook, so ZFS is not checked"
    fi

    for image in "$R"/boot/vmlinuz-*; do
        [[ -e $image ]] || continue
        any=1
        if ! kver="$(kernel_version_of "$image")"; then
            STRAY_KERNELS+=("${image##*/vmlinuz-}")
            problem "kernel: $(basename "$image") matches no tree in /usr/lib/modules -- the kernel in /boot is not the installed one"
            continue
        fi
        finding "kernel: $(basename "$image") is $kver"

        if (( NEEDS_ZFS )); then
            if has_zfs_module "$kver"; then
                finding "  zfs.ko for $kver: present"
                # modinfo and modprobe find a module by name using the index
                # depmod writes, and so does mkinitcpio. A zfs.ko that arrived
                # after the last depmod is present on disk and invisible to all
                # three.
                if ! grep -q 'zfs\.ko' "$R/usr/lib/modules/$kver/modules.dep" 2>/dev/null; then
                    UNLISTED_MODULE+=("$kver")
                    problem "  MISSING: zfs.ko is not in modules.dep for $kver -- depmod has not indexed it, so mkinitcpio cannot find it"
                fi
            else
                BROKEN_MODULE+=("$kver")
                problem "  MISSING: no zfs.ko under /usr/lib/modules/$kver -- the ZFS module was not built for this kernel"
                if [[ ! -d "$R/usr/lib/modules/$kver/build" ]]; then
                    MISSING_HEADERS+=("$(cat "$R/usr/lib/modules/$kver/pkgbase" 2>/dev/null || echo "${image##*/vmlinuz-}")")
                    problem "  MISSING: no headers for $kver, which the ZFS build needs"
                fi
            fi
        fi

        initramfs="$R/boot/initramfs-${image##*/vmlinuz-}.img"
        listing="$REPORT/initramfs-$(basename "$initramfs").txt"
        if [[ ! -e $initramfs ]]; then
            BROKEN_INITRAMFS+=("$kver")
            problem "  MISSING: $(basename "$initramfs") does not exist"
        elif ! command -v lsinitcpio >/dev/null; then
            finding "  initramfs: lsinitcpio is not available, the contents were not checked"
        elif ! lsinitcpio -l "$initramfs" > "$listing" 2>&1; then
            BROKEN_INITRAMFS+=("$kver")
            problem "  UNREADABLE: $(basename "$initramfs"), see $(basename "$listing")"
        elif (( ! NEEDS_ZFS )); then
            finding "  $(basename "$initramfs"): readable"
        elif ! image_carries "$listing" "$kver" zfs; then
            BROKEN_INITRAMFS+=("$kver")
            problem "  MISSING: $(basename "$initramfs") carries no zfs.ko for $kver -- the zfs hook then waits 15 s for /dev/zfs and init exits"
        elif ! image_carries "$listing" "$kver" spl; then
            # zfs.ko fails to load without spl.ko, and only the kernel log of a
            # boot that ultimately ends in the same manner states this.
            BROKEN_INITRAMFS+=("$kver")
            problem "  MISSING: $(basename "$initramfs") carries no spl.ko for $kver, which zfs.ko needs -- init exits as it does without zfs.ko"
        else
            finding "  $(basename "$initramfs"): carries zfs.ko and spl.ko for $kver"
        fi
    done
    (( any )) || finding "kernel: there is no vmlinuz in /boot"

    # A kernel package lacking its image in /boot. Each kernel upgrade begins
    # with the removal of the image (60-mkinitcpio-remove), and only the final
    # one of its hooks puts the new image there, minutes later after DKMS has
    # completed its build. A machine powered down during this interval has
    # nothing for the bootloader to start. What remains of a removed kernel's
    # tree carries neither vmlinuz nor pkgbase, so it does not count.
    for tree in "$R"/usr/lib/modules/*/; do
        [[ -f $tree/vmlinuz && -f $tree/pkgbase ]] || continue
        pkgbase="$(<"$tree/pkgbase")"
        [[ -e "$R/boot/vmlinuz-$pkgbase" ]] && continue
        MISSING_KERNELS+=("$pkgbase")
        problem "kernel: MISSING: /boot/vmlinuz-$pkgbase -- $pkgbase $(basename "$tree") is installed, but its image is not in /boot"
    done

    # A line in modprobe.d that keeps zfs or spl from loading. No Ditana
    # package writes such a line. It is not removed automatically: somebody
    # wrote it.
    if (( NEEDS_ZFS )); then
        while IFS= read -r line; do
            problem "modprobe: BLOCKED: ${line#"$R"} -- the module named there is not loaded at boot"
        done < <(grep -HE '^[[:space:]]*(blacklist|install)[[:space:]]+(zfs|spl)([[:space:]]|$)' \
                      "$R"/etc/modprobe.d/*.conf "$R"/usr/lib/modprobe.d/*.conf 2>/dev/null)
    fi

    local free_mb
    free_mb="$(df -Pm "$R" 2>/dev/null | awk 'NR == 2 { print $4 }')"
    if [[ $free_mb =~ ^[0-9]+$ ]]; then
        if (( free_mb < MIN_FREE_MB )); then
            problem "space: LOW: $free_mb MiB free in the installed system -- a DKMS build or an update needs more than that"
        else
            finding "space: $free_mb MiB free"
        fi
    fi

    # The lock is removed when pacman ends, however it ends, unless it is killed
    # outright or the machine goes down while it runs.
    if [[ -e "$R/var/lib/pacman/db.lck" ]]; then
        DB_LOCK=1
        problem "pacman: db.lck is present -- a pacman run did not end ($(stat -c %y "$R/var/lib/pacman/db.lck" | cut -d. -f1))"
    fi

    if [[ -r "$R/var/log/pacman.log" ]]; then
        last_transaction "$R/var/log/pacman.log" > "$REPORT/pacman-last-transaction.txt"
        # pacman logs "transaction completed" once the packages are in place and
        # before the hooks run. Missing, it means the packages themselves were
        # interrupted.
        if grep -q '\[ALPM\] transaction started' "$REPORT/pacman-last-transaction.txt" \
           && ! grep -q '\[ALPM\] transaction completed' "$REPORT/pacman-last-transaction.txt"; then
            TXN_INCOMPLETE=1
            problem "pacman: the last transaction was interrupted while it installed packages"
        fi
        local hooks
        hooks="$(sed -n "s/.*\[ALPM\] running '\(.*\)'\.\.\./\1/p" "$REPORT/pacman-last-transaction.txt" | tr '\n' ' ')"
        [[ -n $hooks ]] && finding "pacman: hooks of the last transaction: $hooks"

        local when module kernel outcome
        while read -r when module kernel outcome; do
            case "$outcome" in
                built)             finding "dkms: $when $module for $kernel: built" ;;
                built-not-indexed) cause "dkms: $when $module for $kernel was built, but the update was stopped before depmod indexed it" ;;
                running)           cause "dkms: $when the build of $module for $kernel was cut off -- the update was stopped while it built, by closing its window or Ctrl+C for instance" ;;
                failed-*)          cause "dkms: $when the build of $module for $kernel failed with exit code ${outcome#failed-} -- its make.log is in the report" ;;
                no-headers)        cause "dkms: $when $module was not built for $kernel, because its headers were missing" ;;
            esac
        done < <(dkms_outcomes "$R/var/log/pacman.log")
    fi
}

examine_root() {
    local make_log name
    record os-release cat "$R/etc/os-release"
    record boot-listing sh -c "ls -la '$R/boot'; ls -laR '$R/boot/efi' 2>/dev/null | head -n 200"
    record mounts findmnt -R "$R"
    record space df -h "$R" "$R/boot" "$R/home"
    record modules-listing ls -la "$R/usr/lib/modules"
    record mkinitcpio-conf sh -c "grep -E '^(MODULES|HOOKS|BINARIES|FILES)=' '$R/etc/mkinitcpio.conf'; ls -la '$R/etc/mkinitcpio.conf.d' '$R/etc/mkinitcpio.d'; cat '$R'/etc/mkinitcpio.d/*.preset"
    record modprobe-conf sh -c "grep -rH . '$R/etc/modprobe.d' '$R/usr/lib/modprobe.d'"
    record bootloader-conf sh -c "grep -H . '$R/etc/default/grub' '$R'/boot/loader/entries/*.conf '$R'/boot/efi/loader/entries/*.conf 2>/dev/null"
    record packages pacman --root "$R" --dbpath "$R/var/lib/pacman" -Q \
        linux-lts linux-lts-headers linux linux-headers zfs-dkms zfs-utils \
        zfs-linux-lts zfs-linux dkms mkinitcpio zfsbootmenu ditana-userns-guard
    record packages-missing-files sh -c "pacman --root '$R' --dbpath '$R/var/lib/pacman' -Qk 2>&1 | grep -v ' 0 missing files'"
    record package-cache sh -c "ls -la '$R/var/cache/pacman/pkg' | grep -E 'linux|zfs|dkms'"
    record dkms-tree sh -c "ls -laR '$R/var/lib/dkms' 2>&1 | head -n 600"
    # Both the log from an unfinished build and the one DKMS maintains for a
    # finished build, whose time stamp dates the build against the hooks in
    # pacman.log.
    while IFS= read -r make_log; do
        name="${make_log#"$R/var/lib/dkms/"}"
        cp "$make_log" "$REPORT/dkms-${name//\//_}"
    done < <(find "$R/var/lib/dkms" -name make.log 2>/dev/null)
    cp "$R/var/log/pacman.log" "$REPORT/pacman.log" 2>/dev/null
    record userns-guard sh -c "cat '$R/etc/ditana/userns-allow.conf'; ls -la '$R/etc/systemd/system/sysinit.target.wants/'; grep -rH . '$R/etc/sysctl.d'"
    record journal-boots journalctl -D "$R/var/log/journal" --list-boots
    # A boot that encounters failure within the initramfs never reaches the
    # journal of the installed system, so its most recent boot there is the
    # prior one: the session during which the update ran, and with it the end
    # of that session.
    record journal-last-boot journalctl -D "$R/var/log/journal" -b -0 -o short-iso -n 200000 --no-pager
    assess
}

summary() {
    echo
    echo "Findings (also in $FINDINGS):"
    sed 's/^/  /' "$FINDINGS"
    if (( ${#PROBLEMS[@]} )); then
        echo
        echo "Problems:"
        printf '  %s\n' "${PROBLEMS[@]}"
    fi
    if (( ${#CAUSES[@]} )); then
        echo
        echo "Cause:"
        printf '  %s\n' "${CAUSES[@]}"
    fi
}

# Packs the report and copies it to each --to directory. A repair calls it
# twice: before any modifications, ensuring that a repair which hangs or
# loses power still leaves the diagnosis, and upon completion, with the
# output it produced.
deliver_report() {
    local dir
    tarball="$REPORT.tar.gz"
    tar -czf "$tarball" -C "$(dirname "$REPORT")" "$(basename "$REPORT")"
    echo
    echo "Full report: $tarball"
    for dir in "${copy_to[@]}"; do
        if mkdir -p "$dir" && cp "$tarball" "$dir"/ && sync; then
            echo "Copied to $dir/$(basename "$tarball")"
        else
            echo "Could not copy it to $dir" >&2
        fi
    done
}

# --- The repair --------------------------------------------------------------

# Where a package that is reinstalled at exactly the version it currently holds
# comes from: the package cache, which does not require network access, or
# alternatively the Arch Linux Archive, which keeps every version. `pacman -S`
# would install the package as listed in the package database, and the update
# that broke the system also synchronised that database: its kernel is more
# recent than the one currently installed, and its headers fail to compile a
# module for the installed kernel.
package_source() {
    local pkg="$1" version="$2" file
    for file in "$R/var/cache/pacman/pkg/$pkg-$version"-*.pkg.tar.*; do
        [[ -f $file && $file != *.sig ]] || continue
        echo "/var/cache/pacman/pkg/${file##*/}"
        return 0
    done
    echo "https://archive.archlinux.org/packages/${pkg:0:1}/$pkg/$pkg-$version-x86_64.pkg.tar.zst"
}

# $1 refers to the package to reinstall, $2 denotes the package whose
# installed version it must match: the kernel itself, for its headers.
reinstall_step() {
    local version
    if version="$(installed_version "$2")"; then
        echo "pacman -U --noconfirm $(package_source "$1" "$version")"
    else
        echo "pacman -S --noconfirm $1"
    fi
}

# Two phases, as the second may only be scheduled once the first is
# completed. The first brings the packages to a consistent state: an
# interrupted transaction is finalized, a kernel whose image in /boot is
# missing or lacks a module tree is reinstalled, and missing headers are
# installed. pacman's own hooks then build the module and the initramfs,
# frequently leading to the second phase having nothing to execute. The
# second phase builds whatever remains missing.
package_steps() {
    local pkg
    PLAN=()
    (( DB_LOCK )) && PLAN+=("rm -f /var/lib/pacman/db.lck")
    # What an update that halted during package installation leaves
    # behind determines all else, so it is finished first, and the rest
    # is decided afterwards.
    if (( TXN_INCOMPLETE )); then
        PLAN+=("pacman -Syu --noconfirm")
        return
    fi
    for pkg in "${STRAY_KERNELS[@]}" "${MISSING_KERNELS[@]}"; do
        PLAN+=("$(reinstall_step "$pkg" "$pkg")")
    done
    for pkg in "${MISSING_HEADERS[@]}"; do
        PLAN+=("$(reinstall_step "$pkg-headers" "$pkg")")
    done
}

build_steps() {
    local kver zfs_version
    PLAN=()
    zfs_version="$(find "$R/usr/src" -maxdepth 1 -name 'zfs-*' -printf '%f\n' 2>/dev/null | sed 's/^zfs-//' | sort -V | tail -n 1)"
    for kver in "${BROKEN_MODULE[@]}"; do
        if [[ -n $zfs_version ]]; then
            PLAN+=("dkms install --force zfs/$zfs_version -k $kver")
        else
            PLAN+=("pacman -S --noconfirm zfs-dkms")
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
            "pacman -U "*/var/cache/*) echo "    Installing it again runs its hooks, which build its modules and initramfs: several minutes. Do not interrupt it." ;;
            pacman*) echo "    This needs a network connection (ethernet, or iwctl for Wi-Fi). It can take several minutes. Do not interrupt it." ;;
        esac
        # zfs-autosnap and timeshift-autosnap each create a snapshot of the
        # system before every upgrade, afterwards removing the oldest
        # snapshots. Every such step might capture the broken system and
        # potentially eliminate the final snapshot taken before the update
        # that caused the failure. Both skip the operation when SKIP_AUTOSNAP
        # is set.
        if ! "$CHROOT" "$R" env SKIP_AUTOSNAP=1 sh -c "$step"; then
            echo
            echo "The step failed: $step"
            echo "The installed system stays mounted at $R; arch-chroot $R opens a shell in it."
            return 1
        fi
    done
}

still_broken() {
    (( ${#BROKEN_MODULE[@]} || ${#BROKEN_INITRAMFS[@]} || ${#STRAY_KERNELS[@]} || ${#MISSING_KERNELS[@]} \
       || ${#UNLISTED_MODULE[@]} || DB_LOCK || TXN_INCOMPLETE ))
}

repair_system() {
    package_steps
    local packages=("${PLAN[@]}")
    build_steps
    local builds=("${PLAN[@]}")

    echo
    if (( ${#packages[@]} == 0 && ${#builds[@]} == 0 )); then
        if (( ${#PROBLEMS[@]} )); then
            echo "Nothing to repair automatically: the problems above need a decision this script does not take."
        else
            echo "Nothing to repair: every kernel in /boot matches its modules and has its initramfs,"
            echo "and the last update ran to its end. The cause lies elsewhere; the report has the rest."
        fi
        return 0
    fi
    echo "Repair plan, run inside the installed system:"
    printf '  %s\n' "${packages[@]}" "${builds[@]}"
    if (( ${#packages[@]} && (${#builds[@]} || TXN_INCOMPLETE) )); then
        echo "  (the steps after these are decided again once they are done)"
    fi
    (( dry_run )) && return 3

    if [[ -n "$(blkid -L ditana-efi 2>/dev/null)" ]] && ! mountpoint -q "$R/boot/efi"; then
        mkdir -p "$R/boot/efi" && mount "$(blkid -L ditana-efi)" "$R/boot/efi"
    fi

    local round
    for round in 1 2; do
        package_steps
        (( ${#PLAN[@]} )) || break
        run_steps || return 1
        echo
        echo "Checking again after the package steps (round $round):"
        assess
    done
    build_steps
    run_steps || return 1

    echo
    echo "Checking again:"
    assess
    if still_broken; then
        echo "Not repaired. The installed system stays mounted at $R; arch-chroot $R opens a shell in it."
        return 1
    fi
    echo
    echo "Repaired."
}

# --- Run ---------------------------------------------------------------------

if [[ -z $given_root ]]; then
    if (( EUID != 0 )); then
        echo "Run this as root, from the Ditana live medium." >&2
        exit 1
    fi
    mode=ro
    (( repair && ! dry_run )) && mode=rw
    import_pool "$mode"
fi

R="$root_dir"
if [[ -z $R || ! -d "$R/usr/lib/modules" ]]; then
    finding "system: there was no installed root tree to examine"
    exit 1
fi

(( EUID == 0 )) && record_machine
[[ "$(findmnt -no FSTYPE --target "$R" 2>/dev/null)" == zfs ]] && record_pool
examine_root
summary

if (( ! repair )); then
    deliver_report
    exit 0
fi

if (( dry_run )); then
    repair_system | tee "$REPORT/repair-plan.txt"
    status=${PIPESTATUS[0]}
    deliver_report
    exit "$status"
fi

deliver_report
repair_system 2>&1 | tee "$REPORT/repair.txt"
status=${PIPESTATUS[0]}
echo "repair: exit $status" >> "$FINDINGS"
deliver_report

if (( status != 0 )); then
    # The pool stays imported and mounted, for manual work.
    imported_here=0
    exit "$status"
fi
if (( imported_here )); then
    umount -R "$ALTROOT" 2>/dev/null
    if zpool export "$POOL"; then
        imported_here=0
        echo "The pool is exported. Remove the stick and reboot."
    else
        imported_here=0
        echo "The pool could not be exported. Run: zpool export $POOL" >&2
    fi
fi
exit 0

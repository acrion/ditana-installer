# Unattended installation

An answer file predefines what the installer would normally inquire about. Each setting it names is enacted prior to the first dialog appearing, and each step whose queries are resolved is skipped. Nothing else about the installer is altered: the same settings govern the same installation, so an unattended install and an interactive one cannot diverge.

## Where the installer looks

The first of these that exists takes precedence.

1. `ditana.autoinstall=<URL|path>` on the kernel command line. This is the method a hosting provider employs: it endures PXE and requires no altered image. A URL is retrieved via `curl`; if the retrieval fails the execution halts instead of proceeding from another source.
2. A filesystem marked `DITANA_AUTO` on any connected device, containing `autoinstall.kdl` in its root directory. The config drive pattern – attach a minor image alongside the installation medium and modify nothing else. `make-config-drive` within this repository produces one.
3. `autoinstall.kdl` adjacent to the installer. In an ISO it resides at `/root/autoinstall.kdl`; in a simulated run initiated from a checkout it is the file situated next to `main.raku`.

## The format

KDL, the same language as the rest of the Ditana configuration, with two blocks – one for the settings, one for the account password:

```kdl
settings {
    user-name "operator"
    install-disk "vda"
    profile-server #true
    encrypt-root-partition #false
}
```

Each node assigns a setting and contains exactly one value. Two values constitute an error, and so does a setting that does not exist – validated against the settings the active installer actually loaded, not against a schema stored elsewhere. The configuration is retrieved at runtime, so the active installer is the sole authority over which settings exist, and it may reply with "no such setting" instead of silently overlooking a typo. A block that is neither `settings` nor `passwords` is prohibited for the same reason.

## What you have to answer, and what you do not

**What the file does not name retains the value the installer would have provided** – the default from `ditana-config`, or what was detected for this machine. That is not a guess: it is the answer an interactive dialog arrives pre-selected with, and overriding a detected value would mean choosing something that does not fit the hardware. A file therefore remains brief, and endures `ditana-config` gaining a new option.

**Anything lacking that value halts execution.** There are two types, and they differ in their point of termination:

- A question with nothing behind it. The user name is blank until someone inputs one, so a file that does not name `user-name` halts before any writing occurs, naming the setting.
- A question the installer cannot resolve at all: which disk to erase, whether to overwrite an EFI partition another system boots from, the passphrase for an encrypted root. These reach their dialog, and the dialog gate stops the run and names the box.

There is intentionally no forgiving mode that completes the gaps. A value from the configuration is an answer, a missing value is not, and no third case has ever been found.

### A radiolist is one choice

Options such as the user profile are one choice spread over several boolean settings, and the dialog unchecks the others when one is checked. An answer file that touches a radiolist owns it: the members it does not name go false. Naming two of them as true, or unsetting the only true one without naming another, stops the run – there is no way to tell which one was meant.

## Passwords

The password for the user account is requested by a dialog within the chroot, which the installer’s own gate cannot access. An unattended run would stall there indefinitely, with the whole system already in place. So the answer file carries it, in a block of its own:

```kdl
passwords {
    user "$6$..."
}
```

Only hashes are accepted, and a plaintext password is refused with the command that produces one. This is not merely precaution: an answer file for a hosting provider resides on a provisioning server and is read by every entity that provisions a machine, so a readable password in one is a password that has already been exposed. Generate a hash using `openssl passwd -6` or `mkpasswd -m yescrypt`.

The only account is `user`, which is whichever name `user-name` gives. Root has no password on Ditana and cannot acquire one here.

An answer file lacking a `passwords` block proceeds unchallenged, since an interactive installation contains none either. The run then stops in the chroot, saying which block is missing.

## A complete example

[`examples/autoinstall-server.kdl`](../examples/autoinstall-server.kdl) sets up a server without a desktop and requests nothing:

```kdl
settings {
    user-name "operator"
    install-disk "vda"
    bootloader-partition "new"
    profile-server #true
    timezone "Europe/Zurich"
    locale "en_US"
    keymap-layout "us"
    keymap-variant ""
    encrypt-root-partition #false
}

passwords {
    user "$6$..."
}
```

Nine settings and one password hash, and each one of them serves a purpose:

| Setting | Why it cannot be left out |
|---|---|
| `user-name` | Empty until someone inputs one. |
| `install-disk` | No disk may be wiped by assumption. The name is validated against the disks this device possesses. |
| `bootloader-partition` | `new` creates a fresh EFI partition on `install-disk`. Omit it on a machine that already boots something – then the installer halts and queries, rather than producing another unbootable system. |
| `profile-server` | The profile that installs no desktop environment. Naming it unsets the other four. |
| `timezone`, `locale`, `keymap-layout`, `keymap-variant` | The installer derives these from the network address, which is the incorrect origin for a machine in a data centre. |
| `encrypt-root-partition` | Without a passphrase from some source, an encrypted root cannot be configured automatically. |

Every value is validated against what the machine provides: a time zone against `timedatectl list-timezones`, a locale against `/etc/locale.gen`, a layout against `localectl list-x11-keymap-layouts`, a disk against the disks that are present. A misspelt one halts the run and displays what would have been valid.

## Trying it out

The fastest loop requires neither an ISO nor a virtual machine. The installer operates in simulation mode as a regular user – no partitioning, no `pacstrap`, no chroot – and reads `autoinstall.kdl` from the directory it is executed in:

```bash
cp examples/autoinstall-server.kdl airootfs/root/autoinstall.kdl
# edit install-disk to a disk this machine actually has
cd airootfs/root && ./main.raku
```

It returns 0 when the file carries the installation through, and otherwise terminates with the name of whatever it still wanted to ask. The log is `/tmp/install_ditana.log`.

For a genuine setup in QEMU, create a config drive and connect it as a second disk:

```bash
./make-config-drive examples/autoinstall-server.kdl ditana-auto.img
qemu-system-x86_64 -enable-kvm -m 4G \
    -drive file=ditana-test.qcow2,format=qcow2 \
    -drive file=ditana-auto.img,format=raw \
    -cdrom out/Ditana-*-x86_64.iso
```

## Why an answer file and not a script

The process might have been a script triggering keystrokes. It is an answer file due to the second function it performs: enabling automated Ditana deployments at a hosting provider. This requirement shapes every aspect of the architecture – the file must be accessible from the kernel command line to endure PXE, and the installer must be able to reject a typo rather than act on it. The nightly test deployment and a provisioning system represent the same mechanism, which is the sole means by which the first one verifies what the second one does.

## What is not covered yet

- An encrypted root. `encrypt-root-partition #true` reaches a passphrase box and stops there. Unlike the account password, a LUKS passphrase cannot be a hash -- the disk needs the passphrase itself -- so the same answer is not available, and no other one has been settled on.
- A post-installation hook a provider could hand over to. The block does not exist; naming it is rejected rather than ignored.

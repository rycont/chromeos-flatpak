# Flatpak on ChromeOS (kukui / ARM64)

This repository is an EAPI 7 Portage overlay for installing Flatpak directly
into a ChromeOS `dev_install` sysroot. It targets the ChromeOS host itself and
does not require Crostini, the Linux VM, or another container.

The validated target is `kukui` on ARM64. ChromeOS's package repository stays
the base repository; this overlay adds only packages, build fixes, and the
small compatible eclass set needed by Flatpak. It does not require connecting
a general Gentoo package repository.

## Current scope

The current stable profile provides:

- Flatpak 1.16.6
- OSTree 2025.7 with GPG verification
- AppStream 1.0.6 metadata support
- Bubblewrap 0.11.2
- xdg-dbus-proxy 0.1.7
- FUSE 3 mounting support

The validated configuration is intentionally user-scope oriented. Flatpak's
system helper, polkit, and systemd integration are not enabled. Therefore the
base supported workflow is:

```sh
flatpak --user remote-add --if-not-exists \
  flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak --user install flathub APP_ID
flatpak --user run APP_ID
```

The installer creates `/usr/local/etc/profile` so new host shells include
`/usr/local/bin`, `/usr/local/share`, and the target system installation at
`/usr/local/var/lib/flatpak`. For a system-scope remote or installation, run
the Flatpak command as root (the system repository is root-owned):

```sh
sudo -n flatpak --system remote-add --if-not-exists \
  flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo -n flatpak --system install flathub APP_ID
```

The base installation also includes the core `xdg-desktop-portal` service and
the small PipeWire client ABI it needs. It uses D-Bus activation and does not
enable systemd. This is the portal dispatcher and document portal; it does not
provide a ChromeOS-native Files picker by itself.

On the validated host, D-Bus successfully auto-activates
`org.freedesktop.portal.Desktop`, `org.freedesktop.portal.Documents`, and
`org.freedesktop.impl.portal.PermissionStore`. The expected optional
RealtimeKit warning remains because ChromeOS does not provide RealtimeKit.

An optional GTK desktop-portal ebuild is included, but it is not part of the
base installation. A clean `kukui` developer sysroot does not provide the
GTK package stack needed by that backend, so it is outside the supported
one-command path. If a compatible GTK stack is supplied separately, copy
`config/package.use/flatpak-chromeos-portal` and emerge
`sys-apps/xdg-desktop-portal-gtk`. It provides its own GTK dialogs; it does
not expose ChromeOS's native Files picker or Ash permission UI.

The portal package uses D-Bus activation and does not enable systemd. The
overlay's PipeWire package supplies the client library needed to build the
portal; it does not start a PipeWire daemon or replace ChromeOS's CRAS audio
stack. A user D-Bus session and a graphical environment are still required.

The Flatpak package itself may also install its internal `flatpak-portal`; that
is different from `xdg-desktop-portal` and a desktop-specific backend.

## One-command installation

On a Chromebook with an empty `/usr/local`, the complete installation can be
started with one command:

```sh
curl -fsSL https://raw.githubusercontent.com/rycont/chromeos-flatpak/main/install.sh | bash
```

The script takes no arguments. It requires passwordless `sudo`, runs
`dev_install` for the `kukui` developer sysroot, installs Flatpak and the core
desktop portal, and performs basic file checks. It resolves the latest `main`
commit through GitHub's public API with `curl`; the target Chromebook does not
need the `gh` CLI. For safety, it refuses to run when
`/usr/local` already contains anything; remove the existing developer sysroot
with `sudo dev_install --uninstall` and rerun it if necessary. It never empties
an existing `/usr/local` itself.

The pinned build fixes the ChromeOS developer sysroot's missing target-prefix
metadata and old Portage environment propagation. It does not add the general
Gentoo repository, and it does not overwrite the immutable ChromeOS root.

If the command is launched from a controlling PC with an authenticated `gh`,
resolve the current `main` SHA there and stream the exact revision to the
Chromebook over SSH. Replace the SSH key and target with your own values:

```sh
ref="$(gh api repos/rycont/chromeos-flatpak/commits/main --jq .sha)" && \
curl -fsSL "https://raw.githubusercontent.com/rycont/chromeos-flatpak/${ref}/install.sh" | \
ssh -T -i /path/to/key chronos@chromebook \
  "CHROMEOS_FLATPAK_REV=${ref} /bin/bash --noprofile --norc -s"
```

The `CHROMEOS_FLATPAK_REV` value prevents `main` moving between the API lookup
and the archive download. The Chromebook itself only needs the tools used by
`install.sh`; it does not need the `gh` CLI.

## Portage configuration

For manual or incremental installation, clone this repository to a persistent
path on the Chromebook and install the two example configuration files. The
overlay includes its compatible eclasses, so a separate Gentoo repository is
not needed. If you use another path, adjust `location` in
`config/repos.conf/flatpak-chromeos.conf` first:

```sh
install -d /usr/local/portage
git clone --depth=1 https://github.com/rycont/chromeos-flatpak.git \
  /usr/local/portage/flatpak-chromeos
install -d /usr/local/etc/portage/repos.conf \
  /usr/local/etc/portage/package.use \
  /usr/local/etc/portage/package.accept_keywords
cp /usr/local/portage/flatpak-chromeos/config/repos.conf/flatpak-chromeos.conf \
  /usr/local/etc/portage/repos.conf/
cp /usr/local/portage/flatpak-chromeos/config/package.use/flatpak-chromeos \
  /usr/local/etc/portage/package.use/
cp /usr/local/portage/flatpak-chromeos/config/package.accept_keywords/flatpak-chromeos \
  /usr/local/etc/portage/package.accept_keywords/
```

Then, from the ChromeOS host shell:

```sh
source /etc/profile
export PORTAGE_CONFIGROOT=/usr/local
export ROOT=/usr/local
export PORTDIR_OVERLAY=/usr/local/portage/flatpak-chromeos
export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib
export PORTAGE_BINHOST="https://commondatastorage.googleapis.com/chromeos-dev-installer/board/kukui/16765.41.0/packages https://commondatastorage.googleapis.com/chromeos-prebuilt/board/arm64-generic/postsubmit-R156-16821.0.0-87474-8670646292013436097/packages"
/usr/local/bin/emerge --ignore-default-opts \
  --config-root=/usr/local --root=/usr/local \
  --usepkg --getbinpkg --verbose \
  sys-apps/flatpak sys-apps/xdg-desktop-portal
```

The board's binary repository can satisfy unchanged ChromeOS dependencies;
overlay packages are built locally. After installation, start a new shell or
run `source /etc/profile`, then verify with `flatpak --version`.

## SDK validation

From a ChromiumOS checkout, register the overlay in the `kukui` target
sysroot and run:

```sh
emerge-kukui --usepkg --getbinpkg --verbose sys-apps/flatpak
emerge-kukui --ignore-default-opts --pretend --verbose --tree \
  --update sys-apps/flatpak
```

The second command should report zero packages after installation. ARM64
command-line smoke tests can be run in the SDK with `qemu-aarch64 -L`.

## Limitations

ChromeOS does not provide a conventional Linux desktop session to host-side
applications. Installing this overlay does not make ChromeOS's native Files
picker or Ash permission UI available to Flatpak applications. A complete
portal setup needs a user D-Bus session and a compatible backend such as GTK;
that backend will provide its own dialogs unless a ChromeOS-specific bridge is
implemented.

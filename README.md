# Flatpak on ChromeOS (kukui / ARM64)

This repository is an EAPI 7 Portage overlay for installing Flatpak directly
into a ChromeOS `dev_install` sysroot. It targets the ChromeOS host itself and
does not require Crostini, the Linux VM, or another container.

The validated target is `kukui` on ARM64. ChromeOS's package repository stays
the base repository; this overlay adds only packages and build fixes that are
needed by Flatpak. It is not a replacement for the Gentoo repository.

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

An optional GTK desktop-portal profile is included, but it is not part of the
base installation. It provides portal dialogs through GTK; it does not expose
ChromeOS's native Files picker or Ash permission UI. To install it, copy the
additional USE configuration and emerge the backend:

```sh
cp /usr/local/portage/flatpak-chromeos/config/package.use/flatpak-chromeos-portal \
  /usr/local/etc/portage/package.use/
/usr/local/bin/emerge --ignore-default-opts \
  --config-root=/usr/local --root=/usr/local \
  --usepkg --getbinpkg --verbose \
  sys-apps/xdg-desktop-portal-gtk
```

The portal package uses D-Bus activation and does not enable systemd. The
overlay's PipeWire package supplies the client library needed to build the
portal; it does not start a PipeWire daemon or replace ChromeOS's CRAS audio
stack. A user D-Bus session and a graphical environment are still required.

The Flatpak package itself may also install its internal `flatpak-portal`; that
is different from `xdg-desktop-portal` and a desktop-specific backend.

## Portage configuration

Clone this repository to a persistent path on the Chromebook and install the
two example configuration files. If you use another path, adjust `location`
in `config/repos.conf/flatpak-chromeos.conf` first:

```sh
install -d /usr/local/portage
git clone --depth=1 https://github.com/rycont/chromeos-flatpak.git \
  /usr/local/portage/flatpak-chromeos
install -d /usr/local/etc/portage/repos.conf /usr/local/etc/portage/package.use
cp /usr/local/portage/flatpak-chromeos/config/repos.conf/flatpak-chromeos.conf \
  /usr/local/etc/portage/repos.conf/
cp /usr/local/portage/flatpak-chromeos/config/package.use/flatpak-chromeos \
  /usr/local/etc/portage/package.use/
```

Then, from the ChromeOS host shell:

```sh
source /etc/profile
export PORTAGE_CONFIGROOT=/usr/local
export ROOT=/usr/local
export PORTDIR_OVERLAY=/usr/local/portage/flatpak-chromeos
export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib
/usr/local/bin/emerge --ignore-default-opts \
  --config-root=/usr/local --root=/usr/local \
  --usepkg --getbinpkg --verbose sys-apps/flatpak
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

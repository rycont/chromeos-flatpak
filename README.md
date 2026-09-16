# Flatpak on ChromeOS

Flatpak, directly on the ChromeOS host. No Crostini, Linux VM, or extra
container.

Currently tested on `kukui` / ARM64 / ChromeOS `16765.41.0` (R152).

## Install

On a Chromebook with an empty `/usr/local`:

```sh
curl -fsSL https://raw.githubusercontent.com/rycont/chromeos-flatpak/main/install.sh | bash
```

Open a new host shell after installation.

## Use

```sh
source /usr/local/etc/profile
flatpak --user remote-add --if-not-exists \
  flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak --user install flathub APP_ID
flatpak --user run APP_ID
```

For example:

```sh
# Anki
flatpak --user run net.ankiweb.Anki

# VS Code — try this first
flatpak --user run com.visualstudio.code
```

If VS Code crashes, see the optional [Sommelier fallback](docs/how-it-works.md).

The installer is pinned to the tested `kukui` R152 target. For implementation
and build details, see [`docs/how-it-works.md`](docs/how-it-works.md).

## App drawer icons

After installing a Flatpak app, pass its exported desktop file:

```sh
source /usr/local/etc/profile
chromeos-flatpak-launcher \
  "$(flatpak --user info --show-location net.ankiweb.Anki)/export/share/applications/net.ankiweb.Anki.desktop"
```

In the Chrome tab, choose **Install page as app**. The installed app-drawer
icon launches that desktop file immediately.

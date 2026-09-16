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

## If VS Code crashes

Most applications should use the normal command above. If an application
crashes ChromeOS, shows a broken window, or reports a Wayland error, try the
optional Sommelier fallback.

<details>
<summary>VS Code fallback used on the test Chromebook</summary>

Download the debug-enabled ARM64 Sommelier binary from the matching [release](https://github.com/rycont/chromeos-flatpak/releases/tag/r152-kukui-16765.41.0), then run this in one host shell:

```sh
curl -fL \
  https://github.com/rycont/chromeos-flatpak/releases/download/r152-kukui-16765.41.0/sommelier-kukui-r152-arm64 \
  -o /tmp/sommelier
sudo install -m 0755 /tmp/sommelier /usr/local/bin/sommelier

export XDG_RUNTIME_DIR=/run/chrome
sommelier --parent \
  --socket=wayland-sommelier-vscode \
  --display=/run/chrome/wayland-0 \
  --scale=1 \
  --noop-driver \
  --no-support-damage-buffer \
  --no-client-scaling-protocols
```

Leave that shell running. In a second host shell:

```sh
flatpak --user run \
  --socket=wayland \
  --filesystem=/run/chrome \
  --env=XDG_RUNTIME_DIR=/run/chrome \
  --env=WAYLAND_DISPLAY=wayland-sommelier-vscode \
  --env=GDK_BACKEND=wayland \
  --env=ELECTRON_OZONE_PLATFORM_HINT=wayland \
  --env=GTK_A11Y=none \
  --env=LIBGL_ALWAYS_SOFTWARE=1 \
  --no-documents-portal \
  --command=/app/bin/zypak-wrapper.sh \
  com.visualstudio.code \
  /app/extra/vscode/code \
  --no-sandbox --disable-gpu --disable-gpu-compositing \
  --disable-dev-shm-usage --ozone-platform=wayland \
  --enable-features=UseOzonePlatform --new-window
```

</details>

## Notes

- The installer is pinned to the tested `kukui` R152 target and refuses other
  ChromeOS versions.
- Sommelier is optional and is not installed automatically.
- The release Sommelier binary intentionally includes debug information for
  continued troubleshooting.
- The installer does not empty an existing `/usr/local`; remove an old
  developer sysroot with `sudo dev_install --uninstall` first if needed.

For the design, build provenance, and patch details, see
[`docs/how-it-works.md`](docs/how-it-works.md).

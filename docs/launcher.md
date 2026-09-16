# App drawer launcher

`chromeos-flatpak-launcher` is a small host-side daemon plus one local PWA
page. It does not install a Linux desktop environment or another container.

Pass it an exported `.desktop` file:

```sh
chromeos-flatpak-launcher \
  "$(flatpak --user info --show-location net.ankiweb.Anki)/export/share/applications/net.ankiweb.Anki.desktop"
```

The daemon listens on `127.0.0.1:39393`. It reads `Name`, `Icon`, and `Exec`
from the desktop file and uses them for the page, PWA manifest, and launch.
The page has exactly two behaviours:

- in a normal Chrome tab, show the Chrome **Install page as app** instruction;
- in an installed PWA, POST the same `desktop` query parameter to `/launch`.

`Exec` is parsed into arguments and started without a shell. File/URL
placeholders are ignored because this launcher does not pass files.

## Install the PWA

Run the command once per app. When Chrome opens the page in a normal tab,
choose **Install page as app**. Each installed PWA keeps its desktop-file path
in its start URL and launches that app when opened from the app drawer.

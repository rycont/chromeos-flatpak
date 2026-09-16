# How it works

## Normal launch

The default path is intentionally boring:

```sh
flatpak --user run APP_ID
```

Wayland-aware applications that work with the ChromeOS host compositor should
use this path. Anki worked this way on the test Chromebook.

The installer does not modify every application's Flatpak metadata and does
not force Sommelier into the runtime. This keeps ordinary applications on the
smallest and most predictable path.

## Sommelier fallback

Some applications, notably the tested Electron build of VS Code, can exercise
Wayland protocols that caused the ChromeOS host compositor to terminate when
the application connected directly. Sommelier sits between the application
and `/run/chrome/wayland-0` and provides a compatibility layer.

The tested setup uses a Sommelier parent in one host shell and points the
Flatpak application at its socket from another host shell:

```sh
export XDG_RUNTIME_DIR=/run/chrome
sommelier --parent \
  --socket=wayland-sommelier-vscode \
  --display=/run/chrome/wayland-0 \
  --scale=1 \
  --noop-driver \
  --no-support-damage-buffer \
  --no-client-scaling-protocols
```

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

`--socket=wayland` by itself only grants Flatpak's Wayland socket access; it
does not turn ChromeOS's `/run/chrome/wayland-0` into a compatible compositor
endpoint. Flatpak filesystem permissions are therefore needed for this
fallback. They should be used only for applications that need the fallback.

## Sommelier release

The optional release asset is named
`sommelier-kukui-r152-arm64`. It is:

- ARM64/aarch64 only;
- built for the tested `kukui` ChromeOS R152 / `16765.41.0` environment;
- dynamically linked against the ChromeOS userspace libraries;
- intentionally not stripped, so its debug information remains available for
  continued investigation.

The matching `.sha256` asset is published beside it. This binary is separate
from the Flatpak runtime bundle because Sommelier is a host display fallback,
not a dependency required by Flatpak itself.

## Patch provenance

The binary was built from the ChromiumOS `platform2/vm_tools/sommelier` source
at base commit:

```text
f095fe170b13ce5aca637879e1db084be9efdfdf
```

The local patch in
[`sommelier/no-client-scaling-protocols.patch`](../sommelier/no-client-scaling-protocols.patch)
adds `--no-client-scaling-protocols` and forwards it in parent mode. It also
forwards the compatibility options used by the test. The patch prevents
Sommelier from advertising the client-side viewporter and fractional-scale
protocols that triggered the tested VS Code/ChromeOS failure.

## Rebuilding

Use a ChromiumOS ARM64 sysroot containing the Sommelier dependencies, then
apply the patch and build with Meson:

```sh
git -C /path/to/platform2 apply \
  /path/to/chromeos-flatpak/sommelier/no-client-scaling-protocols.patch

meson setup /tmp/sommelier-build \
  /path/to/platform2/vm_tools/sommelier \
  --cross-file /path/to/arm64-cross.ini \
  -Dwith_tests=false \
  -Dgamepad=false \
  -Dtracing=false \
  -Dquirks=false \
  -Dlog_level=0
ninja -C /tmp/sommelier-build
```

The exact cross file is board/sysroot-specific. The release binary was built
with Clang targeting `aarch64-linux-gnu`, LLD, and the ARM64 ChromeOS sysroot.
The unstripped build output is suitable for debugging; keep it if investigating
a new compositor failure.

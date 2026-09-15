# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

# Metadata shim for the GLib already shipped by the pinned ChromeOS image.
# The installer uses the matching ChromeOS prebuilt package; never compile an
# empty replacement if that binary is unavailable.
DESCRIPTION="ChromeOS GLib 2.76 compatibility metadata"
HOMEPAGE="https://chromium.googlesource.com/chromiumos/overlays/chromiumos-overlay/"
LICENSE="LGPL-2.1+"
SLOT="2"
KEYWORDS="arm64"
IUSE="cros_host dbus debug doc gtk-doc mime selinux static-libs sysprof systemtap test utils xattr"

src_unpack() {
	die "This ChromeOS compatibility package requires the pinned GLib binary"
}

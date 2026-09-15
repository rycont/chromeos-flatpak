# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

# Target builds do not run ChromiumOS platform2 tests; avoid their host runner deps.
PLATFORM2_TEST_DEPS=test-only
inherit meson systemd

MY_PV="${PV//_pre*}"
MY_P="${PN}-${MY_PV}"

DESCRIPTION="Backend implementation for xdg-desktop-portal using GTK+"
HOMEPAGE="https://flatpak.org/ https://github.com/flatpak/xdg-desktop-portal-gtk"
SRC_URI="https://github.com/flatpak/${PN}/releases/download/${MY_PV}/${MY_P}.tar.xz"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="arm64"
IUSE="wayland X"

BDEPEND="
	dev-util/gdbus-codegen
	sys-devel/gettext
	virtual/pkgconfig
"

DEPEND="
	dev-libs/glib:2
	gnome-base/gsettings-desktop-schemas
	media-libs/fontconfig
	sys-apps/dbus
	>=sys-apps/xdg-desktop-portal-1.14.0
	x11-libs/cairo[X?]
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3[wayland?,X?]
"

RDEPEND="${DEPEND}"
S="${WORKDIR}/${MY_P}"

src_configure() {
	local emesonargs=(
		-Dsystemd-user-unit-dir="$(systemd_get_userunitdir)"
		-Dappchooser=enabled
		-Dsettings=enabled
		-Dlockdown=disabled
		-Dwallpaper=disabled
	)

	meson_src_configure
}

src_install() {
	meson_src_install

	# Activation is provided by the D-Bus service. ChromeOS has no systemd
	# user manager to consume the optional unit file.
	rm -rf "${ED}/etc/systemd" "${ED}/usr/lib/systemd" || die
}

# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

# Target builds do not run ChromiumOS platform2 tests; avoid their host runner deps.
PLATFORM2_TEST_DEPS=test-only
inherit gnome.org gnome2-utils meson xdg

# The ChromeOS Portage profile does not define Gentoo's gnome mirror alias.
SRC_URI="https://download.gnome.org/sources/gsettings-desktop-schemas/48/gsettings-desktop-schemas-48.0.tar.xz"

DESCRIPTION="Collection of GSettings schemas for GNOME desktop"
HOMEPAGE="https://gitlab.gnome.org/GNOME/gsettings-desktop-schemas"

LICENSE="LGPL-2.1+"
SLOT="0"
KEYWORDS="arm64"
IUSE="introspection"

BDEPEND="
	introspection? ( >=dev-libs/gobject-introspection-1.82.0-r2:= )
	dev-util/glib-utils
	virtual/pkgconfig
"

PATCHES=(
	# Use generic sans and monospace aliases
	"${FILESDIR}"/48.0-default-fonts.patch
)

src_prepare() {
	# The ChromeOS dev root does not ship msgfmt; translations are optional
	# for this host installation.
	sed -i "/subdir('po')/d; /subdir('po\\/')/d" meson.build || die
	default
}

src_configure() {
	local emesonargs=(
		$(meson_use introspection)
	)
	meson_src_configure
}

pkg_postinst() {
	xdg_pkg_postinst
	gnome2_schemas_update
}

pkg_postrm() {
	xdg_pkg_postrm
	gnome2_schemas_update
}

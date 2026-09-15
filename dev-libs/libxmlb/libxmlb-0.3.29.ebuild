# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

PYTHON_COMPAT=( python3_11 )
inherit meson python-any-r1

DESCRIPTION="Library to help create and query binary XML blobs"
HOMEPAGE="https://github.com/hughsie/libxmlb"
SRC_URI="
	https://github.com/hughsie/libxmlb/releases/download/${PV}/${P}.tar.xz
"

LICENSE="LGPL-2.1+"
SLOT="0/2" # libxmlb.so version
KEYWORDS="arm64"
IUSE="doc introspection +lzma stemmer test +zstd"
RESTRICT="!test? ( test )"

RDEPEND="
	>=dev-libs/glib-2.56.0:2
	lzma? ( app-arch/xz-utils )
	stemmer? ( dev-libs/snowball-stemmer:= )
	zstd? ( app-arch/zstd:= )
"
DEPEND="
	${RDEPEND}
	doc? ( dev-util/gtk-doc )
	introspection? ( >=dev-libs/gobject-introspection-1.82.0-r2 )
"
BDEPEND="
	${PYTHON_DEPS}
	virtual/pkgconfig
	introspection? (
		$(python_gen_any_dep 'dev-python/setuptools[${PYTHON_USEDEP}]')
	)
"
DOCS=( NEWS README.md )

python_check_deps() {
	if use introspection ; then
		python_has_version -b "dev-python/setuptools[${PYTHON_USEDEP}]"
	else
		return 0
	fi
}

src_configure() {
	local emesonargs=(
		$(meson_feature lzma)
		$(meson_feature zstd)
		$(meson_use doc gtkdoc)
		$(meson_use introspection)
		$(meson_use stemmer)
		$(meson_use test tests)
	)
	meson_src_configure
}

src_install() {
	meson_src_install

	if use test; then
		# Preventing tests from being installed in the first place is a moving target,
		# just axe them all afterwards.
		rm -r "${ED}"/usr/{libexec,share}/installed-tests || die
	fi
}

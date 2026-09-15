# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

PYTHON_COMPAT=( python3_11 )

inherit python-any-r1

DESCRIPTION="GDBus code and documentation generator"
HOMEPAGE="https://www.gtk.org/"
SRC_URI="https://download.gnome.org/sources/glib/2.76/glib-${PV}.tar.xz"

LICENSE="LGPL-2+"
SLOT="0"
KEYWORDS="arm64"

RDEPEND="${PYTHON_DEPS}"
DEPEND="${RDEPEND}"

S="${WORKDIR}/glib-${PV}/gio/gdbus-2.0/codegen"

src_prepare() {
	cd "${WORKDIR}/glib-${PV}" || die
	eapply "${FILESDIR}/${PN}-2.56.1-sitedir.patch"
	cd "${S}" || die

	sed -e 's:@PYTHON@:python:' gdbus-codegen.in > gdbus-codegen || die
	sed -e "s:@VERSION@:${PV}:" \
		-e "s:@MAJOR_VERSION@:$(ver_cut 1):" \
		-e "s:@MINOR_VERSION@:$(ver_cut 2):" \
		config.py.in > config.py || die
	cp "${FILESDIR}/setup.py-2.32.4" setup.py || die
	sed -e "s/@PV@/${PV}/" -i setup.py || die
	chmod 0755 gdbus-codegen || die

	eapply_user
}

src_compile() {
	"${PYTHON}" setup.py build || die
}

src_install() {
	"${PYTHON}" setup.py install --skip-build --root="${D}" \
		--prefix=/usr --optimize=1 || die
}

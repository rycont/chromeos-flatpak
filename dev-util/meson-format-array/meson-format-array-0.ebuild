# Copyright 2020-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

PYTHON_COMPAT=( python3_11 )
inherit python-any-r1

DESCRIPTION="Format shell expressions into a meson array"
HOMEPAGE="https://wiki.gentoo.org/wiki/No_homepage"
S="${WORKDIR}"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="arm64"

RDEPEND="${PYTHON_DEPS}"

src_install() {
	newbin "${FILESDIR}/meson-format-array.py" meson-format-array
}

# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="GNU macro processor"
HOMEPAGE="https://www.gnu.org/software/m4/m4.html"
SRC_URI="https://ftp.gnu.org/gnu/m4/${P}.tar.xz"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="arm64"

# This EAPI 7 recipe is intentionally minimal: the target only needs m4 as a
# build tool for the older binary metadata's flex/autoconf dependencies.
src_configure() {
	econf --disable-nls --enable-changeword
}

src_install() {
	default
}

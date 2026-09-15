# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="High level interface to Linux seccomp filter"
HOMEPAGE="https://github.com/seccomp/libseccomp"
SRC_URI="https://github.com/seccomp/libseccomp/releases/download/v${PV}/${P}.tar.gz"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="arm64"
IUSE="static-libs test"
RESTRICT="!test? ( test )"

src_configure() {
	econf \
		$(use_enable static-libs static) \
		--disable-python
}

src_compile() {
	emake
}

src_test() {
	emake check
}

src_install() {
	emake DESTDIR="${D}" install
	docinto /usr/share/doc/${PF}
	dodoc AUTHORS ChangeLog.txt README.md || die
}

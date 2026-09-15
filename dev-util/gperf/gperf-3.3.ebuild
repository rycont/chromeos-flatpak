# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="A perfect hash function generator"
HOMEPAGE="https://www.gnu.org/software/gperf/"
SRC_URI="mirror://gnu/gperf/${P}.tar.gz"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="arm64"

src_prepare() {
	default

	sed -i \
		-e "/^CPPFLAGS /s:=:+=:" \
		*/Makefile.in || die #444078
}

src_configure() {
	econf --cache-file="${S}"/config.cache
}

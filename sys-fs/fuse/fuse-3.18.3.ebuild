# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

# Target builds do not run ChromiumOS platform2 tests; avoid their host runner deps.
PLATFORM2_TEST_DEPS=test-only
inherit meson toolchain-funcs udev

DESCRIPTION="An interface for filesystems implemented in userspace"
HOMEPAGE="https://github.com/libfuse/libfuse"
SRC_URI="https://github.com/libfuse/libfuse/releases/download/${P}/${P}.tar.gz"

LICENSE="GPL-2 LGPL-2.1"
SLOT="3/4"
KEYWORDS="arm64"
IUSE="+suid systemtap"

RDEPEND=">=sys-fs/fuse-common-3.3.0-r1"
BDEPEND="virtual/pkgconfig"

DOCS=( AUTHORS ChangeLog.rst README.md doc/README.NFS doc/kernel.txt )

src_configure() {
	local emesonargs=(
		-Dexamples=false
		-Dtests=false
		$(meson_use systemtap enable-usdt)
		-Denable-io-uring=false
		-Duseroot=false
		-Dinitscriptdir=
		-Dudevrulesdir="${EPREFIX}$(get_udevdir)/rules.d"
	)
	meson_src_configure
}

src_install() {
	meson_src_install

	# Installed via fuse-common
	rm -rf "${ED}"{/etc,$(get_udevdir)} || die

	# useroot=false prevents the build system from doing this.
	use suid && fperms u+s /usr/bin/fusermount3

	# manually install man pages to respect compression
	rm -rf "${ED}"/usr/share/man || die
	doman doc/{fusermount3.1,mount.fuse3.8}
}

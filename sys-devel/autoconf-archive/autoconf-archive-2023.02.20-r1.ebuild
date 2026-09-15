# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="ChromeOS host compatibility metadata for Autoconf Archive"
HOMEPAGE="https://www.gnu.org/software/autoconf-archive/"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="arm64"

# There is intentionally no source archive for this compatibility package.
# Point Portage at the work directory so its phase wrapper can still run.
S="${WORKDIR}"

# The ChromeOS development image already provides a newer copy of the
# Autoconf Archive macros in /usr/share/aclocal.  The old ChromiumOS Portage
# tree nevertheless pulls this package into BROOT; installing its older
# archive would overwrite those host files.  This compatibility package
# records that the requirement is satisfied without installing anything.
src_install() {
	einfo "Using the Autoconf Archive macros supplied by the ChromeOS host"
}

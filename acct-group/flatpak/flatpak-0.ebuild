# Minimal ChromeOS-compatible account package for Flatpak.
EAPI=7

DESCRIPTION="System group for Flatpak"
LICENSE="GPL-2"
SLOT="0"
KEYWORDS="arm64"

S=${WORKDIR}

src_install() {
	insinto /usr/lib/sysusers.d
	newins - acct-group-flatpak.conf <<-EOF
	g flatpak 313
	EOF
}

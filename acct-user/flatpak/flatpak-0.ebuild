# Minimal ChromeOS-compatible account package for Flatpak.
EAPI=7

DESCRIPTION="System user for Flatpak"
LICENSE="GPL-2"
SLOT="0"
KEYWORDS="arm64"

S=${WORKDIR}

RDEPEND="acct-group/flatpak"

src_install() {
	insinto /usr/lib/sysusers.d
	newins - acct-user-flatpak.conf <<-EOF
	u flatpak 313 "Flatpak system user" /var/lib/flatpak /sbin/nologin
	EOF
}

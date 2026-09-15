# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7
# Target builds do not run ChromiumOS platform2 tests; avoid their host runner deps.
PLATFORM2_TEST_DEPS=test-only
inherit bash-completion-r1 gnome.org gnome2-utils meson systemd virtualx xdg

# The ChromeOS Portage profile does not define Gentoo's gnome mirror alias.
SRC_URI="https://download.gnome.org/sources/dconf/0.40/dconf-0.40.0.tar.xz"

DESCRIPTION="Simple low-level configuration system"
HOMEPAGE="https://wiki.gnome.org/Projects/dconf"

LICENSE="LGPL-2.1+"
SLOT="0"
KEYWORDS="arm64"
IUSE="gtk-doc"
RESTRICT="!test? ( test )" # IUSE=test comes from virtualx.eclass

RDEPEND="
	>=dev-libs/glib-2.44.0:2
	sys-apps/dbus
"
DEPEND="${RDEPEND}"
BDEPEND="
	dev-util/gdbus-codegen
	gtk-doc? ( >=dev-util/gtk-doc-1.15 )
	virtual/pkgconfig
"

PATCHES=(
	"${FILESDIR}"/0.40.0-bash-completion-dir.patch
	"${FILESDIR}"/0.32.0-drop-vapigen-dep.patch # .vapi/.deps are pregenerated, just install them without a vala dep
)

src_prepare() {
	# The ChromeOS dev root does not ship msgfmt; translations are optional
	# for this host installation.
	sed -i "/subdir('po')/d; /subdir('po\\/')/d" meson.build || die
	default
}

src_configure() {
	local emesonargs=(
		-Dbash_completion_dir="$(get_bashcompdir)"
		-Dman=false
		$(meson_use gtk-doc gtk_doc)
		-Dvapi=false
		-Dsystemduserunitdir=$(systemd_get_userunitdir)
	)
	meson_src_configure
}

src_install() {
	meson_src_install

	# D-Bus and user-service activation must use the ChromeOS developer
	# sysroot, whose runtime prefix is /usr/local.
	local service
	for service in "${ED}"/usr/share/dbus-1/services/*.service \
		"${ED}"/usr/lib/systemd/user/*.service; do
		[[ -f ${service} ]] || continue
		sed -i 's#Exec=/usr/libexec/#Exec=/usr/local/libexec/#g' "${service}" || die
	done

	# GSettings backend may be one of: memory, gconf, dconf
	# Only dconf is really considered functional by upstream
	# must have it enabled over gconf if both are installed
	# This snippet can't be removed until gconf package is
	# ensured to not install a /etc/env.d/50gconf and then
	# still consider the CONFIG_PROTECT_MASK bit.
	echo 'CONFIG_PROTECT_MASK="/etc/dconf"' >> 51dconf
	echo 'GSETTINGS_BACKEND="dconf"' >> 51dconf
	doenvd 51dconf
}

src_test() {
	virtx meson_src_test
}

pkg_postinst() {
	xdg_pkg_postinst
	gnome2_giomodule_cache_update

	# Kill existing dconf-service processes as recommended by upstream due to
	# possible changes in the dconf private dbus API.
	# dconf-service will be dbus-activated on next use.
	pids=$(pgrep -x dconf-service)
	if [[ $? == 0 ]]; then
		ebegin "Stopping dconf-service; it will automatically restart on demand"
		kill ${pids}
		eend $?
	fi
}

pkg_postrm() {
	xdg_pkg_postrm
	gnome2_giomodule_cache_update
}

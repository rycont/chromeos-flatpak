# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

# Target builds do not run ChromiumOS platform2 tests; avoid their host runner deps.
PLATFORM2_TEST_DEPS=test-only
inherit meson systemd

# See the corresponding note in the PipeWire ebuild.  This is only used by
# the SDK's cross-build and is not used for a native ChromeOS emerge.
_meson_get_exe_wrapper() {
	echo /bin/true
}

DESCRIPTION="Desktop integration portal"
HOMEPAGE="https://flatpak.github.io/xdg-desktop-portal/ https://github.com/flatpak/xdg-desktop-portal"
SRC_URI="https://github.com/flatpak/${PN}/releases/download/${PV}/${P}.tar.xz"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="arm64"
IUSE="flatpak geolocation gstreamer seccomp systemd test udev"
REQUIRED_USE="flatpak? ( seccomp )"
RESTRICT="!test? ( test ) gstreamer? ( test )"

DEPEND="
	>=dev-libs/glib-2.72:2
	dev-libs/json-glib
	media-video/pipewire:=
	>=sys-fs/fuse-3.10.0:3=[suid]
	x11-libs/gdk-pixbuf:2
	geolocation? ( >=app-misc/geoclue-2.5.3:2.0 )
	gstreamer? (
		media-libs/gst-plugins-base:1.0
		sys-apps/bubblewrap
	)
	flatpak? ( sys-apps/flatpak )
	seccomp? ( sys-apps/bubblewrap )
	systemd? ( sys-apps/systemd )
	udev? ( dev-libs/libgudev )
"
RDEPEND="
	${DEPEND}
	sys-apps/dbus
"
BDEPEND="
	dev-util/gdbus-codegen
	virtual/pkgconfig
	test? (
		dev-util/umockdev
		media-libs/gstreamer
		media-libs/gst-plugins-good
	)
"

PATCHES=(
	"${FILESDIR}/${PN}-1.20.4-optional-gstreamer.patch"
)

src_prepare() {
	# The ChromeOS dev root does not ship msgfmt; translations are optional
	# for this host installation.
	sed -i "/subdir('po')/d; /subdir('po\\/')/d" meson.build || die
	default
}

src_configure() {
	local emesonargs=(
		-Ddbus-service-dir="${EPREFIX}/usr/share/dbus-1/services"
		-Dsystemd-user-unit-dir="$(systemd_get_userunitdir)"
		$(meson_feature flatpak flatpak-interfaces)
		$(meson_feature geolocation geoclue)
		$(meson_feature udev gudev)
		$(meson_feature seccomp sandboxed-image-validation)
		$(meson_feature gstreamer sandboxed-sound-validation)
		$(meson_feature systemd)
		-Ddocumentation=disabled
		-Ddatarootdir="${EPREFIX}/usr/share"
		-Dman-pages=disabled
		-Dinstalled-tests=false
		$(meson_feature test tests)
	)

	meson_src_configure
}

src_install() {
	meson_src_install

	insinto /usr/share/xdg-desktop-portal
	newins "${FILESDIR}/default-portals.conf" portals.conf

	# ChromeOS has no systemd user manager. The D-Bus service installed by
	# upstream is sufficient to activate the portal on a session bus.
	rm -rf "${ED}/etc/systemd" "${ED}/usr/lib/systemd" || die

	local service
	for service in "${ED}"/usr/share/dbus-1/services/*.service; do
		[[ -f ${service} ]] || continue
		sed -i 's#Exec=/usr/libexec/#Exec=/usr/local/libexec/#g' "${service}" || die
	done
}

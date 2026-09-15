# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

# Target builds do not run ChromiumOS platform2 tests; avoid their host runner deps.
PLATFORM2_TEST_DEPS=test-only
inherit meson

# The ChromiumOS SDK cross-build cannot execute ARM64 test binaries while
# Meson performs its compiler sanity check.  The installed package is used on
# a native ARM64 ChromeOS host, so a successful no-op wrapper is sufficient.
_meson_get_exe_wrapper() {
	echo /bin/true
}

DESCRIPTION="Multimedia processing graphs (minimal client library for ChromeOS portals)"
HOMEPAGE="https://pipewire.org/"
SRC_URI="https://gitlab.freedesktop.org/pipewire/pipewire/-/archive/${PV}/${P}.tar.bz2"

LICENSE="MIT LGPL-2.1+ GPL-2"
SLOT="0/0.4"
KEYWORDS="arm64"

BDEPEND="
	>=dev-build/meson-0.59
	virtual/pkgconfig
"

# This package deliberately builds the client ABI needed by
# xdg-desktop-portal. It does not start a daemon and does not replace CRAS.
RDEPEND=""
DEPEND="${RDEPEND}"

PATCHES=(
	"${FILESDIR}/${PN}-${PV}-no-spa-plugin-deps.patch"
)

src_configure() {
	local emesonargs=(
		-Ddocs=disabled
		-Dman=disabled
		-Dexamples=disabled
		-Dtests=disabled
		-Dinstalled_tests=disabled
		-Dgstreamer=disabled
		-Dgstreamer-device-provider=disabled
		-Dsystemd=disabled
		-Dlogind=disabled
		-Dsystemd-system-service=disabled
		-Dsystemd-user-service=disabled
		-Dselinux=disabled
		-Dpipewire-alsa=disabled
		-Dpipewire-jack=disabled
		-Dpipewire-v4l2=disabled
		-Dspa-plugins=disabled
		-Dalsa=disabled
		-Dbluez5=disabled
		-Dlibcamera=disabled
		-Dv4l2=disabled
		-Ddbus=disabled
		-Dcontrol=disabled
		-Daudiotestsrc=disabled
		-Dvideoconvert=disabled
		-Dvideotestsrc=disabled
		-Dvolume=disabled
		-Dvulkan=disabled
		-Dpw-cat=disabled
		-Dpw-cat-ffmpeg=disabled
		-Dudev=disabled
		-Dsdl2=disabled
		-Dsndfile=disabled
		-Dlibmysofa=disabled
		-Dlibpulse=disabled
		-Droc=disabled
		-Davahi=disabled
		-Decho-cancel-webrtc=disabled
		-Dlibusb=disabled
		-Dreadline=disabled
		-Dgsettings=disabled
		-Dcompress-offload=disabled
		-Dsession-managers=[]
		-Draop=disabled
		-Dlv2=disabled
		-Dflatpak=disabled
		-Dsupport=enabled
		-Djack=disabled
		-Debur128=disabled
		-Dopus=disabled
		-Dlibffado=disabled
		-Dlibcanberra=disabled
		-Dx11=disabled
		-Dx11-xfixes=disabled
	)

	meson_src_configure
}

src_install() {
	meson_src_install

	# Keep the ABI, headers, and pkg-config metadata; do not install a daemon,
	# service units, or auxiliary host tools into the ChromeOS profile.
	rm -rf "${ED}/etc" "${ED}/usr/bin" "${ED}/usr/sbin" \
		"${ED}/usr/libexec" "${ED}/usr/lib/pipewire-"* \
		"${ED}/usr/lib64/pipewire-"* "${ED}/usr/lib/alsa-lib" \
		"${ED}/usr/share" "${ED}/usr/lib/systemd" || die
}

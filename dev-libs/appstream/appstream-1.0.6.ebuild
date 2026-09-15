# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit meson xdg-utils

# The SDK has no ARM64 execution path for Meson's compiler sanity check.
# AppStream's tests and native-data generation are disabled below, so a
# successful no-op wrapper is sufficient for configuration.
_meson_get_exe_wrapper() {
	echo /bin/true
}

if [[ ${PV} == *9999* ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/ximion/${PN}"
else
	MY_PN="AppStream"
	SRC_URI="https://www.freedesktop.org/software/appstream/releases/${MY_PN}-${PV}.tar.xz"
	KEYWORDS="~alpha amd64 arm arm64 ~loong ppc ppc64 ~riscv x86"
	S="${WORKDIR}/${MY_PN}-${PV}"
fi

DESCRIPTION="Cross-distro effort for providing metadata for software in the Linux ecosystem"
HOMEPAGE="https://www.freedesktop.org/wiki/Distributions/AppStream/"

LICENSE="LGPL-2.1+ GPL-2+"
# check as_api_level
SLOT="0/5"
IUSE="apt compose doc +introspection qt6 systemd test"
RESTRICT="test" # bug 691962

RDEPEND="
	app-arch/zstd:=
	>=dev-libs/glib-2.62:2
	dev-libs/libxml2:2=
	>=dev-libs/libxmlb-0.3.14:=
	dev-libs/libyaml
	>=net-misc/curl-7.62
	compose? (
		dev-libs/glib:2
		dev-libs/libyaml
		gnome-base/librsvg:2
		media-libs/fontconfig:1.0
		media-libs/freetype:2
		x11-libs/cairo
		x11-libs/gdk-pixbuf:2
	)
	introspection? ( >=dev-libs/gobject-introspection-1.82.0-r2:= )
	qt6? ( dev-qt/qtbase:6 )
	systemd? ( sys-apps/systemd:= )
"
DEPEND="${RDEPEND}"
BDEPEND="
	dev-util/glib-utils
	dev-util/gperf
	>=sys-devel/gettext-0.19.8
	doc? (
		app-text/docbook-xsl-stylesheets
		app-text/docbook-xml-dtd:4.5
		dev-libs/libxslt
		dev-util/itstool
	)
	test? ( dev-qt/qttools:6[linguist] )
"

PATCHES=(
	"${FILESDIR}"/${PN}-1.0.0-disable-Werror-flags.patch # bug 733774
	"${FILESDIR}"/${P}-missing-fontconfig-include.patch # bug 977023
)

src_prepare() {
	default
	# The data/ subdirectory invokes a native appstreamcli during a
	# cross-build. ChromeOS builds the target library and CLI, but does not
	# provide a native AppStream executable in the SDK.
	sed -i "/^subdir('data\/')$/d" meson.build || die
	sed -e "/^as_doc_target_dir/s/appstream/${PF}/" -i docs/meson.build || die
	if ! use test; then
		sed -e "/^subdir.*tests/s/^/#DONT /" -i {,qt/}meson.build || die # bug 675944
	fi

}

src_configure() {
	xdg_environment_reset

	local emesonargs=(
		-Dapidocs=false
		-Ddocs=false
		-Dcompose=false
		-Dmaintainer=false
		-Dstatic-analysis=false
		# The stemming sub-build hardcodes /usr/include, which is the SDK host
		# include directory and cannot be used for a ChromeOS ARM64 target.
		-Dstemming=false
		-Dvapi=false
		-Dapt-support=$(usex apt true false)
		-Dcompose=$(usex compose true false)
		-Dinstall-docs=$(usex doc true false)
		-Dgir=$(usex introspection true false)
		-Dqt=$(usex qt6 true false)
		-Dsystemd=$(usex systemd true false)
	)

	meson_src_configure
}

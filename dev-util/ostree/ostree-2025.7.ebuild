# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit systemd tmpfiles

DESCRIPTION="Operating system and container binary deployment and upgrades"
HOMEPAGE="https://ostreedev.github.io/ostree/"
SRC_URI="
	https://github.com/ostreedev/ostree/releases/download/v${PV}/lib${P}.tar.xz
		-> ${P}.tar.xz
"
S="${WORKDIR}/lib${P}"

LICENSE="LGPL-2+"
SLOT="0"
KEYWORDS="arm64"
IUSE="archive +curl doc dracut flatpak-gpg gnutls grub +http2 introspection libmount selinux sodium ssl soup systemd zeroconf"
RESTRICT="test"
REQUIRED_USE="
	dracut? ( systemd )
	http2? ( curl )
"

RDEPEND="
	app-arch/xz-utils
	dev-libs/glib:2
	sys-fs/fuse:3=
	virtual/zlib:=
	archive? ( app-arch/libarchive:= )
	curl? ( net-misc/curl )
	dracut? ( sys-kernel/dracut )
	flatpak-gpg? (
		app-crypt/gpgme:=
		dev-libs/libgpg-error
	)
	grub? ( sys-boot/grub:2= )
	introspection? ( >=dev-libs/gobject-introspection-1.82.0-r2 )
	libmount? ( sys-apps/util-linux )
	selinux? ( sys-libs/libselinux )
	sodium? ( >=dev-libs/libsodium-1.0.14:= )
	soup? ( net-libs/libsoup:3.0 )
	ssl? (
		gnutls? ( net-libs/gnutls:= )
		!gnutls? (
			dev-libs/openssl:0=
		)
	)
	systemd? ( sys-apps/systemd:0= )
	zeroconf? ( net-dns/avahi[dbus] )
"
DEPEND="${RDEPEND}
	app-text/docbook-xml-dtd:4.2
	app-text/docbook-xsl-stylesheets
	doc? (
		dev-util/gtk-doc
		app-text/docbook-xml-dtd:4.3
	)
"
BDEPEND="
	dev-libs/libxslt
	dev-util/glib-utils
	sys-devel/flex
	sys-devel/bison
	virtual/pkgconfig
"

PATCHES=(
	"${FILESDIR}"/${PN}-2023.3-dont-force-clang-introspection.patch
	"${FILESDIR}"/${PN}-2024.8-Werror.patch
	"${FILESDIR}"/${PN}-2025.6-include-stdint-musl.patch
)

src_prepare() {
	default
	# The release archive already contains generated Automake files.
	touch aclocal.m4 Makefile.in configure config.h.in || die
}

src_configure() {
	# The ChromeOS dev root does not define CHOST although gcc is target-specific.
	export CHOST="${CHOST:-$(gcc -dumpmachine)}"
	# ChromiumOS gcc uses a sysroot libc; put its linker objects before host
	# /usr/lib64 while configuring this target package.
	export LDFLAGS="-L/usr/local/toolchain-arm64/lib/aarch64-linux-gnu ${LDFLAGS}"
	export LIBS="-lssl -lcrypto -lmount -lffi -lblkid -lgnutls -lnettle -lhogweed -lgmp -ltasn1 -lidn2 -lunistring -lzstd -lbrotlidec -lbrotlienc -lbrotlicommon -lnghttp2 -lresolv ${LIBS}"
	export LD_LIBRARY_PATH="/usr/lib64:${LD_LIBRARY_PATH}"
	export PKG_CONFIG_PATH="/usr/local/usr/lib64/pkgconfig:/usr/local/usr/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
	export PKG_CONFIG_LIBDIR="/usr/local/usr/lib64/pkgconfig:/usr/local/usr/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
	local pkg_config_wrapper="${T}/pkg-config-toolchain"
	cat > "${pkg_config_wrapper}" <<'EOF'
#!/bin/sh
case " $* " in
  *--libs*)
    printf "%s " "-L/usr/local/toolchain-arm64/lib/aarch64-linux-gnu"
    /usr/local/bin/pkgconf "$@" | /usr/bin/tr "\n" " "
    printf " -lpcre2-8\n"
    exit $?
    ;;
esac
exec /usr/local/bin/pkgconf "$@"
EOF
	chmod +x "${pkg_config_wrapper}" || die
	export PKG_CONFIG="${pkg_config_wrapper}"
	export OT_DEP_E2P_CFLAGS="-I/usr/local/toolchain-arm64/include"
	export OT_DEP_E2P_LIBS="-L/usr/local/toolchain-arm64/lib/aarch64-linux-gnu"
	# Needs Bison (bug #884289)
	unset YACC

	local econfargs=(
		--disable-man
		--enable-shared
		--with-grub2-mkconfig-path=grub-mkconfig
		--with-modern-grub
		$(use_with archive libarchive)
		$(use_with curl)
		$(use_with dracut dracut yesbutnoconf) #816867
		$(use_enable doc gtk-doc)
		$(usex introspection --enable-introspection={,} yes no)
		$(use_with flatpak-gpg gpgme)
		$(use_enable http2)
		$(use_with selinux )
		$(use_with soup soup3)
		--without-soup # libsoup:2.4
		$(use_with libmount)
		$(use ssl && usex gnutls --with-crypto=gnutls --with-crypto=openssl)
		$(use_with sodium ed25519-libsodium)
		$(use_with systemd libsystemd)
		$(use_with zeroconf avahi)
	)

	if use systemd; then
		econfargs+=( --with-systemdsystemunitdir="$(systemd_get_systemunitdir)" )
	fi

	unset ${!XDG_*} #657346 g-ir-scanner sandbox violation
	econf "${econfargs[@]}"
}

src_compile() {
	emake \
		LDFLAGS="-L/usr/local/toolchain-arm64/lib/aarch64-linux-gnu -L/usr/local/usr/lib64 -Wl,-rpath-link,/usr/lib64 -Wl,-rpath-link,/usr/local/usr/lib64" \
		LIBS="-lssl -lcrypto -lmount -lffi -lblkid -lgnutls -lnettle -lhogweed -lgmp -ltasn1 -lidn2 -lunistring -lzstd -lbrotlidec -lbrotlienc -lbrotlicommon -lnghttp2 -lresolv -lz"
}

src_install() {
	default
	dotmpfiles src/boot/ostree-tmpfiles.conf #901797
	find "${D}" -name '*.la' -type f -delete || die

	# pkg-config metadata otherwise points at the immutable host prefix. The
	# target runtime prefix of this overlay is /usr/local.
	local pc
	for pc in "${ED}"/usr/lib*/pkgconfig/ostree-1.pc; do
		[[ -f ${pc} ]] || continue
		sed -i 's#^prefix=/usr$#prefix=/usr/local/usr#' "${pc}" || die
	done
}

pkg_postinst() {
	tmpfiles_process ostree-tmpfiles.conf
}

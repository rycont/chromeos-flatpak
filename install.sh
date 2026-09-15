#!/bin/bash

set -euo pipefail

# The VT shell on ChromeOS has a deliberately minimal PATH. Include both
# regular and administrative host utilities used during the bootstrap.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/bin"

BINHOST="https://commondatastorage.googleapis.com/chromeos-dev-installer/board/kukui/16765.41.0/packages"
COMMON_BINHOST="https://commondatastorage.googleapis.com/chromeos-prebuilt/board/arm64-generic/postsubmit-R156-16821.0.0-87474-8670646292013436097/packages"
REPO_API="https://api.github.com/repos/rycont/chromeos-flatpak/commits/main"
OVERLAY="/usr/local/portage/flatpak-chromeos"
BUNDLE_RELEASE="r152-kukui-16765.41.0"
BUNDLE_NAME="chromeos-flatpak-kukui-r152-arm64.tar.xz"
BUNDLE_URL="https://github.com/rycont/chromeos-flatpak/releases/download/${BUNDLE_RELEASE}/${BUNDLE_NAME}"
BUNDLE_SHA256_URL="${BUNDLE_URL}.sha256"
FLATPAK_USER_DIR="/usr/local/var/lib/flatpak-user"

SUDO="/usr/bin/sudo"
CURL="/usr/bin/curl"
FIND="/usr/bin/find"
GREP="/bin/grep"
ID="/usr/bin/id"
INSTALL="/usr/bin/install"
LN="/bin/ln"
CP="/bin/cp"
CHMOD="/bin/chmod"
CHOWN="/bin/chown"
MKDTEMP="/usr/bin/mktemp"
MV="/bin/mv"
RM="/bin/rm"
SED="/bin/sed"
TAR="/bin/tar"
TEE="/usr/bin/tee"
LDCONFIG="/sbin/ldconfig"
SHA256SUM="/usr/bin/sha256sum"
LSB_RELEASE="/etc/lsb-release"

die() {
	echo "chromeos-flatpak: $*" >&2
	exit 1
}

for tool in "$SUDO" "$CURL" "$FIND" "$GREP" "$ID" "$INSTALL" "$LN" "$CP" \
	"$CHMOD" "$CHOWN" "$MKDTEMP" "$MV" "$RM" "$SED" "$TAR" "$TEE" \
	"$LDCONFIG" "$SHA256SUM"; do
	[ -x "$tool" ] || die "required host tool is missing: $tool"
done

[ -r "$LSB_RELEASE" ] || die "ChromeOS release information is missing"
chromebook_board="$($SED -n 's/^CHROMEOS_RELEASE_BOARD=//p' "$LSB_RELEASE")"
chromebook_version="$($SED -n 's/^CHROMEOS_RELEASE_VERSION=//p' "$LSB_RELEASE")"
case "$chromebook_board" in
	kukui*) ;;
	*) die "this bundle targets kukui, not board $chromebook_board" ;;
esac
[ "$chromebook_version" = "16765.41.0" ] || die \
	"this bundle targets ChromeOS 16765.41.0, not $chromebook_version"

if [ "$($ID -u)" -eq 0 ]; then
	SUDO_CMD=()
else
	"$SUDO" -n true 2>/dev/null || die \
		"passwordless sudo is required; run this from a root-capable ChromeOS shell"
	SUDO_CMD=("$SUDO" -n)
fi

run_root() {
	"${SUDO_CMD[@]}" "$@"
}

ensure_target_link() {
	local target=$1 source=$2
	if [ -e "$target" ] || [ -L "$target" ]; then
		return
	fi
	[ -e "$source" ] || die "required host path is missing: $source"
	run_root "$INSTALL" -d -m 0755 "${target%/*}"
	run_root "$LN" -s "$source" "$target"
}

patch_runtime_paths() {
	local service
	for service in /usr/local/share/dbus-1/services/*.service \
		/usr/local/lib/systemd/user/*.service; do
		[ -f "$service" ] || continue
		run_root "$SED" -i \
			's#Exec=/usr/libexec/#Exec=/usr/local/libexec/#g' "$service"
	done
}

install_runtime_profile() {
	run_root "$INSTALL" -d -m 0755 /usr/local/etc/profile.d
	run_root "$TEE" /usr/local/etc/profile >/dev/null <<'EOF'
# ChromeOS developer sysroot runtime environment for chromeos-flatpak. VT/SSH
# shells can start with only /opt/bin, so include the regular host utilities
# explicitly instead of relying on the inherited PATH.
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/bin${PATH:+:$PATH}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export FLATPAK_SYSTEM_DIR="${FLATPAK_SYSTEM_DIR:-/usr/local/var/lib/flatpak}"
export FLATPAK_USER_DIR="${FLATPAK_USER_DIR:-/usr/local/var/lib/flatpak-user}"

for flatpak_profile in /usr/local/etc/profile.d/*.sh; do
	[ -r "$flatpak_profile" ] && . "$flatpak_profile"
done
unset flatpak_profile
EOF
}

configure_flatpak_user_dir() {
	local chronos_uid chronos_gid
	chronos_uid="$($ID -u chronos 2>/dev/null || true)"
	chronos_gid="$($ID -g chronos 2>/dev/null || true)"
	[ -n "$chronos_uid" ] && [ -n "$chronos_gid" ] || die \
		"the chronos account was not found"
	run_root "$INSTALL" -d -m 0700 "$FLATPAK_USER_DIR"
	run_root "$CHOWN" "$chronos_uid:$chronos_gid" "$FLATPAK_USER_DIR"
}

configure_portage_make_conf() {
	local make_conf=/usr/local/etc/portage/make.conf
	local binhost_value="PORTAGE_BINHOST=\"$BINHOST $COMMON_BINHOST\""
	local fetch_command='FETCHCOMMAND="/usr/bin/curl --connect-timeout 15 -L -# -o \${DISTDIR}/\${FILE} \${URI}"'
	local resume_command='RESUMECOMMAND="/usr/bin/curl --connect-timeout 15 -L -# -C - -o \${DISTDIR}/\${FILE}\${URI}"'

	# Rewrite rather than append: dev_install --uninstall preserves this
	# developer configuration file between runs.
	run_root "$SED" -i \
		'/^PORTAGE_BINHOST=/d; /^FETCHCOMMAND=/d; /^RESUMECOMMAND=/d' \
		"$make_conf"
	run_root "$TEE" -a "$make_conf" >/dev/null <<EOF
$binhost_value
$fetch_command
$resume_command
EOF
}

if [ -d /usr/local ]; then
	first_entry="$(run_root "$FIND" /usr/local -mindepth 1 -maxdepth 1 \
		-print -quit 2>/dev/null || true)"
	[ -z "$first_entry" ] || die \
		"/usr/local is not empty ($first_entry); empty it with dev_install --uninstall, then rerun this script"
fi

workdir="$($MKDTEMP -d /tmp/chromeos-flatpak.XXXXXX)"
trap '"$RM" -rf "$workdir"' EXIT

repo_json="$workdir/repository.json"
repo_ref="${CHROMEOS_FLATPAK_REV:-}"
if [ -z "$repo_ref" ]; then
	"$CURL" -fsSL --retry 3 \
		-H 'Accept: application/vnd.github+json' \
		-H 'X-GitHub-Api-Version: 2022-11-28' \
		-o "$repo_json" "$REPO_API"
	repo_ref="$($SED -n \
		'/^[[:space:]]*"sha":[[:space:]]*"[0-9a-f]\{40\}"/ { s/^[[:space:]]*"sha":[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p; q; }' \
		"$repo_json")"
fi
[ -z "$repo_ref" ] || "$GREP" -Eq '^[0-9a-f]{40}$' <<<"$repo_ref" || \
	die "invalid repository revision: $repo_ref"
[ -n "$repo_ref" ] || die "could not resolve the latest main commit"
repo_tarball="https://github.com/rycont/chromeos-flatpak/archive/${repo_ref}.tar.gz"

echo "chromeos-flatpak: downloading the self-contained overlay"
"$CURL" -fsSL --retry 3 -o "$workdir/overlay.tar.gz" "$repo_tarball"
"$TAR" -xzf "$workdir/overlay.tar.gz" -C "$workdir"
overlay_source="$($FIND "$workdir" -mindepth 1 -maxdepth 1 -type d \
	-name 'chromeos-flatpak-*' -print -quit)"
[ -n "$overlay_source" ] || die "the overlay archive had an unexpected layout"

dev_log="$workdir/dev-install.log"
echo "chromeos-flatpak: initializing the ChromeOS developer sysroot"
if run_root /usr/bin/dev_install --reinstall --yes --binhost="$BINHOST" \
	2>&1 | "$TEE" "$dev_log"; then
	:
else
	if "$GREP" -q 'Could not install virtual/target-os-dev' "$dev_log" \
		&& [ -x /usr/local/bin/emerge ] \
		&& [ -d /usr/local/etc/portage/make.profile ]; then
		echo "chromeos-flatpak: dev_install optional target was unavailable; continuing with the initialized sysroot" >&2
	else
		die "dev_install failed"
	fi
fi

portage_init="$($FIND /usr/local/lib /usr/local/lib64 -type f \
	-path '*/portage/__init__.py' -print -quit 2>/dev/null || true)"
[ -n "$portage_init" ] || die "the dev_install Portage library was not found"

# The ChromeOS developer sysroot keeps its Python shared library under
# /usr/local.  Portage's old phase helpers invoke that interpreter from child
# processes, so make the loader path explicit in every helper that can invoke
# Python (filtering, xattrs, xpak metadata, and IPC).
portage_ebuild="$($FIND /usr/local/lib /usr/local/lib64 -type f \
	-name ebuild.sh -print -quit 2>/dev/null || true)"
[ -n "$portage_ebuild" ] || die "the dev_install Portage ebuild helper was not found"
portage_bindir="${portage_ebuild%/*}"
for helper in ebuild.sh phase-functions.sh misc-functions.sh estrip ebuild-ipc; do
	helper_path="$portage_bindir/$helper"
	[ -f "$helper_path" ] || continue
	if ! run_root "$GREP" -qF \
		'export LD_LIBRARY_PATH="/usr/local/lib64:/usr/local/lib' "$helper_path"; then
		run_root "$SED" -i '3i\
export LD_LIBRARY_PATH="/usr/local/lib64:/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
			"$helper_path"
	fi
done

# Portage 2.3.75 drops PORTAGE_BINHOST while creating the running-root tree
# when ROOT is /usr/local. Preserve it so binary dependencies remain usable.
if ! run_root "$GREP" -q "^[[:space:]]*'PORTAGE_BINHOST',[[:space:]]*$" \
	"$portage_init"; then
	run_root "$SED" -i "/'PORTAGE_USERNAME',/a\\        'PORTAGE_BINHOST'," \
		"$portage_init"
fi

run_root "$INSTALL" -d -m 0755 /usr/local/portage
run_root "$MV" "$overlay_source" "$OVERLAY"
run_root "$INSTALL" -d -m 0755 \
	/usr/local/etc/portage/repos.conf \
	/usr/local/etc/portage/package.use \
	/usr/local/etc/portage/package.accept_keywords
run_root "$CP" -f "$OVERLAY/config/repos.conf/flatpak-chromeos.conf" \
	/usr/local/etc/portage/repos.conf/flatpak-chromeos.conf
run_root "$CP" -f "$OVERLAY/config/package.use/flatpak-chromeos" \
	/usr/local/etc/portage/package.use/flatpak-chromeos
run_root "$CP" -f "$OVERLAY/config/package.use/flatpak-chromeos-portal" \
	/usr/local/etc/portage/package.use/flatpak-chromeos-portal
run_root "$CP" -f "$OVERLAY/config/package.accept_keywords/flatpak-chromeos" \
	/usr/local/etc/portage/package.accept_keywords/flatpak-chromeos

# Several ChromeOS development headers live in the immutable host tree while
# the cross-built packages look below /usr/local. These links are deliberately
# narrow and only bridge the paths used by the pinned kukui build.
ensure_target_link /usr/local/lib64/libffi-3.1/include \
	/usr/lib64/libffi-3.1/include
ensure_target_link /usr/local/include/libmount /usr/include/libmount
ensure_target_link /usr/local/include/blkid /usr/include/blkid
ensure_target_link /usr/local/include/libpng16 /usr/include/libpng16
ensure_target_link /usr/local/include/json-glib-1.0 /usr/include/json-glib-1.0
ensure_target_link /usr/local/include/libxml2 /usr/include/libxml2

# The ChromeOS developer profile lists the host's GLib as package.provided,
# but package.provided cannot express its real SLOT=2.  Dependencies such as
# gdk-pixbuf:2 and xdg-desktop-portal therefore fail to see the host library.
# Remove only that stale provision so the matching ChromeOS GLib binary can be
# registered in the target sysroot. Enumerate as the calling user and edit as
# root; this also works when the profile tree is not traversable by sudo's
# command-substitution environment.
while IFS= read -r provided_file; do
	[ -n "$provided_file" ] || continue
	if run_root "$GREP" -q '^dev-libs/glib-' "$provided_file"; then
		run_root "$SED" -i '/^dev-libs\/glib-/d' "$provided_file"
	fi
done < <("$FIND" -L /usr/local/etc/portage/make.profile/package.provided \
	-type f -print 2>/dev/null)

# The pinned ARM64 GLib binary uses the libc-provided iconv/gettext
# interfaces. Its upstream metadata names the corresponding virtuals, but
# this ChromeOS profile does not list those host capabilities.
provided_dir=/usr/local/etc/portage/make.profile/package.provided
run_root "$INSTALL" -d -m 0755 "$provided_dir"
run_root "$TEE" "$provided_dir/chromeos-flatpak" >/dev/null <<'EOF'
virtual/libiconv-0-r1
virtual/libintl-0-r2
sys-libs/libseccomp-2.5.5
EOF

# The old Portage shipped by this ChromeOS release filters PORTAGE_BINHOST out
# of ebuild environments. The main emerge process also needs to retain it in
# order to populate the second (common ARM64) binhost.
while IFS= read -r special_env; do
	[ -n "$special_env" ] || continue
	if ! run_root "$GREP" -qF "'PORTAGE_BINHOST'" "$special_env"; then
		run_root "$SED" -i "/^environ_whitelist = \[/s/\[/['PORTAGE_BINHOST', /" \
		"$special_env"
	fi
done < <("$FIND" /usr/local/lib /usr/local/lib64 /usr/local/usr/lib \
	/usr/local/usr/lib64 -type f \
	-path '*/portage/package/ebuild/_config/special_env_vars.py' \
	-print 2>/dev/null)

# make.conf wins over inherited values in this old Portage. Configure it
# before the first binary fetch as dev_install may preserve the file.
configure_portage_make_conf
configure_flatpak_user_dir
install_runtime_profile

# ChromiumOS publishes the common index with a gs:// BASE_URI, while this
# developer sysroot only has curl. Translate that bucket URI inside the old
# Portage binhost reader so index refreshes cannot restore the unsupported URI.
while IFS= read -r bintree; do
	[ -n "$bintree" ] || continue
	if ! run_root "$GREP" -qF \
		'remote_base_uri = "https://commondatastorage.googleapis.com/chromeos-prebuilt"' \
		"$bintree"; then
		run_root "$SED" -i '/remote_base_uri = pkgindex.header.get("URI", base_url)/a\
				if remote_base_uri == "gs://chromeos-prebuilt":\
					remote_base_uri = "https://commondatastorage.googleapis.com/chromeos-prebuilt"' \
			"$bintree"
	fi
done < <("$FIND" /usr/local/lib /usr/local/lib64 /usr/local/usr/lib \
	/usr/local/usr/lib64 -type f -path '*/portage/dbapi/bintree.py' \
	-print 2>/dev/null)

echo "chromeos-flatpak: installing the ChromeOS GLib :2 binary"
# The pinned GLib is a compatibility binary from the ChromeOS common binhost.
# Its recorded build dependencies (autoconf-archive, compiler tools, etc.) are
# not needed to install that binary and can collide with the developer sysroot.
# Install exactly this package and let the later Flatpak transaction resolve
# normal runtime dependencies.
run_root env \
	PORTAGE_CONFIGROOT=/usr/local \
	ROOT=/usr/local \
	PORTAGE_BINHOST="$BINHOST $COMMON_BINHOST" \
	PORTDIR_OVERLAY="$OVERLAY" \
	LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib \
	/usr/local/bin/emerge --ignore-default-opts \
	--config-root=/usr/local --root=/usr/local \
	--getbinpkg --usepkgonly --binpkg-respect-use=n --nodeps --verbose \
	=dev-libs/glib-2.76.4-r4

echo "chromeos-flatpak: downloading the tested Flatpak/portal runtime bundle"
"$CURL" -fsSL --retry 3 -o "$workdir/$BUNDLE_NAME" "$BUNDLE_URL"
"$CURL" -fsSL --retry 3 -o "$workdir/$BUNDLE_NAME.sha256" "$BUNDLE_SHA256_URL"
expected_sha256="$($SED -n \
	"s/^\\([0-9a-f]\\{64\\}\\)[[:space:]][[:space:]]${BUNDLE_NAME}$/\\1/p" \
	"$workdir/$BUNDLE_NAME.sha256")"
[ -n "$expected_sha256" ] || die "the bundle checksum file is invalid"
actual_sha256="$($SHA256SUM "$workdir/$BUNDLE_NAME" | "$SED" 's/[[:space:]].*$//')"
[ "$actual_sha256" = "$expected_sha256" ] || die "the runtime bundle checksum does not match"

# The bundle is flattened for /usr/local. Do not preserve archive ownership or
# modes: the bwrap setuid bit is applied explicitly below after extraction.
run_root "$TAR" -xJf "$workdir/$BUNDLE_NAME" -C /usr/local \
	--no-same-owner --no-same-permissions
run_root "$CHMOD" 4755 /usr/local/bin/bwrap

# Portage may install shared libraries below /usr/local/lib64 while the
# immutable host loader cache still only knows the previous sysroot contents.
# Refresh it before the post-install executable checks and future shells.
run_root "$LDCONFIG"

patch_runtime_paths

run_root test -x /usr/local/bin/flatpak
run_root test -x /usr/local/libexec/xdg-desktop-portal
run_root test -f /usr/local/share/dbus-1/services/org.freedesktop.portal.Desktop.service
run_root test -u /usr/local/bin/bwrap
if [ "$($ID -u)" -eq 0 ]; then
	run_root /usr/local/bin/bwrap --ro-bind / / /bin/true
else
	/usr/local/bin/bwrap --ro-bind / / /bin/true
fi
echo "chromeos-flatpak: Flatpak, portal, and the tested bwrap sandbox were installed"
echo "chromeos-flatpak: source /usr/local/etc/profile, then use flatpak --user or flatpak --system"

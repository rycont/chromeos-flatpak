#!/bin/bash

set -euo pipefail

# The VT shell on ChromeOS has a deliberately minimal PATH. Include both
# regular and administrative host utilities used during the bootstrap.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/bin"

BINHOST="https://commondatastorage.googleapis.com/chromeos-dev-installer/board/kukui/16765.41.0/packages"
COMMON_BINHOST="https://commondatastorage.googleapis.com/chromeos-prebuilt/board/arm64-generic/postsubmit-R156-16821.0.0-87474-8670646292013436097/packages"
REPO_API="https://api.github.com/repos/rycont/chromeos-flatpak/commits/main"
OVERLAY="/usr/local/portage/flatpak-chromeos"

SUDO="/usr/bin/sudo"
CURL="/usr/bin/curl"
FIND="/usr/bin/find"
GREP="/bin/grep"
ID="/usr/bin/id"
INSTALL="/usr/bin/install"
CP="/bin/cp"
MKDTEMP="/usr/bin/mktemp"
MV="/bin/mv"
RM="/bin/rm"
SED="/bin/sed"
TAR="/bin/tar"
TEE="/usr/bin/tee"

die() {
	echo "chromeos-flatpak: $*" >&2
	exit 1
}

for tool in "$SUDO" "$CURL" "$FIND" "$GREP" "$ID" "$INSTALL" "$CP" \
	"$MKDTEMP" "$MV" "$RM" "$SED" "$TAR" "$TEE"; do
	[ -x "$tool" ] || die "required host tool is missing: $tool"
done

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
done < <("$FIND" /usr/local/etc/portage/make.profile/package.provided \
	-type f -print 2>/dev/null)

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

echo "chromeos-flatpak: installing the ChromeOS GLib :2 binary"
run_root env \
	PORTAGE_CONFIGROOT=/usr/local \
	ROOT=/usr/local \
	PORTAGE_BINHOST="$COMMON_BINHOST" \
	PORTDIR_OVERLAY="$OVERLAY" \
	LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib \
	/usr/local/bin/emerge --ignore-default-opts \
	--config-root=/usr/local --root=/usr/local \
	--getbinpkg --usepkgonly --binpkg-respect-use=n --verbose \
	=dev-libs/glib-2.76.4-r4

echo "chromeos-flatpak: emerging Flatpak and the core desktop portal"
run_root env \
	PORTAGE_CONFIGROOT=/usr/local \
	ROOT=/usr/local \
	PORTAGE_BINHOST="$BINHOST $COMMON_BINHOST" \
	PORTDIR_OVERLAY="$OVERLAY" \
	LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib \
	/usr/local/bin/emerge --ignore-default-opts \
	--config-root=/usr/local --root=/usr/local \
	--getbinpkg --usepkg --verbose \
	sys-apps/flatpak sys-apps/xdg-desktop-portal

run_root test -x /usr/local/bin/flatpak
run_root test -x /usr/local/libexec/xdg-desktop-portal
run_root test -f /usr/local/usr/share/dbus-1/services/org.freedesktop.portal.Desktop.service
echo "chromeos-flatpak: Flatpak and the core desktop portal were installed"
echo "chromeos-flatpak: run 'flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' next"

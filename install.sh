#!/bin/bash

set -euo pipefail

# The VT shell on ChromeOS has a deliberately minimal PATH. Keep helper
# programs used by tar and env discoverable during the bootstrap.
export PATH="/usr/bin:/bin:/opt/bin"

BINHOST="https://commondatastorage.googleapis.com/chromeos-dev-installer/board/kukui/16765.41.0/packages"
REPO_REF="main"
REPO_TARBALL="https://github.com/rycont/chromeos-flatpak/archive/refs/heads/${REPO_REF}.tar.gz"
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

# Portage 2.3.75 drops PORTAGE_BINHOST while creating the running-root tree
# when ROOT is /usr/local. Preserve it so binary dependencies remain usable.
if ! run_root "$GREP" -q "^[[:space:]]*'PORTAGE_BINHOST',[[:space:]]*$" \
	"$portage_init"; then
	run_root "$SED" -i "/'PORTAGE_USERNAME',/a\\        'PORTAGE_BINHOST'," \
		"$portage_init"
fi

echo "chromeos-flatpak: downloading the self-contained overlay"
"$CURL" -fsSL --retry 3 -o "$workdir/overlay.tar.gz" "$REPO_TARBALL"
"$TAR" -xzf "$workdir/overlay.tar.gz" -C "$workdir"
overlay_source="$($FIND "$workdir" -mindepth 1 -maxdepth 1 -type d \
	-name 'chromeos-flatpak-*' -print -quit)"
[ -n "$overlay_source" ] || die "the overlay archive had an unexpected layout"

run_root "$INSTALL" -d -m 0755 /usr/local/portage
run_root "$MV" "$overlay_source" "$OVERLAY"
run_root "$INSTALL" -d -m 0755 \
	/usr/local/etc/portage/repos.conf \
	/usr/local/etc/portage/package.use
run_root "$CP" -f "$OVERLAY/config/repos.conf/flatpak-chromeos.conf" \
	/usr/local/etc/portage/repos.conf/flatpak-chromeos.conf
run_root "$CP" -f "$OVERLAY/config/package.use/flatpak-chromeos" \
	/usr/local/etc/portage/package.use/flatpak-chromeos
run_root "$CP" -f "$OVERLAY/config/package.use/flatpak-chromeos-portal" \
	/usr/local/etc/portage/package.use/flatpak-chromeos-portal

echo "chromeos-flatpak: emerging Flatpak and the GTK desktop portal"
run_root env \
	PORTAGE_CONFIGROOT=/usr/local \
	ROOT=/usr/local \
	PORTAGE_BINHOST="$BINHOST" \
	PORTDIR_OVERLAY="$OVERLAY" \
	LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib \
	/usr/local/bin/emerge --ignore-default-opts \
	--getbinpkg --usepkg --verbose \
	sys-apps/flatpak sys-apps/xdg-desktop-portal-gtk

run_root test -x /usr/local/bin/flatpak
run_root test -x /usr/local/libexec/xdg-desktop-portal
run_root test -f /usr/local/usr/share/dbus-1/services/org.freedesktop.portal.Desktop.service
echo "chromeos-flatpak: Flatpak and the optional GTK portal were installed"
echo "chromeos-flatpak: run 'flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' next"

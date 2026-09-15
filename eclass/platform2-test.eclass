# Copyright 2023 The ChromiumOS Authors
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: platform2-test.eclass
# @MAINTAINER:
# ChromiumOS Build Team
# @BUGREPORTS:
# Please report bugs via http://crbug.com/new (with label Build)
# @VCSURL: https://chromium.googlesource.com/chromiumos/overlays/chromiumos-overlay/+/HEAD/eclass/@ECLASS@
# @BLURB: helper eclass pulling in the correct dependencies for platform2_test.py
# @DESCRIPTION:
# platform2_test.py is primarily used to execute unit tests for platform2
# packages, but it's also used by some packages while building to emulate the
# host system.

if [[ -z "${_ECLASS_PLATFORM2_TEST}" ]]; then
_ECLASS_PLATFORM2_TEST=1

case ${EAPI:-0} in
[0123456]) die "Unsupported EAPI=${EAPI:-0} (too old) for ${ECLASS}" ;;
esac

IUSE="cros_host test"

# @ECLASS-VARIABLE: PLATFORM2_TEST_DEPS
# @PRE_INHERIT
# @DESCRIPTION:
# Controls when to add the dependencies. If cros_host is set, this eclass
# doesn't do anything, since you should only be using platform2_test.py when
# cross-compiling.
#
# * test-only -- Add dependencies with `test? ()`. i.e., platform2_test.py is
#                only used when running unit tests.
# * build+test -- Unconditionally add the dependencies. i.e., platform2_test.py
#                 is used for building and unit testing.
: "${PLATFORM2_TEST_DEPS:=test-only}"

BDEPEND="
	!cros_host? (
		dev-python/psutil
		sys-apps/iproute2
		sys-apps/proot
		sys-libs/libcap-ng
		!amd64? ( !x86? ( app-emulation/qemu ) )
	)
"

# python: platform2_test.py may run tests via gtest-parallel, which is a python
# script. Because this is run after chroot'ing into the sysroot, this needs to
# be in DEPEND, not BDEPEND.
DEPEND="
	!cros_host? ( dev-lang/python )
"

case "${PLATFORM2_TEST_DEPS}" in
	test-only)
		BDEPEND="test? ( ${BDEPEND} )"
		DEPEND="test? ( ${DEPEND} )"
		;;
	build+test)
		;;
	*)
		die "Unsupported PLATFORM2_TEST_DEPS=${PLATFORM2_TEST_DEPS}"
		;;
esac

fi

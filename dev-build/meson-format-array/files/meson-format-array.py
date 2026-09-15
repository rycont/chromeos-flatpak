#!/usr/bin/env python3
# Copyright 2020 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

import itertools
import shlex
import sys


def quote(s):
    """Surround a value with quotes, escaping embedded quotes.

    >>> quote("foobar")
    "'foobar'"
    """

    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def format_array(args):
    """Format shell-compatible expressions as a Meson array.

    >>> format_array(['-O2 -pipe -DFOO="bar baz"'])
    "['-O2', '-pipe', '-DFOO=bar baz']"
    """

    args = (shlex.split(x) for x in args)
    args = itertools.chain.from_iterable(args)
    args = (quote(x) for x in args)
    return "[" + ", ".join(args) + "]"


def main(args):
    print(format_array(args))


if __name__ == "__main__":
    main(sys.argv[1:])

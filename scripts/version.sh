#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
version=$(sed -n 's/.*\.version = "\([^"]*\)".*/\1/p' build.zig.zon)
[ -n "$version" ] || { echo "Cannot read project version" >&2; exit 1; }
printf '%s\n' "$version"

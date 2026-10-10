#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
version=$(sh scripts/version.sh)
tag=${1:?Usage: release.sh vVERSION [output-directory]}
[ "$tag" = "v$version" ] || { echo "Tag $tag does not match project version v$version" >&2; exit 1; }
[ "$(zig version)" = "$(cat .zig-version)" ] || { echo "Use the pinned Zig version" >&2; exit 1; }
output=${2:-dist}
mkdir -p "$output"
output=$(cd "$output" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/zman-release.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
for target in aarch64-macos aarch64-linux x86_64-linux; do
    zig build install -Doptimize=ReleaseSafe -Dtarget="$target" --prefix "$work/$target"
    stage="$work/archive-$target"
    mkdir -p "$stage"
    cp "$work/$target/bin/zman" "$stage/zman"
    cp LICENSE README.md "$stage/"
    COPYFILE_DISABLE=1 tar -czf "$output/zman-$tag-$target.tar.gz" -C "$stage" zman LICENSE README.md
    cp "$stage/zman" "$output/zman-$tag-$target"
done
cd "$output"
: > SHA256SUMS
for target in aarch64-macos aarch64-linux x86_64-linux; do
    for artifact in "zman-$tag-$target" "zman-$tag-$target.tar.gz"; do
        if command -v sha256sum >/dev/null 2>&1; then sha256sum "$artifact" >> SHA256SUMS; else shasum -a 256 "$artifact" >> SHA256SUMS; fi
    done
done

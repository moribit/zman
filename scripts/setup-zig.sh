#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
version=$(cat .zig-version)
case "$(uname -s)" in Linux) os=linux ;; Darwin) os=macos ;; *) echo "Unsupported host OS" >&2; exit 1 ;; esac
case "$(uname -m)" in x86_64) arch=x86_64 ;; aarch64|arm64) arch=aarch64 ;; *) echo "Unsupported host architecture" >&2; exit 1 ;; esac
archive="zig-$arch-$os-$version.tar.xz"
base="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/zman-zig-$version"
mkdir -p "$base"
curl --fail --location --retry 3 "https://ziglang.org/download/$version/$archive" -o "$base/$archive"
expected=$(awk -v name="$archive" '$2 == name { print $1 }' .github/zig-SHA256SUMS)
[ -n "$expected" ] || { echo "No pinned checksum for $archive" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then actual=$(sha256sum "$base/$archive" | awk '{print $1}'); else actual=$(shasum -a 256 "$base/$archive" | awk '{print $1}'); fi
[ "$actual" = "$expected" ] || { echo "Zig download checksum mismatch" >&2; exit 1; }
tar -xJf "$base/$archive" -C "$base"
zig_dir="$base/zig-$arch-$os-$version"
[ "$("$zig_dir/zig" version)" = "$version" ] || { echo "Zig version mismatch" >&2; exit 1; }
if [ -n "${GITHUB_PATH:-}" ]; then printf '%s\n' "$zig_dir" >> "$GITHUB_PATH"; fi
printf '%s\n' "$zig_dir"

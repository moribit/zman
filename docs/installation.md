# Installation

## Platforms

| Host | Archive target |
| --- | --- |
| macOS Apple Silicon | `aarch64-macos` |
| Linux ARM64 | `aarch64-linux` |
| Linux x86_64 | `x86_64-linux` |

Use **Zig 0.17.x on PATH**, including with prebuilt zman. Documentation comes
from that installation; first-time semantic indexing uses its compiler. See
[Zig version support](zig-version-support.md).

Third-party library dependencies: none. Linux release binaries are static and
do not require an external libc. `man`, a pager, and an editor are optional host
tools. No package manager or runtime network access is required for queries.

## Prebuilt

The published [1.0.0 release](https://github.com/moribit/zman/releases/tag/v1.0.0)
contains archives, raw executables, and SHA256SUMS. Each archive contains
`zman`, `LICENSE`, and `README.md`. Select your target before downloading:

```sh
version=1.0.0
target=aarch64-linux  # or aarch64-macos / x86_64-linux
archive="zman-v${version}-${target}.tar.gz"
base="https://github.com/moribit/zman/releases/download/v${version}"
curl -fLO "$base/$archive"
curl -fLO "$base/SHA256SUMS"
```

### Verify the download

From the directory containing both downloads, check the selected archive:

```sh
awk -v name="$archive" '$2 == name {print}' SHA256SUMS > selected.sha256
test -s selected.sha256
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c selected.sha256
else
    shasum -a 256 -c selected.sha256
fi
```

Stop if verification fails. SHA256SUMS covers raw executables as well as archives;
select the raw binary's filename if using that download instead.

### Install and PATH

```sh
mkdir -p zman-release ~/.local/bin
tar -xzf "$archive" -C zman-release
install -m 755 zman-release/zman ~/.local/bin/zman
~/.local/bin/zman --version
export PATH="$HOME/.local/bin:$PATH"
```

Add the PATH line to your shell configuration to keep it across sessions.
Installation requires no sudo. These download steps use the network once;
`zman` itself reads local documentation only.

### macOS

Release binaries are not Developer ID signed or notarized. macOS may require
per-app approval after checksum verification. Building from source is another option.

## From source

```sh
git clone https://github.com/moribit/zman.git
cd zman
zig build -Doptimize=ReleaseSafe
zig build install -Doptimize=ReleaseSafe --prefix ~/.local
~/.local/bin/zman --version
```

The default build writes `zig-out/bin/zman`. Cross compilation is available with
`zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe`; the other release targets
are `aarch64-linux` and `aarch64-macos`.

Continue with [getting started](getting-started.md). For build/test setup rather
than user installation, see [contributing](contributing.md).

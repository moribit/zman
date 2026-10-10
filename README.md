# zman

**man(1) for Zig.**

Fast, local Zig standard library documentation from your terminal.

```sh
zman std.posix.read
zman "open file"
zman std.ArrayListUnmanaged
zman std.os.linux.write --man
```

- Uses the documentation shipped with your installed Zig.
- No runtime network access or third-party dependencies.
- Search, source lookup, semantic resolution, and host system manual integration.

[![CI](https://github.com/moribit/zman/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/moribit/zman/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/moribit/zman)](https://github.com/moribit/zman/releases/latest)
[![License](https://img.shields.io/github/license/moribit/zman)](LICENSE)

## In the terminal

An excerpt from `zman std.ArrayListUnmanaged`, using Zig 0.17.0:

```text
std.ArrayListUnmanaged
──────────────────────

TYPE FACTORY

SEMANTICS
  Status      resolved
  Alias of    std.ArrayList
  Returns     type

SIGNATURE
  pub fn ArrayList(comptime T: type) type
```

The rest includes the original documentation, source location, and Zig version.
TTY output adds syntax highlighting and a consistent visual hierarchy; plain
output keeps the same layout.

## Why zman?

`zman` complements `zig std`. Use `zig std` to browse in a browser; use `zman`
when you are already in a shell or editor and want to inspect an API, find a
symbol, jump to source, or pipe the result into another tool.

| Workflow | `zig std` (Zig 0.17) | `zman` |
| --- | --- | --- |
| Main interface | Locally served browser docs | Terminal CLI |
| Search | Browser search field | Symbol or free-text query |
| Read source | Linked source view | Source context and editor jump |
| Output for tools | Web pages | Plain text or JSON |

## Installation

Requires **Zig 0.17.x on PATH**, including with a prebuilt binary.

### Prebuilt

Download the archive for your platform from the published
[1.0.0 release](https://github.com/moribit/zman/releases/tag/v1.0.0):
`aarch64-macos`, `aarch64-linux`, or `x86_64-linux`.
[Verify its checksum](docs/installation.md#verify-the-download), then install:

```sh
tar -xzf zman-v1.0.0-aarch64-linux.tar.gz
mkdir -p ~/.local/bin
install -m 755 zman ~/.local/bin/zman
```

Choose the matching filename. Add `~/.local/bin` to PATH if needed.
See [installation](docs/installation.md) for downloads, PATH, and macOS notes.

### From source

From a checkout, with Zig 0.17.x:

```sh
zig build -Doptimize=ReleaseSafe
zig build install -Doptimize=ReleaseSafe --prefix ~/.local
```

## Quick start

```sh
zman std.posix.read
zman "open file"
zman std.ArrayList
zman source std.posix.read
zman std.os.linux.write --man
zman --json std.posix.read
```

The first query builds a local index; initial semantic helper compilation may
take about 14 seconds. Subsequent queries use the cache. Start with the
[getting started guide](docs/getting-started.md) for a short walkthrough.

## What you can do

### Look up an API

`zman posix.read` accepts the optional `std.` prefix. A name such as `zman read`
shows candidates when multiple declarations match.

### Search without knowing the API name

`zman "open file"` finds names such as `std.Io.Dir.openFile` before incidental
documentation matches. [Search](docs/search.md) covers tokenization and typos.

### Inspect aliases and type factories

`zman std.ArrayListUnmanaged` shows its alias relationship to `std.ArrayList`.
Signatures and docs retain their original source; complex cases remain
[unresolved](docs/semantic-resolution.md) rather than guessed.

### Read or open source

`zman source std.posix.read` shows source context.
`EDITOR=nvim zman edit std.posix.read` jumps to the original declaration.

### Bridge a Zig API to the host system manual

```text
std.os.linux.write
├── Zig source and signature
└── write(2)
    └── host system manual
```

`zman std.os.linux.write --man` displays the reference;
`zman man std.os.linux.write` opens it. The manual belongs to your host OS,
and is a separate source from Zig docs. See [system manuals](docs/system-manuals.md).

## Key features

- Exact lookup, deterministic text search, and symbol typo suggestions
- Official source signatures, doc comments, and source locations
- Official Zig autodoc semantic resolution: aliases, re-exports, and type factories
- Syntax highlighting, readable plain output, and pager support
- Source/editor integration and a host system manual bridge
- JSON output and a local cache
- Zero third-party dependencies; no runtime network access

## Source of truth

**zman does not invent API documentation.** Signatures and docs come from your
installed Zig source. Semantic links come from installed **official Zig autodoc**.
Host system manual references are labeled separately. Unknown semantic cases
remain unresolved instead of being guessed; this is not full compiler evaluation.

## Platform and Zig support

Prebuilt binaries: **macOS aarch64**, **Linux aarch64**, **Linux x86_64**.
Primary Zig version: **0.17.x**. Other versions are best effort and may fall back
to a syntax-only index. See [Zig version support](docs/zig-version-support.md).

## Documentation

- [Getting started](docs/getting-started.md)
- [Command reference](docs/commands.md)
- [Search](docs/search.md)
- [Semantic resolution](docs/semantic-resolution.md)
- [Host system manuals](docs/system-manuals.md)
- [Installation](docs/installation.md)
- [Zig version support](docs/zig-version-support.md)
- [Architecture](docs/architecture.md)
- [Contributing](docs/contributing.md)

These pages describe current usage and design. For historical implementation
reports and measurements, see [IMPLEMENTATION.md](IMPLEMENTATION.md).

## Contributing

Issues and focused pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md)
for setup, tests, and project principles. Release history is in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE).

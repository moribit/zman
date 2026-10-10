# zman

**man(1) for Zig.**

Search and read the documentation shipped with your local Zig installation,
without leaving the terminal.

## Example

```sh
zman std.posix.read
```

## Why

`zig std` provides browser-oriented browsing. `zman` provides terminal-oriented
lookup and search, alongside tools such as `man`. It complements official browser docs.

## Features

- Exact symbol lookup, optional `std.` prefix, deterministic text search and typo suggestions
- Official signatures and comments, source locations and surrounding source
- ANSI syntax highlighting, plain pipe output, pager and editor integration
- JSON output and automatically rebuilt versioned local cache
- macOS and Linux; one executable, no libc linkage requested

Dependencies: none (a local Zig installation supplies documentation).
Runtime network access: none.
Documentation source: your local Zig installation.

## Installation

### Prebuilt binary

Release automation is not included yet. When binaries are published, download the
one matching your OS and architecture and place it in `~/.local/bin/zman`.
No other runtime package is required, apart from Zig as the documentation source.

### From source

Use Zig 0.17.x:

```sh
zig build -Doptimize=ReleaseSafe
zig build install -Doptimize=ReleaseSafe --prefix ~/.local
~/.local/bin/zman --version
```

Add `~/.local/bin` to PATH if necessary. Cross compile with
`zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe` (also `aarch64-linux`
and `aarch64-macos`).

## Usage

### Symbol lookup

```sh
zman std.posix.read
zman posix.read
zman read
zman ArrayList
zman std.Io
zman --json std.posix.read
```

Exact public paths win; a short name opens directly only if unique. Ambiguous
names produce candidates. API availability follows your installed Zig.

### Search

```sh
zman "open file"
zman search "open file" --limit 20
zman allocator
zman posx.read
```

Search splits punctuation, underscores, camelCase and PascalCase. Exact names
and complete name-token matches outrank comment matches. Ties use path length,
then lexical order. Fuzzy matching applies to single symbol/path queries only. Dotted path typo
suggestions outrank prose matches; short-name fuzzy matches have the lowest score.
Zig 0.17 exposes file operations under `std.Io.Dir`, so search returns those
paths rather than inventing earlier `std.fs.Dir` APIs.

### Source

```sh
zman source std.posix.read
zman std.posix.read --source
```

Source includes the complete declaration and three context lines on each side.

### Editor

```sh
EDITOR=nvim zman edit std.posix.read
```

Editor priority: `ZMAN_EDITOR`, `VISUAL`, `EDITOR`. vi/vim/nvim and code support
line jumps; other editors receive the file path. Commands support quoting and
backslash escaping, but never run through a shell or expand shell expressions.

Color defaults to auto: stdout TTY, no `NO_COLOR`, and `TERM` other than `dumb`.
Use `--color=auto|always|never` or `--no-color`. Explicit always permits color
when redirected; `NO_COLOR` and `TERM=dumb` still disable it.

Pager priority: `ZMAN_PAGER`, `PAGER`, `less -R`, direct stdout. Auto uses a
40-line threshold on TTY output. `--pager=auto|always|never` controls it;
redirected output always bypasses the pager. Custom pager options are respected.
JSON disables color and pager.

## Documentation source

Documentation bodies are extracted verbatim from the **installed Zig standard
library source**, not generated or inferred by zman. Comment markers are removed
only in human output; JSON retains original comments. Every entry records its
source path, line and byte range. Displayed version identifies the local Zig
source, separately from zman's own version.

## Zig version compatibility

Developed and tested against Zig 0.17. Other major/minor versions produce a
warning and are attempted on a best-effort basis. `zig env` supplies the compiler,
library, stdlib, target and version; both JSON and current 0.17 ZON output are
supported. No installation path is compiled into zman.

## Design philosophy

`std.zig` is the public root. Zig's AST extracts public functions and variables,
inline container members, and literal `@import("relative.zig")` namespaces.
Private files are not assigned namespaces merely from their filenames.
Signatures are source slices; function bodies are excluded. Container signatures
end at the container keyword, with complete declarations available via `source`.

This is a syntax index, not a semantic type checker. Indirect aliases, conditional
imports, generated types returned by functions, `@This()` aliases and computed
namespace expressions are not expanded. A binding whose initializer is a type
alias remains syntactically `const`; its semantic type is not inferred. Container
fields and enum values are not indexed as public declarations. Phase 4 could use
compiler/autodoc analysis to resolve these while preserving source fidelity.

Cache: checksum-protected JSON envelope, `ZMAN` marker, format version 1, and an
identity including Zig version, executable, stdlib path and target. Every traversed
source file's size and nanosecond mtime is checked on load. Corrupt or stale caches
are rebuilt. The cache uses `XDG_CACHE_HOME`, otherwise `~/Library/Caches` on
macOS or `~/.cache` on Linux. Missing HOME disables caching. Cache writes failing
are nonfatal. `zman reindex` forces rebuilding. Concurrent writes can cause a
rebuild on the next run; no external database is used.

Non-goals: online docs, LLM/embedding search, package indexes, TUI, LSP, semantic
checker reimplementation, language/compiler docs or POSIX man integration.

## Development

```sh
zig build
zig build test
zig build integration  # uses the installed Zig source
zig build install --prefix /tmp/zman-install
```

Tests use small fixtures for AST extraction, namespace traversal, comments,
search, argv quoting, highlighting and plain rendering. The parser is isolated
in `src/parser.zig`; search and render do not depend on AST types.

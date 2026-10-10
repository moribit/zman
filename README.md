# zman

**man(1) for Zig.**

Search and read the documentation shipped with your local Zig installation,
without leaving the terminal.

## Example

```sh
zman std.posix.read
zman "open file"
zman std.ArrayListUnmanaged
zman std.posix.read --man
```

## Why

`zig std` provides browser-oriented browsing. `zman` provides terminal-oriented
lookup and search, alongside tools such as `man`. It complements official browser docs.

## Features

- Exact lookup, optional `std.` prefix, deterministic search and typo suggestions
- Official source signatures/comments, source locations and surrounding source
- Official Zig autodoc declaration links, aliases/re-exports and type factories
- ANSI highlighting, plain pipes, pager/editor integration and JSON
- Optional, clearly separated host system manual references
- Versioned local cache; macOS and Linux; one distributable executable

Third-party dependencies: **none**. Runtime network access: **none**.
Documentation source: **your installed Zig**. Zig is required for documentation
and the first semantic index build. `man`, pager and editor are optional host tools.
No external database, WASM runtime, libc linkage or package dependency is added.

## Installation

### Prebuilt releases

A matching `vVERSION` tag builds and publishes archives and raw binaries to
[GitHub Releases](https://github.com/moribit/zman/releases).
Available targets: `aarch64-macos`, `aarch64-linux`, `x86_64-linux`.
Archives contain `zman`, `LICENSE`, and `README.md`; `SHA256SUMS` covers both
archives and raw executables.

For a published version (choose the matching target):

```sh
version=0.2.0-beta.1
target=aarch64-macos  # or aarch64-linux / x86_64-linux
archive="zman-v${version}-${target}.tar.gz"
base="https://github.com/moribit/zman/releases/download/v${version}"
curl -fLO "$base/$archive"
curl -fLO "$base/SHA256SUMS"
awk -v name="$archive" '$2 == name {print}' SHA256SUMS > selected.sha256
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c selected.sha256
else
    shasum -a 256 -c selected.sha256
fi
mkdir -p zman-release ~/.local/bin
tar -xzf "$archive" -C zman-release
install -m 755 zman-release/zman ~/.local/bin/zman
~/.local/bin/zman --version
```

Add `~/.local/bin` to PATH if necessary. macOS release binaries are not Developer ID
signed or notarized. Release publication occurs when the version tag is pushed;
source checkout and local packaging alone do not publish anything.

### From source

Use Zig 0.17.x:

```sh
zig build -Doptimize=ReleaseSafe
zig build install -Doptimize=ReleaseSafe --prefix ~/.local
~/.local/bin/zman --version
```

Cross compile with `zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe`
(also `aarch64-linux` and `aarch64-macos`).

## Usage

### Symbol lookup

```sh
zman std.posix.read
zman posix.read
zman read
zman std.ArrayList
zman std.Io
zman --json std.posix.read
```

Exact public paths win; a short name opens directly only if unique. Ambiguous
names produce candidates. API availability follows the installed Zig source.

### Search

```sh
zman "open file"
zman search "open file" --limit 20
zman allocator
zman posx.read
```

Search splits punctuation, underscores, camelCase and PascalCase. Complete
name-token matches outrank comment matches. Ties use public path length, then
lexical order. Dotted path typo suggestions outrank prose matches; ordinary
short-name fuzzy matches have the lowest score. Results sharing a known canonical
declaration are grouped, while an alias-specific match retains that public path.
Zig 0.17 file operations live under `std.Io.Dir`, so `open file` returns those
names rather than inventing earlier `std.fs.Dir` APIs.

### Source

```sh
zman source std.posix.read
zman std.posix.read --source
```

Source includes the complete declaration and three context lines on each side.
Resolved aliases show/jump to the original declaration. JSON also preserves
`alias_source`, `alias_signature`, and `alias_docs` for the export binding.

### Editor

```sh
EDITOR=nvim zman edit std.posix.read
```

Priority: `ZMAN_EDITOR`, `VISUAL`, `EDITOR`. vi/vim/nvim and code support line jumps;
other editors receive the file path. Commands support quoting/backslash escaping,
but never run through a shell or expand shell expressions.

### Semantic resolution

```sh
zman std.ArrayListUnmanaged
zman --json std.ArrayListUnmanaged
zman std.ArrayList
```

The syntax index is enriched by **the installed Zig autodoc `Walk.zig` and
`Decl.zig`**, also used by `zig std` and `-femit-docs`. On index creation, zman
compiles a native helper with the installed Zig compiler. The adapter changes
allocation for native execution, adds recursion guards, and corrects the shipped
return-expression accessor to match Zig 0.17's optional AST operand; it does not replace
Zig's declaration lookup/classification rules. A content-identified helper and
Zig compiler cache are reused for subsequent index builds. Cached lookup/search
never compile or execute the helper.

Aliases/re-exports follow official declaration IDs. Canonical paths prefer a
public direct declaration, then the shortest public path and lexical order.
Both alias and canonical names remain queryable. `@This()` links come from the
autodoc namespace scope, including private `Self` relationships.

Literal `type`-returning functions are labeled `TYPE FACTORY`. Public members of
literal returned containers are exposed when already present in autodoc's graph;
members of unused local containers are excluded. Generic-context `@This()` links
that would conflate a generated type with its factory remain unresolved;
there is no arbitrary generic instantiation engine. `ArrayList(u8).append` is not
instantiated by zman.

`resolution` distinguishes `syntax_only`, `resolved`, `partially_resolved`,
`unresolved`, and `cyclic`. Here, resolved means the **official autodoc structural
metadata** resolved the declaration/classification. This is not a full compiler
semantic evaluation or a proof that a standalone source fragment compiles.
Autodoc fallback classifications and conditional branch heuristics are rejected
when they cannot establish the requested fact. Unknowns stay unknown.

First semantic indexing may take roughly 14 seconds for helper compilation;
a cached helper makes rebuilding much faster. Index status goes to stderr.
Missing/incompatible autodoc internals or a failed helper produce a warning and
retain syntax-only functionality. `zman reindex` retries the backend.

JSON retains existing name/kind/signature/docs/source fields and adds
`semantic_kind`, `resolution`, `canonical_name`, `aliases`, `alias_of`,
`reexport_of`, `target_entry`, `member_of`, `returns_type`, `is_type`, and
`is_namespace`. `kind` remains the declaration's syntactic kind; `semantic_kind`
provides its official autodoc classification. Index IDs are cache-local, not a
stable external identifier.

### POSIX / system man integration

```sh
zman std.posix.read --man       # Zig docs plus reference; never opens man
zman man std.posix.read         # executes: man 2 read
zman man std.posix.read --json  # metadata only; never executes man
```

References use an explicit table with `direct` / `related` relations. Output says:

```text
SYSTEM MANUAL

System manual on this host:
    read(2) [direct]
```

System manuals are a separate information source from Zig docs. macOS supplies
Darwin manuals; Linux supplies that host's installed manuals. JSON includes
`system_manual` metadata without opening a manual.

The table covers 23 actual Zig 0.17 `std.posix` APIs, including `read`, `openat`,
`poll`, `ppoll`, `getpeername`, `setsockopt`, memory mapping and signals. In 0.17,
`std.posix.open/write/close/socket/...` and the old posix epoll wrappers are absent;
existing `std.os.linux` syscall declarations and `std.c` declarations cover those
names instead. `std.Io.Dir.openFile` has an explicitly **related** `open(2)` entry.
No removed API is added to the documentation index.

Missing `man`: `error: man command not found`. Missing page: a host-specific page
not-installed message. Other failures are reported separately. No distribution
package install is attempted. Host man programs may apply their own formatting
or pager behavior; zman invokes them with argv, without a shell.

### Terminal options

Color defaults to auto: stdout TTY, no `NO_COLOR`, and `TERM` other than `dumb`.
Use `--color=auto|always|never` or `--no-color`. Explicit always permits redirected
color; `NO_COLOR` and `TERM=dumb` still disable it. Documentation prose is not
syntax highlighted.

Pager priority: `ZMAN_PAGER`, `PAGER`, `less -R`, direct stdout. Auto uses a 40-line
threshold on TTY output. `--pager=auto|always|never` controls it. Redirected output
bypasses zman's pager. Custom options are respected. JSON disables color/pager.

## Documentation source

Documentation bodies and signatures come directly from the **installed Zig
standard library source**, not generated or inferred prose. Human output removes
comment markers; JSON preserves original comments. Semantic links/classifications
come from the **installed official Zig autodoc implementation**. Each entry records
its source file, line and byte range. System man metadata is labeled separately.

## Zig version compatibility

Developed against Zig 0.17. Other major/minor versions produce a warning and are
attempted on a best-effort basis. `zig env` supplies executable, lib, stdlib,
target and version; JSON and 0.17 ZON output are supported. No installation path
is compiled into the binary. CI/release pin Zig in `.zig-version` and verify
official download checksums.

## Design philosophy

`std.zig` is the public root. The syntax index uses Zig AST public declarations
and literal imports, without assigning namespaces from filenames. The semantic
backend may read other stdlib files to resolve links, but exports only paths
reachable through the official public declaration graph. AST and autodoc internals
are isolated in parser/helper modules; search/render/cache use plain Entry data.

This is **not a Zig compiler replacement**. Unresolved cases include target/comptime
conditionals, arbitrary computed namespaces, compiler-only reflection such as
`@TypeOf`/`@Type`, generic instances and ambiguous generated members. Namespace
expansion stops when an ancestor declaration is revisited. Enum values/container
fields are not indexed as independent public declarations. Autodoc's own missing
links remain unresolved; aliases reaching those declarations are only partial.

Cache format 2: textual `ZMAN`/version/checksum header plus JSON payload. It stores
semantic relationships and validates size/mtime for source files/directories and
the installed autodoc backend. Identity includes Zig version/executable/stdlib/
target plus the adapter revision and backend metadata. Old or corrupt caches are
rebuilt. Cache writes use temporary files and atomic rename. Content restored to
identical size/mtime is outside this invalidation scheme.

Cache priority: `XDG_CACHE_HOME`, otherwise `~/Library/Caches` on macOS or
`~/.cache` on Linux. Without HOME, lookup runs without a persistent index cache.
Cache write failures are nonfatal. `zman reindex` forces rebuilding;
`zman reindex --json` reports semantic counts. Helper sources/compiler artifacts
are cached separately from the documentation index.

Non-goals: online docs, LLM/embedding search, package indexes, TUI, LSP, language
reference/compiler-source full-text search or replacing the compiler.

## Development

```sh
zig build
zig build test
zig build integration
zig build install --prefix /tmp/zman-install
sh scripts/release.sh v0.2.0-beta.1 /tmp/zman-release
```

Unit tests use small fixtures and injected man executables. Integration uses the
installed Zig autodoc backend for semantic fixtures and real stdlib examples.
CLI integration caches stay under `.zig-cache/zman-integration`.

CI runs on Ubuntu and macOS. Tag release checks `v$(sh scripts/version.sh)` against
`build.zig.zon`, tests, cross compiles all three targets, packages checksums, then
publishes with GitHub CLI. Only official GitHub Actions are used and commit SHA
pinned. CLI version comes from the same `build.zig.zon` source.

Implementation details, measurements and limitations: [IMPLEMENTATION.md](IMPLEMENTATION.md).

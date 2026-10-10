# Architecture

This page describes current design. [IMPLEMENTATION.md](../IMPLEMENTATION.md)
retains historical phase reports, verification output, and measurements; older
sections there are not the current command reference.

```text
Installed Zig
├── standard library source
│   └── syntax index (parser.zig)
└── official Zig autodoc
    └── semantic resolver (semantic.zig + native helper)
                │
                ▼
            Entry index
            ├── deterministic search
            ├── human renderer + tokenizer highlighting
            ├── JSON renderer
            └── versioned local cache

query → exact lookup / search → Entry → terminal output or JSON
```

## Environment and syntax index

`environment.zig` runs PATH's `zig env` using argv, accepts JSON and 0.17 ZON
output, and discovers version, executable, lib/std paths, and target. No Zig
installation path is compiled into zman.

`parser.zig` uses `std.zig.Ast`, starting from `std/std.zig`. Public declarations,
literal imports, and containers establish public paths; filenames alone are not
namespaces. It slices original declaration signatures/doc comments and stores
source line/byte ranges. AST types do not cross the Entry model boundary.

## Semantic backend

Installed `lib/compiler/std-docs.zig` and the compiler's `-femit-docs` path use
`lib/docs/wasm/Walk.zig` and `Decl.zig`. zman compiles these installed official
autodoc components with an embedded native driver, rather than implementing a
new semantic analyzer or requiring a WASM runtime.

The adapter substitutes a native arena allocator, adds recursion guards, and
corrects the shipped return-expression accessor to match 0.17's optional AST
operand. Adaptation requires exact source anchors. It preserves the official
lookup/classification algorithm; additional validation declines unsafe fallback
and branch classifications. Incompatible internals or helper failures produce
a warning and syntax-only fallback.

The driver emits neutral facts: declaration IDs, parents, targets, public
visibility, categories, and original source slices/locations. Only paths
reachable from the public std root are exported. Graph expansion excludes
ambiguous or unrelated generated members; alias chains use visited IDs and
official recursion uses a file/node/operation/child-name stack. Bounds prevent
unbounded expansion. Private alias links can remain location-based relationships.

Enrichment selects canonical public paths and retains alias bindings separately
from target signatures/docs. [Semantic resolution](semantic-resolution.md)
documents user-visible meanings and limitations. Compiler/autodoc internal types
never enter search, render, or cache APIs.

Helper sources have a content-identified directory and are checked before reuse;
compiler artifacts are cached alongside the index. A cached lookup does not
compile or execute the helper. Index storage uses a long-lived arena; helper and
search temporary allocations have separate lifetimes.

## Search and rendering

Exact lookup precedes a linear ranked search. ASCII/token normalization and
bounded edit distance are deterministic; canonical-target deduplication follows
ranking. No model or network is involved. See [search](search.md).

HumanRenderer centralizes title/section/body/metadata layout. `style.zig` maps UI
and lexer roles to basic ANSI styles; `highlight.zig` uses `std.zig.Tokenizer`.
Doc prose is not Zig code. JSON has a separate renderer and retains source bytes.
The CLI decides TTY/color/pager behavior; pager/editor/man use argv, not a shell.

## Cache

Cache directory selection is `XDG_CACHE_HOME`, then `~/Library/Caches` on macOS
or `~/.cache` on Linux. The index is `zman/<identity-hash>/index.json`. Without
both XDG_CACHE_HOME and HOME, queries run without a persistent index cache.

Format 2 is a `ZMAN`/format-version/Wyhash-checksum header followed by a JSON
payload. It stores entries, relationships, semantic counts, and source metadata.
The checksum detects corruption, not malicious tampering. Old/invalid/corrupt
caches rebuild; writes use a unique temporary file and atomic rename. Cache
write failure warns but does not prevent lookup.

Identity includes installed Zig version/executable/std path/target, adapter
content revision, and autodoc backend metadata. Files and directories are
validated by size and mtime; backend source changes also invalidate. Edits that
deliberately preserve size and mtime are outside this scheme. `zman reindex`
forces rebuilding; `zman reindex --json` exposes entry/semantic counts.

For a development-machine example, Phase 4 ReleaseSafe medians were about
73 ms cached exact lookup and 103 ms search. These are measurements, not latency
guarantees; see [the implementation report](../IMPLEMENTATION.md).

## Build and release pipeline

`build.zig.zon` is the project-version source; `.zig-version` pins CI/compiler
setup to 0.17.0. Official tarball downloads are checked against
`.github/zig-SHA256SUMS`. CI runs build/unit/integration/install checks on Ubuntu
and macOS. Official GitHub Actions are pinned by commit SHA.

The tag workflow validates `v<project-version>`, tests, and runs
`scripts/release.sh` for the three [release targets](installation.md#platforms).
Archives contain zman/LICENSE/README.md; raw binaries and all archive checksums
are included in SHA256SUMS. GitHub CLI publishes only after successful builds.
Hyphenated version tags are prereleases; plain version tags are stable releases.
Only the publish job has contents-write permission. Downloads occur in build
automation, never during a zman query. See [contributing](contributing.md#release-maintenance).

Non-goals include online docs, generated API explanations, package indexes,
TUI/LSP, arbitrary compiler evaluation, and language-reference/compiler-source
full-text search.

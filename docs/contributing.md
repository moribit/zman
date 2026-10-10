# Contributor guide

See [CONTRIBUTING.md](../CONTRIBUTING.md) for project principles and submission
requirements. User onboarding is in [getting started](getting-started.md).

## Setup and checks

Install Zig 0.17.0 from `.zig-version`, clone the repository, then:

```sh
zig build
zig build test
zig build integration
zig fmt --check build.zig src tests
```

Run `zig-out/bin/zman` directly during development. To check installation without
changing your usual PATH, use a temporary prefix:

```sh
zig build install --prefix /tmp/zman-install
/tmp/zman-install/bin/zman --version
```

Unit tests use small fixtures and fake manual executables. Semantic integration
uses installed official Zig autodoc against fixtures and real stdlib declarations.
CLI integration cache files live under `.zig-cache/zman-integration`.
Missing host man pages do not prevent the test suite from running.

## Where changes belong

| Area | Files |
| --- | --- |
| CLI/environment | `src/cli.zig`, `src/main.zig`, `src/environment.zig` |
| Syntax | `src/parser.zig` |
| Semantic enrichment | `src/semantic.zig`, `src/semantic/` |
| Shared data/cache | `src/index.zig`, `src/cache.zig` |
| Search | `src/search.zig` |
| Terminal/JSON | `src/render.zig`, `src/highlight.zig`, `src/style.zig` |
| Host tools | `src/pager.zig`, `src/man.zig` |
| Verification | `src/tests.zig`, `src/integration.zig`, `tests/` |

[Architecture](architecture.md) explains boundaries. Keep AST and compiler
internals out of the shared Entry/search/render/cache layers. Preserve raw source
slices and decline unsafe semantic classifications. API prose must stay official.

## Documentation changes

README is the project entrance. `docs/` describes current usage and design.
`IMPLEMENTATION.md` is a historical report, so do not replace its recorded past
output with current output. Link to current pages when historical details differ.

Capture demos from the current binary with the installed Zig version recorded.
Mark excerpts explicitly; do not invent source paths or documentation text.
Future screenshots/GIFs can go in [docs/assets](assets/README.md). Add image links
only when the file exists. Verify commands, relative links, and heading anchors.

## Release maintenance

Project version is in `build.zig.zon`; compiler pin is in `.zig-version`.
Packaging can be checked locally without publishing:

```sh
sh scripts/release.sh "v$(sh scripts/version.sh)" /tmp/zman-release
```

This builds macOS ARM64, Linux ARM64, and Linux x86_64 binaries/archives plus
SHA256SUMS. Actual publication requires pushing a matching tag and successful
release workflow. Hyphenated versions publish as prereleases. Do not push release
tags as part of an ordinary contribution.

Keep download instructions, [CHANGELOG.md](../CHANGELOG.md), and version support
accurate. The [architecture page](architecture.md#build-and-release-pipeline)
describes CI and release internals.

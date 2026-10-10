# Changelog

This records verified release and development history. Version labels below
distinguish published releases from implementation milestones.

## Unreleased

### Changed

- Reorganized README as a project landing page; moved reference/design details
  into `docs/` with installation, search, semantic, and host manual guides.
- Added contribution guidance, issue forms, PR template, and this changelog.

## [1.0.0](https://github.com/moribit/zman/releases/tag/v1.0.0)

Published stable release.

### Changed

- Added title separators, consistent section styles, aligned SEMANTICS metadata,
  compact spacing, and indented bodies; made source/version secondary information.
- Shared UI/lexer ANSI mapping while preserving source fidelity, JSON, semantic
  resolution, color overrides, and pager/editor behavior.

## 0.2.0 development / [0.2.0-beta.1](https://github.com/moribit/zman/releases/tag/v0.2.0-beta.1)

0.2.0 was an implementation version, not a published stable release.
0.2.0-beta.1 was published as a prerelease.

### Added

- Official Zig autodoc enrichment for aliases/re-exports, canonical paths,
  typical `@This()` relationships, type classification, and type factories.
- Host system manual mapping, reference output, and `zman man` execution.
- CI and tag-based prebuilt releases for three targets with checksums.

### Changed

- Updated the semantic index/cache format and centralized project versioning.

## 0.1.0 development

Unpublished Phase 1–3 implementation milestone, recorded in
[commit 44dfb83](https://github.com/moribit/zman/commit/44dfb83).

### Added

- Installed Zig environment discovery and public stdlib syntax indexing.
- Exact lookup, deterministic search, typo suggestions, and a local cache.
- Terminal rendering/highlighting, pager/editor integration, source lookup, JSON,
  build/install support, and fixture/integration tests.

Historical verification and measurements remain in [IMPLEMENTATION.md](IMPLEMENTATION.md).

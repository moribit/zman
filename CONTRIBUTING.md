# Contributing to zman

Issues and focused pull requests are welcome. Start with the
[contributor guide](docs/contributing.md) for the module map and test workflow.

## Setup

Use Zig 0.17.0 (pinned in `.zig-version`) from a checkout:

```sh
zig build
zig build test
zig build integration
```

The integration checks need the installed Zig standard library and official
autodoc sources. They do not require network access or host manual packages.

## Project principles

- Do not invent documentation or generate API explanations.
- Prefer unresolved over guessed semantic information.
- Preserve source fidelity: original signatures, doc comments, and locations.
- Keep third-party build/runtime dependencies at zero.
- Keep terminal output usable without ANSI color; preserve JSON separation.
- Use installed Zig as the source of truth. Host system manuals are a separate source.

## Pull requests

Keep changes focused and explain the problem and resulting behavior. Add
meaningful tests for behavior changes, update docs when behavior changes, and
report checks performed. For documentation-only changes, verify examples and
relative links. Before submitting:

```sh
zig fmt --check build.zig src tests
zig build
zig build test
zig build integration
```

Do not silently introduce dependency, network, semantic inference, or JSON
compatibility changes. Describe source-fidelity impact in the PR template.

## Issues

Include zman version, Zig version, OS/architecture, the command, actual output
(including stderr), and expected behavior. A small source fixture is useful for
parser/semantic bugs. Use the issue forms for reproducible bug reports or feature
proposals; [current limitations](docs/semantic-resolution.md) help define scope.

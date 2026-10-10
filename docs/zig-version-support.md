# Zig version support

The primary supported series is **Zig 0.17.x**. CI and release builds pin
**0.17.0** in [.zig-version](../.zig-version). The zman release version (currently
1.0.0) is separate from the Zig documentation version.

```sh
zig version
zman --version
```

zman runs PATH's `zig env` to discover the executable, lib/std paths, target, and
version. It supports JSON and 0.17 ZON env output without `which` or hardcoded
installation paths. Homebrew, tarball, and package layouts are discovered rather
than assumed, provided their Zig environment includes the required sources.

## Other versions

Other major/minor series are best effort. Documentation queries warn:

```text
warning: zman was developed against Zig 0.17
```

Installed Zig AST/autodoc internals are version-sensitive. A change to parsing
syntax, backend source layout, or adapter anchors can prevent enrichment.
If semantic resolution is unavailable, zman warns and retains a syntax-only
index **when syntax parsing succeeds**. Syntax incompatibility can still fail;
fallback is not a promise that every Zig version works.

`syntax_only` is shown in SEMANTICS/JSON rather than pretending semantic facts
were resolved. `zman reindex` retries the installed backend. Changes to Zig
identity and source metadata invalidate the cache.

For compatibility reports, include both versions, OS, command, stderr, and
expected behavior. See [contributing](contributing.md) and
[semantic resolution](semantic-resolution.md) for supported cases.

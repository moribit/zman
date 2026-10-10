# Search

## Exact lookup first

```sh
zman std.posix.read
zman posix.read
```

Normal lookup checks the exact public path, accepts an omitted `std.`, then checks
for a unique exact short name. Exact lookup is case-sensitive. If it cannot
select one entry, it searches instead. `zman search <query>` skips direct opening
and always shows candidates.

## Short names and ambiguity

```sh
zman read
zman allocator
```

A name shared by several declarations produces a list. `source`, `edit`, and
`man` require an unambiguous symbol; copy a public path from the results.

## Free text

```sh
zman "open file"
zman search "open file" --limit 20
```

Search uses names, official doc comments, signatures, and source paths. It folds
ASCII case and splits whitespace, punctuation, underscores, camelCase, and
PascalCase. Thus `openFile` can match `open file`, and `HTTPServer` becomes
`http server`. No embeddings, LLM, network, or external language model is used.

Ranking favors exact names and complete name-token matches, then prefixes,
documentation phrases/token matches, and weaker signature/path matches.
Complete symbol matches outrank incidental prose. Equal scores use public path
length, then lexical order, so ordering is deterministic.

With Zig 0.17, file APIs are under `std.Io.Dir`; `open file` finds
`std.Io.Dir.openFile`. Results depend on the installed Zig source.

## Typo suggestions

```sh
zman posx.read
```

Small edit-distance matches can suggest `std.posix.read`. Fuzzy matching is
limited to single-word symbol/path queries; it is not applied across arbitrary
documentation prose. Dotted-path suggestions can outrank weak prose matches;
ordinary short-name fuzzy matches rank last.

## Aliases

Known [aliases and re-exports](semantic-resolution.md) remain searchable.
Candidates that share a canonical target are grouped. An alias-specific query
can retain that public alias path; canonical previews can list related aliases.
Unresolved declarations are not grouped on guessed relationships.

See [commands](commands.md) for output limits and JSON, and
[architecture](architecture.md#search-and-rendering) for implementation boundaries.

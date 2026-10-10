# Semantic resolution

## Syntax index and semantic enrichment

The syntax index extracts public declarations, source slices, doc comments, and
locations with Zig's AST. Semantic enrichment follows declaration links and
categories from the **installed official Zig autodoc** implementation.

zman does not implement an independent Zig semantic analyzer. The backend is
structural autodoc resolution, not full compiler evaluation. A `resolved` entry
is not proof that an arbitrary standalone source fragment compiles.

## Aliases and re-exports

```sh
zman std.ArrayListUnmanaged
zman --json std.ArrayListUnmanaged
```

On Zig 0.17, `std.ArrayListUnmanaged` aliases `std.ArrayList`. Direct declaration
references, `child.X`, and `@import("child.zig").X` can be resolved using official
declaration IDs. Both the alias path and canonical public path are queryable.

Canonical selection prefers a public direct declaration, then the shortest
public path and lexical order. This is zman's deterministic presentation choice,
not a claim that the compiler assigns a unique preferred public name.
Search [groups known canonical targets](search.md#aliases).

**Source fidelity stays intact:** signature, documentation, and source location
for a resolved alias come from the original declaration. The export binding's
source/signature/docs are retained separately in JSON. No explanatory API prose
is generated or substituted.

## `@This()`

Official autodoc namespace scope supplies typical `Self = @This()` links to
the surrounding container. Private links are retained as index relationships;
private declarations do not become public lookup entries.

Links that would conflate a generic factory function with its generated type
remain unresolved. Complex comptime scopes are not inferred.

## Types, values, and type factories

```sh
zman std.ArrayList
zman std.mem.Allocator
zman std.os.linux.fd_t
zman std.math.pi
```

These demonstrate a type factory, a container type, a primitive type alias, and
a constant on Zig 0.17. Syntactic `kind` and semantic `semantic_kind` are separate
in JSON; a const binding can refer to a type without rewriting its declaration.

A function with an established literal `type` return is labeled **TYPE FACTORY**
and can show `Returns type`. Public members of a literal returned container may
be exposed when present in the official graph. Unused local containers' members
are excluded.

zman does **not** instantiate `ArrayList(u8).append`, evaluate arbitrary generic
parameters, or run an independent instantiation engine.

## Resolution states

| State | Meaning |
| --- | --- |
| `syntax_only` | No semantic enrichment was available for this index |
| `resolved` | Official structural metadata establishes the classification/link |
| `partially_resolved` | A relationship is known, but its target is not fully classified |
| `unresolved` | A safe classification or relationship could not be established |
| `cyclic` | Alias traversal found a cycle |

Conditional/computed imports, comptime-dependent namespaces, compiler-only
reflection (`@TypeOf`/`@Type`), generic instances, and ambiguous generated members
can remain unresolved. Autodoc fallback const classifications and conditional
branch heuristics are rejected when they cannot establish the requested fact.
Missing links remain missing; unknowns are preferable to invented certainty.

## JSON

Exact-result JSON keeps `name`, `kind`, `signature`, `docs`, and `source`, plus
`semantic_backend`, `semantic_kind`, `resolution`, `canonical_name`, `aliases`,
`alias_of`, `reexport_of`, `target_entry`, `member_of`, `returns_type`, `is_type`,
`is_namespace`, `alias_signature`, `alias_docs`, and `alias_source`.
`target_entry` is cache-local, not a stable cross-version identifier. Raw doc
comments keep their markers; the human renderer strips markers for readability.

If the backend fails, zman's syntax index remains usable with a warning.
`zman reindex` retries resolution. See [Zig version support](zig-version-support.md)
for compatibility and [architecture](architecture.md#semantic-backend) for adapter
and compiler-cache details.

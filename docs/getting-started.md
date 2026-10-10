# Getting started

Install [a prebuilt binary or build from source](installation.md), then make sure
both `zig` (0.17.x) and `zman` are on PATH:

```sh
zig version
zman --version
```

`zman --version` distinguishes the tool version from the installed Zig version.
Queries use your local Zig installation, without network access.

## Your first query

```sh
zman std.posix.read
```

The first query builds the index and may spend about 14 seconds compiling the
semantic helper. Progress appears on stderr. Later queries load the cache.
The display includes the symbol, semantic kind/status, original signature and
doc comments, source location, and Zig version. `zman posix.read` also works.

## Find an API

```sh
zman "open file"
zman search "open file" --limit 20
```

With Zig 0.17, `std.Io.Dir.openFile` appears near the top. A short name such as
`zman read` lists candidates when ambiguous. [Search](search.md) explains ranking
and typo suggestions.

## Read source or open your editor

```sh
zman source std.posix.read
zman std.posix.read --source
EDITOR=nvim zman edit std.posix.read
```

Source includes the declaration and surrounding lines. Resolved aliases point
to the original declaration. Editor selection also supports `ZMAN_EDITOR` and
`VISUAL`; see [commands](commands.md#editor-selection).

## Inspect an alias

```sh
zman std.ArrayListUnmanaged
```

On Zig 0.17, SEMANTICS shows `Alias of std.ArrayList` and `Returns type`.
The declaration is a type factory, not an instantiated `ArrayList(u8)`.
Read [semantic resolution](semantic-resolution.md) for the distinction.

## Follow a host system manual reference

```sh
zman std.os.linux.write --man
zman man std.os.linux.write
```

The first prints a `write(2)` reference beside the Zig documentation. The second
executes `man 2 write`. It opens the manual installed on your host, which may
differ between Linux and macOS. No manual packages are installed automatically.
See [host system manuals](system-manuals.md).

## Plain text, color, and long output

```sh
zman std.posix.read | cat
zman std.posix.read --pager=never
zman --json std.posix.read
```

Color is automatic on a TTY. Pipes, `NO_COLOR`, and `TERM=dumb` produce plain
output. Long TTY output can use your pager; JSON disables color and the pager.
The [command reference](commands.md#terminal-output) lists controls.

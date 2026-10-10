# Command reference

## Commands

| Command | Behavior |
| --- | --- |
| `zman <query>` | Exact lookup first, otherwise ranked search results |
| `zman search <query>` | Always show candidates, even for an exact name |
| `zman source <symbol>` | Declaration source plus three context lines on either side |
| `zman edit <symbol>` | Open the declaration's source file in your editor |
| `zman man <symbol>` | Print the host reference and execute `man <section> <page>` |
| `zman reindex` | Rebuild the installed Zig index; retry semantic resolution |

`source`, `edit`, and `man` require a uniquely resolved symbol. Ambiguous names
print candidates and fail instead of choosing one. An omitted `std.` prefix is
accepted. No arguments prints help. Quote multiword queries:

```sh
zman search "open file" --limit 20
zman std.posix.read --source
zman man std.posix.read --json
zman reindex --json
```

## Options

Options can precede or follow the query.

| Option | Meaning |
| --- | --- |
| `--json` | Structured output; disables ANSI and zman's pager |
| `--source` | Append source context to a normal exact lookup |
| `--man` | Include the host system manual reference; does not execute `man` |
| `--limit N` | Maximum search results, default 10; accepted range 1–1000 |
| `--color=auto\|always\|never` | Color mode, default auto |
| `--color` | Shorthand for always |
| `--no-color` | Shorthand for never |
| `--pager=auto\|always\|never` | Pager mode, default auto |
| `--version` | Show zman version and installed Zig documentation version |
| `--help` | Show usage and examples |

`--source` and `--man` are presentation options for exact results, not search
lists. They do not alter JSON. Exact-result JSON already includes an available
system manual reference. `zman man <symbol> --json` never starts `man`.
`--limit=20` and `--pager always` are not accepted; use the forms above.

## JSON

Exact results contain original `signature`, raw `docs` comment markers, `source`
path/line/byte range, syntactic `kind`, and semantic metadata. Search returns
`zig_version`, `query`, and a `results` array. Reindex JSON reports entry and
semantic counts. These are different result shapes; do not assume every command
returns one declaration. See [semantic resolution](semantic-resolution.md#json).

## Terminal output

Color auto requires stdout to be a TTY. Explicit `--color=always` allows redirected
ANSI, but **NO_COLOR and TERM=dumb still override it**. Plain layout retains title
separators, section headings, and metadata alignment. Only code is syntax
highlighted; documentation paragraphs remain ordinary text.

Pager priority is `ZMAN_PAGER`, `PAGER`, then `less -R`. If spawning a pager fails,
output falls back to stdout. A pager that exits unsuccessfully reports a failure.
Auto uses a pager when TTY output exceeds 40 lines; always still requires a TTY.
Redirects and pipes bypass the pager. User-specified pager options are respected.
Host `man` has its own pager/formatting behavior.

## Editor selection

Selection order: `ZMAN_EDITOR`, `VISUAL`, `EDITOR`.

```sh
EDITOR=nvim zman edit std.posix.read
ZMAN_EDITOR='code --reuse-window' zman edit std.posix.read
```

vi/vim/nvim receive `+<line>` and the file; code receives `--goto file:line`.
Unknown editors receive only the file path. Pager/editor commands support quoted
argv and backslash escaping. They are never evaluated by a shell; pipelines,
variables, glob expansion, and command substitution are not supported.

## Errors and cache

Missing Zig, missing stdlib/source, invalid arguments, no matches, ambiguity,
and editor/man failures are reported on stderr. A failed semantic backend warns
and retains syntax lookup. An invalid or corrupt cache is rebuilt automatically.
Use `zman reindex` after an intentional source change; cache locations and
invalidation are described in [architecture](architecture.md#cache).

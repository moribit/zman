# Host system manuals

Zig documentation and host system manuals are separate sources. A reference
connects a Zig API to a related manual; it does not replace Zig's signature or
doc comments with a manual's prose.

## Show a reference or open a page

```sh
zman std.os.linux.write --man
zman man std.os.linux.write
```

`--man` adds this section to the normal documentation and never opens `man`:

```text
SYSTEM MANUAL
  Host page   write(2)
  Relation    direct
```

`zman man` prints the reference and executes `man 2 write` as argv, without a
shell. It requires an exact or unique symbol and an explicit mapping.

## Direct and related

Mappings are a fixed table, not inferred from API names or descriptions.
`direct` connects a wrapper/declaration to its corresponding manual page.
`related` indicates a relevant host API without asserting equivalent behavior.
For example, `std.Io.Dir.openFile` has a **related** `open(2)` reference.

The current table contains 55 symbol mappings:

| Namespace | Mappings | Examples |
| --- | ---: | --- |
| `std.posix` | 23 | read, openat/openatZ, poll/ppoll, mmap, signals |
| `std.os.linux` | 19 | open/read/write/close, epoll, sockets |
| `std.c` | 12 | open/read/write/close, poll, sockets |
| `std.Io.Dir` | 1 | openFile → related open(2) |

Most use section 2; `std.posix.tcgetattr` and `tcsetattr` use section 3.
The exact list lives in [src/man.zig](../src/man.zig).

Zig 0.17 no longer exports the earlier `std.posix.open/write/close/socket/...`
or posix epoll wrappers. zman indexes actual installed declarations, so use
the available `std.os.linux` or `std.c` paths instead. A mapping never creates
a nonexistent Zig API.

## Your host determines the manual

macOS normally supplies Darwin manuals; Linux supplies the installed manuals
for that system. Looking up `std.os.linux.write` on macOS can still open the
host's Darwin `write(2)`. This is why output says **Host page**: it does not
promise Linux manual content or that a page is installed.

Host `man` controls its own formatting and pager. zman's `--pager` applies to
zman's documentation output, not the manual program.

## Missing tools and pages

- Missing executable: `error: man command not found`.
- Missing page: `error: manual page write(2) is not installed on this host`.
- Missing mapping: `error: no explicit system manual mapping for this symbol`.

Other process failures are reported separately. Reference display still works
without `man`. zman does not install packages or download manual content.

## JSON

```sh
zman --json std.os.linux.write
zman man std.os.linux.write --json
```

Exact-result JSON includes the available `system_manual` object with `page`,
`section`, and `relation` (or null when unmapped). JSON never invokes `man`,
regardless of `--man` or the `man` command.
See [commands](commands.md) for the other output modes.

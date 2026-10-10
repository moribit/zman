# Phase 1–3 完了報告

検証環境: Zig 0.17.0 / macOS aarch64。本文の説明はすべてインストール済み Zig の source/doc comment から抽出し、独自生成していません。

## 1. 最終構成

```text
zman/
├── .gitignore
├── README.md
├── LICENSE
├── IMPLEMENTATION.md
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig
│   ├── cli.zig
│   ├── environment.zig
│   ├── index.zig
│   ├── parser.zig
│   ├── search.zig
│   ├── render.zig
│   ├── highlight.zig
│   ├── pager.zig
│   ├── cache.zig
│   └── tests.zig
└── tests/
    ├── std.zig
    └── child.zig
```

## 2. 実際の exact lookup 出力

```text
std.posix.read

function

SIGNATURE

pub fn read(fd: fd_t, buf: []u8) ReadError!usize

DESCRIPTION

Returns the number of bytes that were read, which can be less than
buf.len. If 0 bytes were read, that means EOF.
If `fd` is opened in non blocking mode, the function will return error.WouldBlock
when EAGAIN is received.

Linux has a limit on how many bytes may be transferred in one `read` call, which is `0x7ffff000`
on both 64-bit and 32-bit systems. This is due to using a signed C int as the return value, as
well as stuffing the errno codes into the last `4096` values. This is noted on the `read` man page.
The limit on Darwin is `0x7fffffff`, trying to read more than that returns EINVAL.
The corresponding POSIX limit is `maxInt(isize)`.

SOURCE

/Users/mimoc/.zvm/0.17.0/lib/std/posix.zig:402

ZIG VERSION

0.17.0
```

上記 path は検証環境での実出力です。実装にはハードコードしていません。

## 3. `open file` 上位結果

```text
1. std.Io.Dir.openFile
   function
   Opens a file for reading or writing, without attempting to create a new file.

2. std.Io.failingDirOpenFile
   function

3. std.Io.Dir.OpenFileOptions
   struct

4. std.Io.Dir.openFileAbsolute
   function

5. std.Build.Cache.Path.openFile
   function
```

この Zig 0.17 の file API は `std.Io.Dir` にあります。旧 `std.fs.Dir.openFile` を捏造・補完しません。

## 4–6. Parser、namespace、doc comment

- `std.zig.Ast.parse` / `fullFnProto` / `fullVarDecl` / `fullContainerDecl` を使用。
- `std.zig.Tokenizer` は環境の ZON 出力、container docs、syntax highlighting に使用。環境が JSON なら `std.json` で parse。
- `std.zig` を root とし、`pub` 宣言、直接 literal `@import`、inline container の public 宣言を再帰追跡。ファイル名から公開 namespace を生成しません。
- import の active-path cycle を遮断し、path+namespace の訪問済み集合で重複処理を抑制。stdlib 外の import は展開しません。
- signature は source slice。function body を除外。inline container は keyword までの source slice を表示し、完全な宣言は source command で取得。
- `///` の連続 token を宣言に関連付けて原文保持。import namespace に declaration docs がなければ imported file 冒頭の `//!` を保持。
- fully-qualified/short name、kind、pub visibility、signature、docs、file、line、byte start/end を保持。AST 型は parser 外に漏らしません。
- 実環境では 16,501 宣言を index 化。

## 7. Ranking

ASCII lowercase、空白/punctuation/underscore、camelCase、PascalCase/acronym の境界で tokenize。

基本 score: fq exact 10000、short exact 9000、short の全 token 8000、fq の全 token 7000、prefix 6500、docs phrase 3000、docs 全 token 2500、docs 部分一致 100/token、signature 80、source path 40。

Dotted symbol typo は Levenshtein 距離 1–2 の候補を 5000-distance とし、prose より優先。通常 short-name fuzzy は最下位 20-distance。dotted typo に近似候補があるときは近似候補のみ表示。`posx.read` → `Did you mean: std.posix.read` を確認済み。

同 score は fq path の長さ、続いて lexical order。結果の上限は標準 10、`--limit` で変更。完全一致は search に先行し、short exact が複数なら候補表示。

## 8. Highlight

source bytes → `std.zig.Tokenizer` → token tag → 基本 ANSI color。
keywords、identifier、builtin、string/char、number、doc comment、punctuation と `std.zig.primitives.isPrimitive` で明確な primitive を区別。Tokenizer が省く通常 `//` comment は token 間の gap で色付け。DESCRIPTION の文章には lexer を適用しません。

TTY auto、`NO_COLOR`、`TERM=dumb`、color flags、plain pipe、JSON の ANSI 無出力を検証。明示 always のみ redirect にも色を許可し、NO_COLOR/TERM=dumb は常に優先。

## 9. Cache

checksum 付き JSON envelope。`ZMAN` marker、format version 1、Wyhash checksum。payload に identity と entries/file metadata。

identity: Zig version + executable path + stdlib path + target。起動時に traversed source 全件の size/mtime を検証。format/identity/metadata 不一致、parse 不良、checksum 不良なら rebuild。実際に test cache を壊し、次回 query が再生成することを検証。

XDG_CACHE_HOME 優先、macOS は HOME/Library/Caches、Linux は HOME/.cache。HOME がなければ無 cache。write failure は warning のみ。`reindex` で明示再生成。cache は約 7.8 MiB。

ownership: index と cache decode は process lifetime の arena。検索の scratch arena は entry ごとに capacity を再利用し、結果 allocation は明示 free。

cache write は現在直接 write。複数プロセス同時 write では次回 rebuild が起こり得ます。content が同じ size/mtime に人為的に戻されたケースは検知しません。

## 10. Pager / editor

TTY で 40 行超なら auto pager。ZMAN_PAGER → PAGER → `less -R` → stdout。ユーザー指定 options は変更しません。quoted argv lexer を通し、shell は起動しません。

TTY で custom `cat`、存在しない pager の stdout fallback を確認。pager 非ゼロ終了は簡潔な error。pipe/JSON は pager なし。

Editor は ZMAN_EDITOR → VISUAL → EDITOR。vi/vim/nvim は +line、code は --goto path:line、その他は path。`/usr/bin/true` を test editor として実起動確認。エディタ UI そのものの操作検証は行っていません。

## 11. Install

```sh
zig build -Doptimize=ReleaseSafe
zig build install -Doptimize=ReleaseSafe --prefix ~/.local
~/.local/bin/zman --version
```

実際の検証は `/tmp/zman-install` に install。出力:

```text
zman 0.1.0
Zig docs: 0.17.0
```

ユーザーの ~/.local には配置していません。prebuilt 用の target 設定に対応していますが、Release 公開/CI 自動化は未実装。

## 12. Cross compile

| Target | 結果 |
|---|---|
| x86_64-linux | ReleaseSafe compile 成功、静的 ELF |
| aarch64-linux | ReleaseSafe compile 成功、静的 ELF |
| aarch64-macos | ReleaseSafe compile/install/実行成功、Mach-O arm64 |

Linux はこの macOS 環境では実行せず compile のみ確認。外部 C library/build package は追加していません。

## 13. Verification

- `zig build`: 成功。
- `zig build test`: **7/7 passed**。小 fixture の public function/const/var、struct/enum、nested declaration、imports、/// と //!、plain golden、ANSI categories、search tokenizer/ranking/fuzzy、cache roundtrip/invalidation/corruption、argv quoting。
- `zig build integration`: **9/9 build steps succeeded**。installed Zig に対する version/exact/prefix/ambiguous read/free text/source/JSON を実行。
- version、std.posix.read、posix.read、read、open file、allocator、ArrayList、std.Io、source、JSON、posx.read を個別実行し exit/output を確認。
- `zman std.posix.read | cat`: ANSI 無出力。
- PTY 経由の auto-color、custom pager/fallback、NO_COLOR、JSON と強制 color/pager の組合せを確認。
- ReleaseSafe 実測: cold index+lookup 約 439 ms、cached exact 約 75 ms、cached search 約 100–108 ms。環境・OS cache に依存する参考値。
- sandbox 検証時は Zig global cache と zman cache を /tmp へ向け、通常ユーザー cache への write を避けました。

## 14–15. 現在の制約と Phase 4

正しく展開できないもの:

- 他宣言への alias/re-export (`pub const X = child.X`) の先にある namespace。
- conditional/computed import、`@This()` alias、comptime namespace expression。
- 関数が返す生成型の members（例: parameterized container）。関数自身と docs は index 化。
- enum value / container field は public declaration entry として index 化しない。
- binding が実際に型かどうかの semantic 判定。syntax 上 const なら const と表示し、推測しない。
- inline container 内の `//!` 単独 docs は parent entry に統合しない。

Phase 4 で compiler/autodoc の semantic 情報を利用する場合、alias の canonical/public path、conditional target selection、generic instantiated type の public members、宣言参照リンク、type 判別と container docs の対応付けが主な対象です。現在の source slices・位置情報・独立した Entry モデルを維持できます。

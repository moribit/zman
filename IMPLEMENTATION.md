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

---

# Phase 4 implementation report — 0.2.0

## Semantic (1–10)

1. **Official backend:** installed Zig 0.17.0 の `lib/compiler/std-docs.zig`、`lib/docs/wasm/Walk.zig`、`Decl.zig` を調査しました。公式 [0.17.0 source archive](https://ziglang.org/download/0.17.0/zig-0.17.0.tar.xz) の `src/Compilation.zig` / `src/main.zig` も確認。`zig std` と `-femit-docs` は同じ autodoc backend を利用し、後者は HTML/JS/WASM/source archive を出力します。独立した full-semantic JSON export はありません。インストール済み backend の bytes は公式 archive と一致し、archive SHA256 は公式 [download index](https://ziglang.org/download/index.json) と照合しました。
2. **Integration:** `semantic.zig` が syntax index を enrich します。source に埋め込んだ native driver を installed Zig でコンパイルし、installed Walk/Decl を実行。allocator を native arena に置換し、再帰 guard を追加しました。shipped `Decl.get_type_fn_return_expr` の古い `.node` accessor は 0.17 AST の `.opt_node.unwrap()` に合わせています。exact source anchor の一致を要求し、分類/lookup の公式ルールは変更していません。neutral protocol → Entry の境界で AST/autodoc 型を隔離。backend 不在、不一致、parse/compile failure は警告して syntax-only に fallback します。
3. **Aliases/re-exports:** official declaration ID / alias target を辿ります。`child.X`、`@import("child.zig").X`、namespace binding を fixture で確認。alias query の signature/docs/source は元宣言へ移り、alias binding は `alias_signature` / `alias_docs` / `alias_source` に保持します。
4. **Canonical:** official std root の public edges から export path を構築。元の public direct declaration を優先し、次に最短 path、lexical 順で決定。filename を public namespace と見なしません。alias path も exact lookup 可能で、検索結果は canonical target 単位に重複排除します。
5. **Cycles:** official traversal に file/node/operation/child-name の recursion stack guard、alias chase に visited IDs を使用。実 cycle は `cyclic`、深さ上限到達は `unresolved`。export traversal に ancestor/depth/entry cap。A→B→C→A と cyclic field access の fixture が成功し、無限再帰しません。
6. **`@This()`:** official namespace scope が提供する alias link を採用。public `DirectType.Self` と private `Foo.Self` を確認。private link は source locations を持つ `relationships` に保存。generic factory 内で Self を function 自体へ誤リンクする場合は unresolved にします。
7. **Type/const:** official category を別 `semantic_kind` として保持。primitive type alias、container type、literal constant、function/namespace を分類。autodoc の fallback const、conditional branch の heuristic を採用できない場合は unknown/unresolved。source syntax の `kind` は互換性のため保持します。
8. **Generic:** literal `type` return を official type-function category と併せて `TYPE FACTORY` / `returns_type=true` と表示。literal returned container に属する public members のみ公開します。unused local container の `phantom` member を除外する回帰テストを追加。任意 instantiation engine はありません。
9. **Real stdlib:** `std.ArrayList` = type factory、`std.ArrayListUnmanaged` → `std.ArrayList` alias、`std.mem.Allocator` = type、`std.os.linux.fd_t` = primitive type alias、`std.math.pi` = constant、`array_list.zig` の private Self links、`std.posix.read` の原文 signature を実際の installed stdlib で検証。macOS と Linux の双方で成功しました。
10. **Limitations:** official autodoc は構造的 resolution であり full compiler semantic evaluation ではありません。conditional/computed imports、reflection/comptime-dependent expressions、generic instantiated members、複雑な `@This()`、opaque fallback classifications は未解決を優先。`ArrayList(u8).append` は評価しません。source parse はできても compiler として invalid な fixture を semantic proof として扱いません。

## System man (11–16)

11. **Mapping:** `man.zig` の明示 table で direct/related、page、section を管理。AI 推論、外部 database、shell concatenation はありません。Zig docs と host system manual は別 source として表示します。
12. **Coverage:** 55 mappings、うち実際に存在する `std.posix` API は 23。Zig 0.17 の `std.posix` には open/write/close/socket/bind/listen/accept/connect/send/recv/epoll がありません。存在しない Zig path を捏造せず、`std.os.linux` の 19 syscall paths、`std.c` の 12 paths、related `std.Io.Dir.openFile` を併記しました。23 posix entries の存在は integration test で保証します。
13. **`--man` actual output (excerpt):**

    ```text
    ZIG DOCUMENTATION

    std.posix.read

    FUNCTION

    RESOLUTION

    resolved (Zig autodoc)

    SIGNATURE

    pub fn read(fd: fd_t, buf: []u8) ReadError!usize

    SOURCE

    /Users/mimoc/.zvm/0.17.0/lib/std/posix.zig:402

    SYSTEM MANUAL

    System manual on this host:
        read(2) [direct]
    ```

    DESCRIPTION には stdlib の原文 doc comments が表示されます。上記は省略表示で、独自生成した説明はありません。
14. **Execution:** `zman man std.posix.read` は argv `man`, `2`, `read` を spawn。`--man` は reference 表示だけ。JSON は system_manual metadata のみで man を起動しません。
15. **Host difference:** 最終 ARM64 release binary で macOS の Darwin READ(2) と Fedora 44 の Linux man-pages 6.13 read(2) を実際に開き、正常終了しました。Linux 版 manual と断定せず「on this host」と表示します。
16. **Missing command/page:** FileNotFound は `man command not found`、exit 1/16 は `manual page read(2) is not installed on this host`、その他は concise failure。fake executable による argv、missing command、missing page tests は host man の存在に依存しません。package install は行いません。

## Release (17–23)

17. **CI:** `.github/workflows/ci.yml` は push/PR、Ubuntu 24.04/macOS 15、build/test/integration/temp install。`.zig-version` の 0.17.0 を公式 tarball と pinned SHA256 で setup。GitHub 公式 Actions は commit SHA pin、checkout credentials は保存しません。
18. **Release:** `.github/workflows/release.yml` は v* tag、tag validation → tests → cross build → upload → publish。publish job だけ contents:write。公式 upload/download-artifact と GitHub CLI を利用。[GitHub hosted runners に gh が入っていること](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-github-cli) を確認しました。自動 notes は platform download list と checksum 案内。今回 tag push/Release publish は行っていません。
19. **Targets:** aarch64-macos、aarch64-linux、x86_64-linux。最終 ReleaseSafe build は全 target 成功。`file` で Linux 両 binary の statically linked ELF を確認。ARM64 macOS/Linux は実行、Linux x86_64 は compile のみ。
20. **Assets:** `zman-v0.2.0-<target>.tar.gz` と同名 raw binary。archive 内容は zman/LICENSE/README.md のみ。macOS AppleDouble が混入しないよう COPYFILE_DISABLE を指定。macOS binary は Developer ID signing/notarization 未対応です。
21. **Checksums:** SHA256SUMS は 3 archive + 3 raw binary 全てを含みます。全 checksum と archive entries をローカル検証。`scripts/release.sh` を同じ output directory へ再実行して成功しました。
22. **Install:** README の download/extract/checksum/`mkdir -p ~/.local/bin`/`install -m 755` 手順。source は `zig build -Doptimize=ReleaseSafe`、`zig build install --prefix ~/.local`。実検証は `/tmp/zman-phase4-install` へ install し `zman 0.2.0 / Zig docs: 0.17.0` を確認。
23. **Version:** build.zig.zon の 0.2.0 が single project-version source。build options 経由で CLI version、scripts/version.sh 経由で archive/tag validation。v9.9.9 の negative test は build 前に拒否。Zig version は `.zig-version` に分離。

## Quality / measurements (24–30)

24. **Tests:** `zig build` 成功。`zig build test` は macOS/Fedora とも **13/13 passed**。alias/cycle/unknown、highlight/plain golden、search、cache corruption/old format、CLI flags、fake man argv/failure を含みます。`zig fmt --check` と diff whitespace check も実施。
25. **Integration:** macOS/Fedora とも **16/16 build steps succeeded**。semantic fixture と real installed Zig stdlib、11 CLI invocations。plain pipe に ANSI なし、PTY auto color、NO_COLOR、JSON/man non-execution、alias type factory も最終 binary で確認。YAML parse、shell syntax check 成功。GitHub hosted workflow 自体は未実行です。
26. **Cross compile:** 3 target 成功。Mac と Fedora の host-specific man 起動も確認。runtime の network access は利用していません。
27. **Cache / memory:** 同じ macOS ARM64 host と Zig source に対する比較です。

    | Metric | Phase 3 (0.1.0) | Phase 4 (0.2.0) |
    | --- | ---: | ---: |
    | Public index entries | 16,501 | 20,833 |
    | Index cache bytes | 8,161,438 (7.78 MiB) | 14,633,177 (13.96 MiB) |
    | Official declaration facts | — | 37,803 |
    | Alias edges (incl. private) | — | 4,568 |
    | Public alias paths | — | 1,956 |
    | Resolved entries | — | 17,328 |
    | Partially resolved | — | 86 |
    | Unresolved | — | 3,419 |
    | Cyclic public entries | — | 0 (fixture tests cycles) |
    | Cached lookup maximum RSS | 66,994,176 bytes | 43,630,592 bytes |

    Format 2 は `ZMAN\n2\n<Wyhash>\n<JSON payload>`。format/identity/checksum 不一致と破損は rebuild。version/executable/std path/target/adapter content revision/backend source metadata を identity に含め、読み込んだ source files と directories の size/mtime で invalidate。atomic temp rename。mtime/size を意図的に維持した編集を cryptographic content scan で検出する方式ではありません。native helper/compiler cache は別 storage で、上記 index size には含めません。cache JSON の二重 envelope を廃止し arena が input slices を保持するため、index が増えても cached RSS は低下しました。
28. **Benchmark:** ReleaseSafe binary、5 runs の median、同じ host/source/既存 cache、subprocess wall time（OS cache や負荷で変動）。

    | Query | Phase 3 | Phase 4 |
    | --- | ---: | ---: |
    | std.posix.read | 75.7 ms | 73.3 ms |
    | open file | 98.9 ms | 103.2 ms |

    helper 初回 compilation を含む reindex は約13–17秒、既存 helper で最終 reindex は0.712秒。cached query は compiler/helper を起動しません。最終 `open file` の1位は `std.Io.Dir.openFile`、続いて `std.Io.failingDirOpenFile`、`std.Io.Dir.OpenFileOptions`。query engine は引き続き deterministic ranking です。
29. **Dependencies:** Zig stdlib のみ、third-party/build/runtime library dependency は0。libc link なし、SQLite/PCRE/tree-sitter/WASM runtime なし。index rebuild は PATH の installed Zig compiler を使用。man/pager/editor は optional external host tools、通常の lookup に必須ではありません。release/CI の compiler download は build automation のみに限定。
30. **Phase 5 candidates:** compiler が安定した machine-readable semantic/autodoc export を提供した場合の backend、comptime-dependent target の official evaluation、既存 compiler metadata が提供する generic instances、より詳細な relationship browsing、man mapping 拡充、macOS signing/notarization。独自 semantic analyzer やネットワーク document retrieval は今回導入していません。

---

# 1.0.0 — Terminal visual hierarchy

## Architecture and visual roles

`render.zig` に小さな HumanRenderer を置き、title/section/body/metadata/manual の配置を統一しました。JSON renderer と semantic index は変更していません。`man.zig` の human formatting は renderer へ移し、mapping と process execution は維持しています。

`style.zig` が UI と lexer の Role → ANSI mapping を集約します。新規 UI accent は cyan 1色です。

| Role | ANSI | Usage |
| --- | --- | --- |
| title / section | bold cyan (`1;36`) | symbol、全 section headings |
| kind | bold (`1`) | TYPE FACTORY / FUNCTION 等 |
| metadata_key / secondary | dim (`2`) | Status 等の label、separator、source path、version |
| symbol / builtin | cyan (`36`) | alias reference、host page、builtin/type-like tokens |
| keyword | magenta (`35`) | 既存 Zig syntax |
| literal / number | green (`32`) / yellow (`33`) | 既存 Zig syntax |
| comment / identifier / punctuation | gray (`90`) / default (`39`) / blue (`34`) | 既存 Zig syntax |

`RESOLUTION` を `SEMANTICS` とし、12-column key width で整列。backend名は通常 status から除き、既存JSONへ保持。title の下に byte length 分の Unicode separator。section 間は1空行、heading と body の間は空行なし、body は2-space indent。doc の段落と原文は維持し、prose / inline backticks は色付けしません。source/version は secondary。`--man` は SOURCE の前に Host page / Relation を表示し、host の manual と Zig doc を区別します。

`Returns` は既存 `returns_type=true` の場合にだけ表示します。`std.os.linux.write` の `usize` を新たな semantic metadata として推測・生成していません。manual reference の表示は既存 `--man` flag を維持し、通常の write lookup では自動追加しません。

## Actual plain output

### `zman std.ArrayListUnmanaged`

```text
std.ArrayListUnmanaged
──────────────────────

TYPE FACTORY

SEMANTICS
  Status      resolved
  Alias of    std.ArrayList
  Returns     type

SIGNATURE
  pub fn ArrayList(comptime T: type) type

DESCRIPTION
  A contiguous, growable list of items in memory. This is a wrapper around a
  slice of `T` values.

  The same allocator must be used throughout its entire lifetime. Initialize
  directly with `empty` or `initCapacity`, and deinitialize with `deinit` or
  `toOwnedSlice`.

SOURCE
  /Users/mimoc/.zvm/0.17.0/lib/std/std.zig:52

ZIG VERSION
  0.17.0
```

### `zman std.os.linux.write`

```text
std.os.linux.write
──────────────────

FUNCTION

SEMANTICS
  Status      resolved

SIGNATURE
  pub fn write(fd: fd_t, buf: [*]const u8, count: usize) usize

DESCRIPTION
  No Zig documentation attached.

SOURCE
  /Users/mimoc/.zvm/0.17.0/lib/std/os/linux.zig:1787

ZIG VERSION
  0.17.0
```

`--man` を付けると同じ layout の SYSTEM MANUAL に `Host page   write(2)` と `Relation    direct` が加わります。

### `zman std.posix.read --man`

```text
std.posix.read
──────────────

FUNCTION

SEMANTICS
  Status      resolved

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

SYSTEM MANUAL
  Host page   read(2)
  Relation    direct

SOURCE
  /Users/mimoc/.zvm/0.17.0/lib/std/posix.zig:402

ZIG VERSION
  0.17.0
```

## Verification

- `zig build`: succeeded。
- `zig build test`: **14/14 passed**（既存13 + hierarchy/golden/ANSI boundary test）。alias と manual の plain golden を追加し、ANSI を除去した結果と同一であることも確認。
- `zig build integration`: **16/16 steps succeeded**。既存 semantic fixture / installed stdlib assertions を維持。
- PTY で ArrayListUnmanaged / ArrayList / os.linux.write / posix.read --man の4例を確認。title/section/key/syntax/source の style boundary と prose の通常色を検証し、ANSI 除去後は plain と一致。
- redirect auto、`--color=never`、`NO_COLOR`、`TERM=dumb` は ANSI なし。`--color=always` は redirect でも ANSI あり。NO_COLOR/TERM=dumb は always より優先。実際の `zman std.posix.read | cat` も ANSI なし。
- 同じ cache/source を使用した公開 beta と4例の JSON を byte-by-byte 比較して一致。signature/doc comments/canonical source locations、backend metadata、schema を維持。
- PTY の JSON + forced color/pager も ANSI なし、fake pager の marker が作成されず、pager 非実行を確認。
- custom pager (`cat`) の PTY 出力、fake editor の source path argv、source command の plain 出力が beta と byte-identical、source highlight の維持を確認。
- ReleaseSafe cross compile: aarch64-macos / aarch64-linux / x86_64-linux succeeded。3 archives の entries と全6 assets の checksum を検証。CLI version は `zman 1.0.0`。
- `zig fmt --check`、`git diff --check` を実施。新規 dependency は0。semantic backend/search ranking/cache format/JSON fields は変更していません。

## Changed files / release

`src/style.zig`、`src/render.zig`、`src/highlight.zig`、`src/main.zig`、`src/man.zig`、`src/tests.zig`、`tests/golden/alias.txt`、`tests/golden/manual.txt`、`README.md`、`IMPLEMENTATION.md`、`build.zig.zon`。

project version は1.0.0。ユーザーの確認により「pushせず」より正式公開を優先し、commit と v1.0.0 tag を push して既存 release workflow を使用します。ハイフンなしのタグは prerelease flag を付けず stable release を作成します。commit SHA と公開後の CI/Release 結果は最終報告に記載します。

# pdfTeX バックエンド用 JFM データの生成（M3）

`jfm-jlreq.lua`（単一ソース）から、pdfTeX バックエンド
（`jlreq-pdftex.sty`）が実行時に直接読み込む JFM データを生成する。
PLAN.md §3.3・§5 M3・§10.1 参照。

## 成果物

| ファイル | 役割 |
|---|---|
| `make_pdftex_jfm.lua` | 生成器（ビルド時のみ、texlua で実行） |
| `jlreq-pdftex-jfm.def` ほか4種 | 生成データ（コミット済み・実行時に必要） |
| `check_jfm_pdftex.lua` | 静的検証器（全ペア・全クラス・全文字を検査） |

### バリアントとファイル名

`jlreq.cls` の JFM 名接頭辞システム（`jlreq.cls:507-514`: `b`=ぶら下げ、
`z`=`zenkakunibu_nibu`）に合わせ、4 バリアントを別ファイルとして
生成する（`u`=upTeX は pdfTeX には存在しない）。

| ファイル | open_bracket_pos | burasage | 接頭辞の対応 |
|---|---|---|---|
| `jlreq-pdftex-jfm.def` | `zenkaku_tentsuki` | false | （既定） |
| `jlreq-pdftex-jfm-b.def` | `zenkaku_tentsuki` | true | `b` |
| `jlreq-pdftex-jfm-z.def` | `zenkakunibu_nibu` | false | `z` |
| `jlreq-pdftex-jfm-bz.def` | `zenkakunibu_nibu` | true | `bz` |

`nibu_tentsuki` は有効なクラスオプションだが接頭辞を持たず、生成
テーブルも既定と異なる（90→1 グルー −0.5。`jfm-jlreq.lua:1161-1162`）。
よって本生成器ではバリアントファイルを設けず、明示的に拒否する。

### バリアントの意味（`jfm-jlreq.lua:1141-1172`）

- `zenkakunibu_nibu`（`z`）: クラス 1（開き括弧）の幅 +0.5、全クラス
  →1 グルー −0.5（ratio は `add_space` が再配合）、90→1 は +0.5 で
  相殺し `{0,0,0}` ratio 1.5。
- ぶら下げ（`b`）: クラス 6, 7（句読点）の `end_adjust` に −0.5 を
  追加しソート（`{-0.5, 0, 0.5}`）。

## ビルドと検証

```sh
make pdftex-jfm            # 4 ファイル生成（決定的）
make check-pdftex-jfm      # 再生成してコミット済みファイルと cmp、
                           # check_jfm_pdftex.lua で全検証
texlua check_jfm_pdftex.lua [file.def ...]   # 静的検証のみ
```

- 決定性: ソート済みキー、`%.6f` 固定小数、タイムスタンプなし。
  2 回の実行はバイト一致（`make check-pdftex-jfm` が検査）。
- `.def` をコミットする理由: pdfTeX 実行時に必要で、利用者は texlua
  を持つとは限らない（PLAN §10.1「リポジトリまたは配布物に同梱」）。
  既存の `.tfm`/`.vf` はインストール時ビルドのためコミットしない。
- 各 `.def` ヘッダに `jfm-jlreq.lua` の SHA256 と生成器バージョン、
  バリアントオプションを記録し、追跡可能性を確保。

## 直列化形式

- 定義はすべて `\expandafter\def\csname jlreqpdf@jfm@…\endcsname{…}`。
  理由: 数字を含むマクロ名（`class@0`、`cls@AB` 等）は素の
  `\def\foo@0{…}` では `0` がパラメタテキストの区切りになるため。
- 本体は 1 グループ、複数フィールドは内部グループ `{a}{b}…`。
- マクロファミリ: `dir/zw/zh/version/variant/kanjiskip/xkanjiskip`、
  `class@<n>{{w}{h}{d}{align}{left}}`、`endadj@<n>`、`chars@<n>`、
  `cls@<hex>`（単一代理点）、`combo@<n>`、`ajone@<n>`、
  `pseudo@<name>`、`pair@<f>@<t>{{nat}{str}{shr}{ratio}{spri}{shpri}{knat}{kstr}{kshr}}`。

## 実行時読込契約（バックエンド向け）

1. `\makeatletter`（catcode `@` = 11）を `\input` の前に発行。
   ファイルは catcode を復元しない。
2. 標準 catcode のみで成立（expl3 でも素の TeX でも読込可）。
3. 数字を含む名前の値参照は `\csname` + `\edef` で展開して取得する
   （LaTeX2e の `\typeout` は `\csname` 参照を展開しない。
   `poc/m3-loadtest.tex` で実証済み）。

## データ規模（2026-07-17 版 `jfm-jlreq.lua`）

- クラス 25 個（0,1,2,4–16,27,90,161,191,192,193,300,301,302）
- ペア規則 402 条（全定義ペア。未定義セルは不発行）
- 文字 403 エントリ = 356 単一代理点 + 14 コンボ + 30 AJ1 グリフ
  + 3 疑似（`alchar`, `parbdd`, `boxbdd`）
- `end_adjust` はクラス 2, 5, 6, 7 にのみ存在

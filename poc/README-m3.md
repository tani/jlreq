# M3 PoC: JFM → expl3/consumable `.def` 生成器

PLAN.md §3.3・§12-4 の技術実証。`jfm-jlreq.lua`（単一ソース）から
pdfTeX 実行時に直接読める文字クラステーブル・ペアグルー規則を生成する。

## ファイル

| ファイル | 役割 |
|---|---|
| `make_pdftex_jfm.lua` | 生成器（texlua 実行、決定的出力） |
| `jlreq-pdftex-jfm-sample.def` | 生成物のサンプル（PoC サブセット） |
| `m3-verify.lua` | 検証器：被覆・ペアバイト照合・メトリック検査 |
| `m3-loadtest.tex` | pdfLaTeX 実行時読込テスト |

## 実行方法（poc/ ディレクトリから）

```sh
# 生成（決定性: 2 回実行して cmp で一致確認済み）
texlua make_pdftex_jfm.lua --open-bracket-pos=zenkaku_tentsuki --burasage=false jlreq-pdftex-jfm-sample.def

# 静的検証（ALL CHECKS PASSED で終了）
texlua m3-verify.lua

# 実行時読込テスト（rc=0, ログに M3LOAD| 行が 22 行出る）
pdflatex -interaction=nonstopmode -output-directory=/tmp/m3v m3-loadtest.tex
grep '^M3LOAD' /tmp/m3v/m3-loadtest.log
```

注意: TEXINPUTS を上書きしないこと（デフォルトにカレントディレクトリ
を含む。`.:` 等の指定は kpathsea の既定ツリー検索を壊す）。

## 生成されるデータ（既定バリアント zenkaku_tentsuki / burasage=false）

- クラス 25 個（0,1,2,4–16,27,90,161,191,192,193,300,301,302）
- 文字ディスパッチ 356（単一代理点）+ コンボ 14 + AJ1 グリフ 30 + 疑似 3
  = 403 エントリ（全クラス被覆、重複なし・検証済み）
- ペア規則 49 条（PoC サブセット {0,1,2,4,5,6,7}² の閉包 + 90→1）。
  JFM 全定義は 402 条（25×25 - 未定義セル）— M3 本実装で全量発行。
- kanjiskip {0,0.25,0}、xkanjiskip {0.25,0.25,0.125}、end_adjust は
  ltj-jfont 準拠（昇順ソート）。
- バリアント: `--open-bracket-pos=zenkakunibu_nibu` はクラス 1 幅
  0.5→1.0・全クラス→1 のグルー自然長 −0.5（ratio 再配合）を反映。
  `--burasage=true` はクラス 6,7 の end_adjust に −0.5 を追加しソート。

## 直列化形式

- 全定義 `\expandafter\def\csname NAME\endcsname{…}` 形式。
  **理由**: 名前に数字を含むマクロ（`class@0`、`cls@AB` 等）は素の
  `\def\foo@0{…}` では `0` がパラメタテキストの区切りになり、マクロ名の
  一部にならない（TeX の落とし穴、実証済み）。`\csname` 経由なら安全。
- 本体は 1 つのグループ、複数フィールドは内部グループ `{a}{b}…`。
- 数値は `%.6f` 固定小数（ロケール非依存・決定的。1/3 → 0.333333）。
- キー昇順ソート、タイムスタンプなし → 再生成差分ゼロ検査に適する。

## M3 本実装への指針

- Makefile: `pdftex-jfm` ターゲット（4 バリアント生成）+ `check-pdftex-jfm`
  （再生成して `cmp`/`git diff --exit-code`）→ CI ゲート（PLAN §3.3）。
- コミット済み `.def` ヘッダに `jfm-jlreq.lua` の SHA256 と生成器
  バージョンを記録して追跡可能性を確保（推奨: 実施する）。
- 実行時の値取り出しは `\csname` 参照 + `\edef` で展開（LaTeX2e の
  `\typeout` は `\csname` 参照を展開しない落とし穴あり、実証済み）。

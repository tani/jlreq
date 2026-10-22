# pdfTeXバックエンドのテスト方法（pdftex-tests）

## テスト構成（PLAN.md §6 のテスト層への対応）

| 層 | 内容 | 実装 | 実行方法 |
|---|---|---|---|
| T1 静的 | JFM生成データの同等性 | `check_jfm_pdftex.lua` + `make check-pdftex-jfm` | `texlua check_jfm_pdftex.lua`（rc=0で全項目合格） |
| T2 マクロ | エンジン検出・寸法・フォント選択 | tests/fixtures/ + 3エンジン回帰 | 下記「回帰テスト」 |
| T3 文字組版 | ペアグルー・禁則・和欧文間隔 | tests/fixtures/pdflatex-rules/pairs.tex, kinsoku.tex | `pdflatex ... pairs.tex` → ログの PASS/FAIL |
| T4 段落 | 行末調整 | tests/fixtures/pdflatex-rules/endadjust.tex | Overfull件数で判定 |
| T5 文書 | 混植文書の全体動作 | tests/fixtures/pdflatex-mixed.tex | pdftotext で抽出照合 |
| T7 回帰 | p/u/l の既存動作 | tests/fixtures/{basic-mixed,math-japanese,tate-vertical}.tex | 下記「回帰テスト」 |

## 実行方法（リポジトリ直下から）

```sh
# T1: JFMデータ検証（差分ゼロ + 全ペア照合）
make check-pdftex-jfm
texlua check_jfm_pdftex.lua

# T3: 組版規則の実測（ログに PASS/FAIL が出る）
mkdir -p /tmp/m4t
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=/tmp/m4t tests/fixtures/pdflatex-rules/pairs.tex
grep -E 'PASS|FAIL' /tmp/m4t/pairs.log   # 全PASSが合格

# T4: 行末調整
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=/tmp/m4t tests/fixtures/pdflatex-rules/endadjust.tex
grep -c Overfull /tmp/m4t/endadjust.log  # 0が合格

# T5: 混植文書
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=/tmp/m4t tests/fixtures/pdflatex-mixed.tex
pdftotext /tmp/m4t/pdflatex-mixed.pdf -   # 文字列抽出の目視照合
pdffonts /tmp/m4t/pdflatex-mixed.pdf      # IMFCTT1/IGFCTT1埋込確認

# T7: 3エンジン回帰（差分ゼロ確認）
for f in basic-mixed math-japanese tate-vertical; do
  for e in platex uplatex; do
    $e -interaction=nonstopmode -halt-on-error \
      -output-directory=/tmp/reg tests/fixtures/$f.tex
  done
  lualatex -interaction=nonstopmode -halt-on-error \
    -output-directory=/tmp/reg tests/fixtures/$f.tex
done
# 比較はDVIはタイムスタップ正規化後バイト同一，lualatexのPDFは
# 日付/ID正規化後バイト同一:
LC_ALL=C sed -E 's/[0-9]{4}\.[0-9]{2}\.[0-9]{2}:[0-9]{4}/DATE/' a.dvi > a.n.dvi
LC_ALL=C sed -E 's/(D:[0-9]{14}[+0-9'\'']*)/(DATE)/g; s|/ID \[[^]]*\]|/ID XXX|g' a.pdf > a.n.pdf
```

## 基準点（変更前後で同じコマンド・同じ正規化を用いること）

DVI/PDFは埋込タイムスタンプを持つため，**正規化してからバイト比較**する。
両側を同一パイプライン（同じdvipdfmx等）で処理すること。
lualatexは直接PDF出力のため日付/ID正規化のみでよい。

## 判定基準（PLAN.md §6.3）

- T1: `ALL CHECKS PASSED`（差分0・全ペア照合）
- T3: pairs.tex 7/7 PASS，禁則は `tests/check-kinsoku.py`（実PDF bbox機械
  検証，閉じ約物の行頭0件）で確認 — スイート内 `kinsoku-bbox-line-head-scan`
- T4: 対象フィクスチャでOverfull 0件
- T7: 3フィクスチャ×3エンジン，正規化後バイト同一

## 一括テスト実行

```sh
sh tests/run-pdftex-tests.sh
```

T1（JFMデータ検証），T3/T4（組版規則の実測+ログ内判定），T5（文書・共存
フィクスチャ），T7（3エンジン回帰+バックエンド分離），T2（tate明示エラー）
を順に実行し，全体の PASS/FAIL を出力する。失敗時は詳細が
`/tmp/jlreq-tests/<name>.out` にある。

## 性能測定（T8）

### ストレスベンチマーク（tests/fixtures/pdflatex-bench/long.tex: 約物・
### 混植・脚注・数式・長段落を含む2ページ，内容は全エンジン同一）

PLAN.md §10.2 の比較構成（同一マシン，ウォームアップ後3回の中央値，2026-10-23）:

| 構成 | 実行時間 | PDFサイズ | 備考 |
|---|---|---|---|
| (B) pdfLaTeX＋本バックエンド | **0.375s** | 654,251 B | ipaex-type1 Type1サブセット埋込 |
| (C) LuaLaTeX＋既存jlreq | 0.961s | 109,436 B | OTF直接埋込（サイズ差は字体方式由来） |
| (D) upLaTeX＋既存jlreq | 0.191s | （DVI経由） | 最速基準 |

- (B)は(C)より約2.6×高速，(D)より約2×遅い。増分の主因は
  bxcjkjatype/CJKパッケージのロードと文字毎の状態機構展開。
- JFMデータは静的`.def`のため，実行時のオーバーヘッドはペア表引き
  （`\csname`一件）とグルー出力のみ。0.4秒/2ページという値は
  PLAN.md「性能閾値は実測後に設定」に対し，短文〜中規模文書で十分実用的。
- 両エンジンの抽出テキストは同一内容（4,399 vs 4,288字はpdftotextの
  スペース挿入規則差であり内容欠落ではない）。

### T8 書籍規模ベンチマーク（tests/fixtures/pdflatex-bench/book100.tex、2026-10-23）

PLAN.md §10.2「章・脚注・目次・図表を含む100ページ以上の書籍」:
10章×10節×3段落+脚注300+表10+hyperrefしおり、**124ページ**。
ウォームアップ後3回の中央値:

| 構成 | 実行時間 | ピークメモリ | 出力 |
|---|---|---|---|
| (B) pdfLaTeX＋本バックエンド | **3.77s** | **60.4MB** | PDF 479KB、抽出5007行、フォント37個全埋込 |
| (C) LuaLaTeX＋既存jlreq | 3.16s | 481MB | 124ページ同一、抽出4609行 |
| (D) upLaTeX＋既存jlreq | 0.70s | 45.8MB | DVI経由 |

- (B)は(C)の約1.2倍、(D)の約5.4倍。約物ペアグルーの状態機構展開が
  主因だが、100ページ超文書で4秒弱は実用範囲。
- ピークメモリは(B)が最小クラス: (C)のLuaTeXランタイム(約481MB)の
  1/8、(D)より15MB多い程度。抽出5007 vs 4609行の差はpdftotextの
  スペース結合規則差（内容欠落ではない、両者同一文章）。
- 抽出テキストのU+FFFD 0件、フォント未埋込0件（規模ベンチでも同一品質）。

### T8 追加計測: (A) 生bxcjkjatype ベースライン（2026-10-23）

同一内容（long.texベンチ）での比較:

| 構成 | 実行時間（3回合計） | PDFサイズ | 抽出文字数 |
|---|---|---|---|
| (A) pdfLaTeX＋bxcjkjatype単体 | 0.762s | 440,400 B | 4,291 |
| (B) pdfLaTeX＋本バックエンド | 1.123s | 654,251 B | 4,399 |

- (B)は(A)の約1.5倍。増分＝状態機構の展開＋JFMグルー/禁則ペナルティ出力
  （機能を実装した上で1.5倍はPLAN.md「性能閾値は実測後」に照らし妥当）。
- PDFサイズ差の要因: (B)はペアグルー由来の改行位置差でサブセットフォントの
  グリフ構成が変わる（内容欠落ではない，抽出は本文同一）。

## Definition of Done 実測サマリ（2026-10-23 最終確認）

PLAN.md §11 の各項目に対する機械的確認結果:

| DoD項目 | 確認方法 | 結果 |
|---|---|---|
| 自動検出+明示指定 | `\documentclass{jlreq}` / `[pdflatex]` 両方 rc=0 | PASS |
| JFM単一ソース+差分ゼロ | `make check-pdftex-jfm` | PASS（全4変種） |
| 禁則・字間の重大な規則違反 | `tests/check-kinsoku.py`（実PDF bbox走査）+ pairs.tex 7計測 | 0件 |
| p/u/l 非意図的回帰 | DVI（タイムスタンプ正規化）とPDF（日付/ID正規化）のバイト比較＋`\jidori`/`\akigumi` 4エンジン回帰ガード（suite内 reg-jidori-*） | 全同一 |
| 文字抽出 | 全21 PDF（20フィクスチャ+エラーケース1） `pdftotext` → 置換文字(U+FFFD) 0件 | PASS |
| 文字化け | 同上 | 0件 |
| フォント埋め込み | 全21 PDF `pdffonts` → 未埋込 0件（IPAex Type1, LM, CM すべて subset埋込） | PASS |
| しおり | hyperref-bookmarks 3パス → PDF ObjStm 内 UTF-16BE タイトル3件（`はじめてのしおり`等）を解凍確認 | PASS |
| インストール・配布 | Makefile `install`/`tds` にバックエンド・def・生成器・ドキュメント収録 | 済み |
| 依存関係・ライセンス・最低版 | `docs/pdftex-dependencies.md` | 記録済み |
| 上流レビュー・マージ | `docs/upstream-issue-draft.md`（PR 1–7 分割案つき） | 外部待ち |

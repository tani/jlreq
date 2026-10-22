# PoC G2 — 透明な和欧文境界グルー（JA↔latin boundary glue）

## 目的
PLAN §3.4 / ゲートG2：通常のLaTeXマクロ・グループ・数式・フォント切替を
**透過的**に跨ぐ、JA↔latin 境界への自動グルー挿入が CJK 出力層のフックで
実現できるかを pdfLaTeX + bxcjkjatype で実証する。

## 実行方法
```sh
# 既定（CJKpunct = quanjiao）
pdflatex -interaction=nonstopmode g2-boundary.tex

# noCJKpunct 比較（CJKpunct の干渉を外す）
pdflatex -interaction=nonstopmode '\def\bndNOpunct{1}\input{g2-boundary.tex}'
```
ビルド産物はカレントDirに残るので `/tmp` で実行すること（repo内では実行しない）。
証拠はログに出る:
- `G2|<tag>|...` … 各シナリオの状態遷移トレース
- `G2M|<key>|<width>` … 計測幅 (pt)

## フックポイント（結論）
| フック | 呼ばれる場所 | 役割 |
|---|---|---|
| `\CJKsymbol`（CJKpunct交換後の実体をラップ） | UTF8.chr の `\CJK@char`/`\CJK@altchar` が非約物1文字ごとに呼ぶ | **latin→CJK** 境界グルーを文字直前に挿入 |
| `\CJKpunctsymbol`（同上） | UTF8.enc が e3/ef 面を `\CJK@punctchar` 経由で dispatch（約物だけでなく非約物もここを通る） | 同上（約物経由の文字にも対応） |
| `\CJK@@@ignorespaces`（CJKspace の空白処理。`\CJK*` 環境で各CJK文字列の直後に呼ばれる） | CJK文字処理直後の安定点 | `\futurelet` で**次トークンを覗いて消費せず**判定 → **CJK→latin** 境界グルーをここで挿入 |

設計上の要点:
- 状態は グローバル `\count`（0=none/other, 1=cjk, 2=latin）。マクロ・グループを跨ぐのは
  「TeXのマクロ展開は文字トークン列をそのまま先へ渡す」ため。グループ `{...}` は
  `\egroup` を覗いた時 `\aftergroup` で覗きを再開する。
- 数式内の CJK 文字は `\ifmmode` で検出し、グルーを入れず状態をリセット。
- 明示的スペース後は自動グルーを入力しない（`\@sptoken` 判定）。
- `\CJKsymbol` は `\DeclareRobustCommand` なので、フックは**実行時に展開される
  保護された実体**をラップする（`\AtBeginDocument` 内で `\let` 取得＋`#1` を
  そのまま渡す `\def`。`\makeatletter` は `\AtBeginDocument` の**外**で）。

## 結果（要約）
全シナリオ (a)–(i) で境界グルーが期待通り挿入され、幅計算と一致
（`漢字abc漢字` = 20+15.27782+20+2×2.5 = **60.27782pt**、測定値一致）。
CJKpunct(quanjiao) 有無で差なし（約物経由も同じ経路でラップ）。
詳細な表は `local://poc2-report.md` を参照。

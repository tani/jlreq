# 参照エンジン定量検証結果（PLAN.md §2.2）

生成: 2026-10-23。`\hsize=65pt` の行に「漢漢漢漢漢漢」+閉じ括弧を置いた
禁則ストレス入力での行末挙動。PDFはコミットしない（方針どおり）、
座標値のみを記録する。オラクル: `pdftotext -bbox` の xMin/xMax。

## 入力（tests/fixtures/pdflatex-rules/kinsoku.tex と同一文章）

```latex
\hsize=65pt \parindent=0pt
漢漢漢漢漢漢」漢漢漢漢漢漢漢
漢漢漢漢漢「漢漢漢漢漢漢漢
```

## 行末結果（1行目: 行がどこまで伸びるか）

| エンジン | 1行目右端 xMax (pt) | 1行目の終わり | 備考 |
|---|---|---|---|
| platex (jlreq) | 148.2 | 漢漢漢漢漢漢」 | 行末追込み（end_adjust）で65ptを超えて」まで置く |
| uplatex (jlreq) | 同上 | 同上 | platexと同一 |
| lualatex (jlreq) | 同上 | 同上 | ltjのlineend=extended調整 |
| **pdflatex (本バックエンド)** | 143.2 | 漢漢漢漢漢（」は次行2文字目） | 禁則自体は遵守（」は行頭でない）。差分行末追込み |

## 解釈

- 3参照エンジンは同一レイアウト。いずれも行末約物の追込みにより
  hsizeを最大0.5zw超えて」を行末に残す（jfm-jlreq.luaのクラス2
  end_adjust {0,0.5} の作用）。
- pdfTeXバックエンドは禁則（」を行頭にしない）を守るが、
  end_adjustはshrink畳み込み近似（docs/pdftex-internals.md M5参照）で
  あるため、参照エンジンほど行を伸ばせず、」が次行へ落ちる。
  「行頭禁則違反」ではなく「行末追込みの近似差」であり、
  docs/pdftex-compatibility.md の既知の制限（M5/G3）の実測値である。

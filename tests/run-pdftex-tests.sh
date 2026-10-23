#!/bin/sh
# jlreq pdfTeXバックエンド テスト一括実行（docs/pdftex-tests.md の手順を自動化）。
# 使い方: sh tests/run-pdftex-tests.sh
# 出力: 各テストの PASS/FAIL と最終結果。作業用一時ディレクトリは /tmp/jlreq-tests。
set -e
cd "$(dirname "$0")/.."
OUT=${TMPDIR:-/tmp}/jlreq-tests
mkdir -p "$OUT"
FAILED=0

run() { # run <name> <cmd...>
  name=$1; shift
  if "$@" > "$OUT/$name.out" 2>&1; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (see $OUT/$name.out)"
    FAILED=$((FAILED+1))
  fi
}

echo "== T1: JFMデータ検証 =="
run check-jfm-diff  make check-pdftex-jfm
run check-jfm-full  texlua check_jfm_pdftex.lua

echo "== T3/T4: 組版規則の実測 =="
for f in tests/fixtures/pdflatex-rules/*.tex; do
  name=$(basename "$f" .tex)
  run "rules-$name" pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$OUT" "$f"
done
# pairs.tex はログ内判定も検証（全PASSであること）
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$OUT" \
  tests/fixtures/pdflatex-rules/pairs.tex > /dev/null 2>&1
if grep -q '^FAIL' "$OUT/pairs.log" || ! grep -q '^PASS' "$OUT/pairs.log"; then
  echo "FAIL: rules-pairs-log-assertions"; FAILED=$((FAILED+1))
else
  echo "PASS: rules-pairs-log-assertions ($(grep -c '^PASS' "$OUT/pairs.log") measurements)"
fi
if grep -q 'Overfull' "$OUT/endadjust.log"; then
  echo "FAIL: endadjust-overfull-check"; FAILED=$((FAILED+1))
else
  echo "PASS: endadjust-overfull-check"
fi
# hanging-punct.tex はログ内判定（HANG-PASS/FAIL: 右マージンカーン読み戻し
# と段落行数）を検証（ぶら下げ発火の直接証拠）
if grep -q 'HANG-FAIL' "$OUT/hanging-punct.log" || ! grep -q 'HANG-PASS' "$OUT/hanging-punct.log"; then
  echo "FAIL: hanging-punct-log-assertions"; FAILED=$((FAILED+1))
else
  echo "PASS: hanging-punct-log-assertions ($(grep -c 'HANG-PASS' "$OUT/hanging-punct.log") assertions)"
fi
# 行頭禁則のbbox機械検証（閉じ約物が行頭に来ないこと）
python3 tests/check-kinsoku.py "$OUT"/kinsoku.pdf "$OUT"/punctuation-consecutive.pdf \
  "$OUT"/punct-width.pdf "$OUT"/preclose-latin.pdf "$OUT"/boundary-ja-la.pdf \
  > "$OUT/kinsoku-check.out" 2>&1
if [ $? -eq 0 ]; then
  echo "PASS: kinsoku-bbox-line-head-scan (5 fixtures)"
else
  echo "FAIL: kinsoku-bbox-line-head-scan (see $OUT/kinsoku-check.out)"
  FAILED=$((FAILED+1))
fi

echo "== T5: 文書フィクスチャ =="
for f in tests/fixtures/pdflatex-mixed.tex tests/fixtures/pdflatex-bench/long.tex; do
  name=$(basename "$f" .tex)
  run "doc-$name" pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$OUT" "$f"
done
for f in tests/fixtures/pdflatex-coexist/*.tex; do
  name=$(basename "$f" .tex)
  run "coexist-$name" pdflatex -interaction=nonstopmode -output-directory="$OUT" "$f"
done
# kanji-numbers.tex はログ内判定も検証（\jlreq@pdf@kansuji の桁置換結果が
# リテラル漢数字＝pTeX \kansuji 実測値（uplatex/platex照合済み）と一致すること）
if grep -q 'KANSUJI-FAIL' "$OUT/kanji-numbers.log" || ! grep -q 'KANSUJI-PASS' "$OUT/kanji-numbers.log"; then
  echo "FAIL: kanji-numbers-log-assertions"; FAILED=$((FAILED+1))
else
  echo "PASS: kanji-numbers-log-assertions ($(grep -c 'KANSUJI-PASS' "$OUT/kanji-numbers.log") assertions)"
fi
# mag-tombow.tex（\mag=1200）はトンボ描画のPDFコンテントストリーム座標を検証
# （描画 stored 座標の mag 不変性＝uplatex との描画一致の必要十分条件）
if python3 tests/check-tombow-mag.py "$OUT/mag-tombow.pdf" > "$OUT/check-tombow-mag.out" 2>&1; then
  echo "PASS: tombow-mag1200-stream-parity"
else
  echo "FAIL: tombow-mag1200-stream-parity (see $OUT/check-tombow-mag.out)"; FAILED=$((FAILED+1))
fi
# trimmarks-banner.tex はログ内判定も検証（show=banner で回転バナー枠組が
# pdfTeX 用に配線されたことの印 BANNER-PD-PASS。placed ピクセル対称表は
# fixture コメント参照）
if ! grep -q 'BANNER-PD-PASS' "$OUT/trimmarks-banner.log"; then
  echo "FAIL: trimmarks-banner-log-assertions"; FAILED=$((FAILED+1))
else
  echo "PASS: trimmarks-banner-log-assertions"
fi
# reference-mark-interlinear.tex はログ内判定も検証（合印を跨ぐpair glue・
# 境界・文字クラス状態復帰。全て INTER-PASS であること）
if grep -q 'INTER-FAIL' "$OUT/reference-mark-interlinear.log" || \
   [ "$(grep -c 'INTER-PASS' "$OUT/reference-mark-interlinear.log")" -ne 3 ]; then
  echo "FAIL: interlinear-log-assertions"; FAILED=$((FAILED+1))
else
  echo "PASS: interlinear-log-assertions (3 assertions)"
fi

echo "== T7: 3エンジン回帰（コンパイル成立 + バックエンド非読込） =="
for f in tests/fixtures/basic-mixed.tex tests/fixtures/math-japanese.tex tests/fixtures/tate-vertical.tex; do
  for e in platex uplatex lualatex; do
    name="reg-$(basename "$f" .tex)-$e"
    run "$name" "$e" -interaction=nonstopmode -halt-on-error -output-directory="$OUT" "$f"
    # pdfTeXバックエンドが読み込まれていないこと
    logname="$(basename "$f" .tex)"
    if grep -q 'jlreq-pdftex' "$OUT/$logname.log" 2>/dev/null; then
      echo "FAIL: $name-backend-isolation"; FAILED=$((FAILED+1))
    else
      echo "PASS: $name-backend-isolation"
    fi
  done
done

# \jidori/\akigumi は4エンジンで定義必須（l/u/p側の定義喪失回帰ガード）。
for e in platex uplatex lualatex; do
  run "reg-jidori-$e" "$e" -interaction=nonstopmode -halt-on-error \
    -output-directory="$OUT" tests/fixtures/pdflatex-rules/jidori-akigumi.tex
done

echo "== T8: pdfTeX 縦組み（shipout rotation, T1） =="

# 縦組みフィクスチャ（JFM 縦データ jlreq-pdftex-jfm-tate.def があれば実行）
if kpsewhich jlreq-pdftex-jfm-tate.def > /dev/null 2>&1; then
  # pdflatex+tate はエラーにならない（実験的回転経路 + ロード時警告）
  printf '\\documentclass[pdflatex,tate]{jlreq}\n\\begin{document}あ\\end{document}' > "$OUT/tate-ok.tex"
  if pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$OUT" \
       "$OUT/tate-ok.tex" > "$OUT/tate-ok.out" 2>&1; then
    if grep -q 'pdfTeX tate support is EXPERIMENTAL' "$OUT/tate-ok.log"; then
      echo "PASS: tate-option-compiles-with-warning"
    else
      echo "FAIL: tate-option-compiles-with-warning (gate warning missing)"; FAILED=$((FAILED+1))
    fi
  else
    echo "FAIL: tate-option-compiles-with-warning (compile)"; FAILED=$((FAILED+1))
  fi
  for f in tests/fixtures/pdflatex-tate-basic.tex tests/fixtures/pdflatex-tate-pairs.tex; do
    name=$(basename "$f" .tex)
    run "tate-$name" pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$OUT" "$f"
  done
  for n in pdflatex-tate-basic pdflatex-tate-pairs; do
    if grep -q 'TATE-FAIL' "$OUT/$n.log" || ! grep -q 'TATE-PASS' "$OUT/$n.log"; then
      echo "FAIL: $n-log-assertions"; FAILED=$((FAILED+1))
    else
      echo "PASS: $n-log-assertions ($(grep -c 'TATE-PASS' "$OUT/$n.log") assertions)"
    fi
  done
  # boxdump（\showbox の ! OK のため -halt-on-error 不使用; END マーカで成立確認）
  pdflatex -interaction=nonstopmode -output-directory="$OUT" \
    tests/fixtures/pdflatex-tate-boxdump.tex > /dev/null 2>&1 || true  # \showbox emits `! OK' -> rc=1 by design; set -e must not abort here
  if ! grep -q 'TATE-GALLEY-END' "$OUT/pdflatex-tate-boxdump.log"; then
    echo "FAIL: tate-boxdump-compile"; FAILED=$((FAILED+1))
  elif python3 tests/check-tate-boxdump.py "$OUT/pdflatex-tate-boxdump.log" \
       > "$OUT/tate-boxdump.out" 2>&1; then
    echo "PASS: tate-boxdump-kinsoku"
  else
    echo "FAIL: tate-boxdump-kinsoku (see $OUT/tate-boxdump.out)"; FAILED=$((FAILED+1))
  fi
else
  echo "SKIP: tate fixtures (jlreq-pdftex-jfm-tate.def not found; pending)"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "$FAILED TEST(S) FAILED"
  exit 1
fi

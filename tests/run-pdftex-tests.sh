#!/bin/sh
# jlreq pdfTeXバックエンド テスト一括実行（docs/pdftex-tests.md の手順を自動化）。
#
# 使い方: sh tests/run-pdftex-tests.sh
#
# Phase 1（基準と失敗判定）改訂:
#   - 実行ごとに mktemp -d で隔離されたベースディレクトリを作り、
#     各 (section, fixture, engine, pass) に個別サブディレクトリを与える。
#     各コンパイルは -output-directory=<そのdir> で実行する。ログ・PDFは
#     すべてそこに残り、失敗行は該当ログのパスを必ず示す。
#   - T0 プリフライト: 必須資源（JFM .def 5種、バックエンド .sty 2種、
#     trimmarks .def、フォント ipxm/ipxg、cmtt9）を検査し、欠損は SKIP
#     ではなく FAIL（欠損ファイル名を明示）。縦組みJFM .def 欠損も FAIL。
#   - T7 はコンパイル成立 + バックエンド非読込に加えて、コミット済み
#     ベースライン（tests/reference/baselines/、実装前に固定条件で
#     記録した p/u DVI・l PDF の正規化バイト）とのバイト比較を行う。
#     差分は全件 FAIL。再記録には明示的な承認が必要（README.md 参照）。
#   - 既知不良ゲート（XFAIL）: KNOWN_DEFECTS に列挙した検査は
#     「今日失敗するべきもの」。失敗は XFAIL と数え、デフォルトでは
#     全体 rc に影響しない（実装キャンペーン中は green-with-xfails）。
#     成功した場合は XPASS とし、非0で終了して昇格手順を指示する。
#     KNOWN_DEFECT_EXPECT=<name> を渡すと期待値反転検証に使える。
#   - 自己申告型検査は廃止済み: trimmarks-banner は実PDFの幾何検査
#     （tests/check-banner-slots.py）、pdflatex-tate-pairs はsmokeのみ
#     （T1 の JFM .def 等価性検査が実値検証を担うため、循環ログ判定は
#     成功基準から外した）。
#
# 出力: 各検査の PASS/FAIL/XFAIL/XPASS と最終サマリ。作業ディレクトリは
# 実行ごとの mktemp -d（先頭行にパスを表示）。

cd "$(dirname "$0")/.." || exit 1

# P4: 補助縦フォント（aux TTF/TFM/enc）とフォントプロファイルは
# fonts/pdftex/ に配置される。pdfTeX の mapline 資源解決は kpathsea
# （TEXFONTS/TEXENCS）で行うため、repo root からの実行で見えるように
# 先頭で一度だけ設定する（POSIX sh; 上書きではなく追記）。
PDFTEX_AUX_FONT_DIR="$(pwd)/fonts/pdftex"
if [ -d "$PDFTEX_AUX_FONT_DIR" ]; then
  TEXFONTS="${TEXFONTS:+$TEXFONTS}${PDFTEX_AUX_FONT_DIR}:"
  TEXENCS="${TEXENCS:+$TEXENCS}${PDFTEX_AUX_FONT_DIR}:"
  export TEXFONTS TEXENCS
fi

# ---------------------------------------------------------------------------
# 集計変数
# ---------------------------------------------------------------------------
FAILED=0
XFAILED=0
XPASSED=0
XFAIL_NAMES=""
XPASS_NAMES=""

# 既知不良リスト（単一の真実源）。ここに名前を足した検査は「今日は失敗が
# 期待される」: 失敗 → XFAIL（rc 影響なし）、成功 → XPASS（非0+昇格指示）。
# 実装が不良を直したら、そのフェーズでここから削除し通常検査へ移すこと。
KNOWN_DEFECTS=""

# 既知不良検査の期待値反転用: KNOWN_DEFECT_EXPECT=<name> を設定すると、
# その検査だけ「成功が期待値」となり、失敗時に非0を返す（検査そのものの
# 動作確認・将来のXFAIL戻し入れ時に使う）。
expect_xfail() {
  case " $KNOWN_DEFECT_EXPECT " in
    *" $1 "*) return 0;;
    *) return 1;;
  esac
}

is_known_defect() {
  case " $KNOWN_DEFECTS " in
    *" $1 "*) return 0;;
    *) return 1;;
  esac
}

# ---------------------------------------------------------------------------
# 隔離された実行ディレクトリ
# ---------------------------------------------------------------------------
OUT=$(mktemp -d "${TMPDIR:-/tmp}/jlreq-tests.XXXXXXXX") || {
  echo "FAIL: cannot create temp dir"; exit 1; }
echo "workdir: $OUT"

# outdir_for <group> <name> [<pass>]: (engine,)fixture,pass 別のサブディレ
# クトリ。グループ名は衝突しない短名（t3-rules など）。
outdir_for() {
  _d="$OUT/$1/$2"
  [ $# -ge 3 ] && _d="$_d/$3"
  mkdir -p "$_d" || exit 1
  printf '%s' "$_d"
}

# fail <name> <logpath>: 失敗を数え、ログのパスを明示
fail() {
  echo "FAIL: $1 (see $2)"
  FAILED=$((FAILED+1))
}

# pass <name>
pass() {
  echo "PASS: $1"
}

# verdict <name> <logpath> <rc 0|1>: 検査結果を既知不良管理に従って分類
#   rc=0 かつ既知不良 → XPASS（非0+昇格指示）
#   rc!=0 かつ既知不良 → XFAIL（rc 影響なし）
#   それ以外は通常 PASS/FAIL
verdict() {
  _name=$1; _log=$2; _rc=$3
  if is_known_defect "$_name"; then
    if [ "$_rc" -eq 0 ]; then
      echo "XPASS: $_name (known defect appears FIXED — promotion required)"
      echo "  PROMOTE: remove '$_name' from KNOWN_DEFECTS in tests/run-pdftex-tests.sh,"
      echo "  move its check into the corresponding normal section, and update"
      echo "  docs/pdftex-tests.md. Until then the suite exits non-zero."
      XPASSED=$((XPASSED+1))
      XPASS_NAMES="$XPASS_NAMES $_name"
    else
      echo "XFAIL: $_name (known defect still present, see $_log)"
      XFAILED=$((XFAILED+1))
      XFAIL_NAMES="$XFAIL_NAMES $_name"
    fi
  elif [ "$_rc" -eq 0 ]; then
    pass "$_name"
  else
    fail "$_name" "$_log"
  fi
}

# run_compile <name> <outdir> <engine> <file...>: コンパイルを実行し rc を
# 返す。固定日時 SOURCE_DATE_EPOCH=1735689600、-interaction=nonstopmode
# -halt-on-error -output-directory=<outdir> は全呼出しで共通（pdflatex
# 起動フラグは既存スイートと同一; boxdump のみ例外的に -halt-on-error
# なしで直接呼ぶ）。<name> は互換のため受け取るだけで使用しない。
run_compile() {
  _name=$1; _dir=$2; _eng=$3; shift 3
  SOURCE_DATE_EPOCH=1735689600 "$_eng" -interaction=nonstopmode \
    -halt-on-error -output-directory="$_dir" "$@" >"$_dir/compile.out" 2>&1
}

# run <name> <outdir> <engine> <file...>: コンパイル成功のみを検査する
# 最小ヘルパ（verdict は付かない; 既知不良管理が必要な検査は verdict を
# 直接使う）。
run() {
  _name=$1; _dir=$2; _eng=$3; shift 3
  if run_compile "$_name" "$_dir" "$_eng" "$@"; then
    pass "$_name"
  else
    fail "$_name" "$_dir/compile.out"
  fi
}

# ===========================================================================
echo "== T0: プリフライト（必須資源の検査; 欠損はSKIPではなくFAIL） =="
# ===========================================================================
T0_MISSING=""
# JFM .def 12組（P2 manifest pdftex-jfm-manifest.lua が唯一の一覧）:
# 欠損している .def があれば T0 が特定ファイル名つきで FAIL にする。
for f in jlreq-pdftex-jfm.def jlreq-pdftex-jfm-b.def jlreq-pdftex-jfm-z.def \
         jlreq-pdftex-jfm-bz.def jlreq-pdftex-jfm-n.def jlreq-pdftex-jfm-bn.def \
         jlreq-pdftex-jfm-tate.def jlreq-pdftex-jfm-tate-b.def \
         jlreq-pdftex-jfm-tate-z.def jlreq-pdftex-jfm-tate-bz.def \
         jlreq-pdftex-jfm-tate-n.def jlreq-pdftex-jfm-tate-bn.def \
         pdftex-jfm-manifest.lua \
         jlreq-pdftex.sty jlreq-pdftex-rules.sty \
         jlreq-trimmarks-pdftex.def jlreq.cls; do
  [ -f "$f" ] || T0_MISSING="$T0_MISSING $f"
done
# P4: フォントプロファイル（両組）と第1シャードの aux 縦フォント資源
# （profile .def + TFM/enc/TTF）は縦組みの必須資源。fonts/pdftex/ は
# `make pdftex-fonts` の出力先（コミット済み）。
for f in fonts/pdftex/jlreq-pdftex-fonts-ipaex.def \
         fonts/pdftex/jlreq-pdftex-fonts-ipa.def \
         fonts/pdftex/jlreqv-ipaex-mc-00.tfm fonts/pdftex/jlreqv-ipaex-mc-00.enc \
         fonts/pdftex/jlreqv-ipaex-mc-00.ttf fonts/pdftex/jlreqv-ipaex-mc-01.tfm \
         fonts/pdftex/jlreqv-ipaex-mc-01.enc fonts/pdftex/jlreqv-ipaex-mc-01.ttf \
         fonts/pdftex/jlreqv-ipaex-gt-00.tfm fonts/pdftex/jlreqv-ipaex-gt-00.enc \
         fonts/pdftex/jlreqv-ipaex-gt-00.ttf fonts/pdftex/jlreqv-ipaex-gt-01.tfm \
         fonts/pdftex/jlreqv-ipaex-gt-01.enc fonts/pdftex/jlreqv-ipaex-gt-01.ttf \
         fonts/pdftex/jlreqv-ipa-mc-00.tfm fonts/pdftex/jlreqv-ipa-mc-00.enc \
         fonts/pdftex/jlreqv-ipa-mc-00.ttf fonts/pdftex/jlreqv-ipa-mc-01.tfm \
         fonts/pdftex/jlreqv-ipa-mc-01.enc fonts/pdftex/jlreqv-ipa-mc-01.ttf \
         fonts/pdftex/jlreqv-ipa-gt-00.tfm fonts/pdftex/jlreqv-ipa-gt-00.enc \
         fonts/pdftex/jlreqv-ipa-gt-00.ttf fonts/pdftex/jlreqv-ipa-gt-01.tfm \
         fonts/pdftex/jlreqv-ipa-gt-01.enc fonts/pdftex/jlreqv-ipa-gt-01.ttf; do
  [ -f "$f" ] || T0_MISSING="$T0_MISSING $f"
done
for f in ipxm-r-u30.pfb ipxg-r-u30.pfb cmtt9.tfm; do
  kpsewhich "$f" >/dev/null 2>&1 || T0_MISSING="$T0_MISSING $f(kpsewhich)"
done
if [ -n "$T0_MISSING" ]; then
  echo "FAIL: T0-preflight missing required files:$T0_MISSING"
  FAILED=$((FAILED+1))
else
  pass "T0-preflight (JFM .def x12 + manifest, backend .sty x2, trimmarks .def, ipxm/ipxg fonts, cmtt9, font profiles + aux vert fonts x2 fontsets)"
fi

# ===========================================================================
echo "== T1: JFMデータ検証 =="
# ===========================================================================
d=$(outdir_for t1 jfm)
if make check-pdftex-jfm >"$d/check.out" 2>&1; then
  pass "check-jfm-diff (make check-pdftex-jfm)"
else
  fail "check-jfm-diff" "$d/check.out"
fi
if texlua check_jfm_pdftex.lua >"$d/check-full.out" 2>&1; then
  pass "check-jfm-full (texlua check_jfm_pdftex.lua)"
else
  fail "check-jfm-full" "$d/check-full.out"
fi

# ===========================================================================
echo "== T3/T4: 組版規則の実測 =="
# ===========================================================================
for f in tests/fixtures/pdflatex-rules/*.tex; do
  name=$(basename "$f" .tex)
  d=$(outdir_for t3-rules "$name")
  run "rules-$name" "$d" pdflatex "$f"
done
# pairs.tex: ログ内判定（全PASSであること）
d=$(outdir_for t3-rules pairs 2)
if pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$d" \
     tests/fixtures/pdflatex-rules/pairs.tex >"$d/compile.out" 2>&1 \
     && { ! grep -q '^FAIL' "$d/pairs.log" 2>/dev/null; } \
     && grep -q '^PASS' "$d/pairs.log" 2>/dev/null; then
  echo "PASS: rules-pairs-log-assertions ($(grep -c '^PASS' "$d/pairs.log") measurements)"
else
  fail "rules-pairs-log-assertions" "$d/compile.out"
fi
# endadjust.tex: Overfull 0件
d=$(outdir_for t3-rules endadjust 2)
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$d" \
  tests/fixtures/pdflatex-rules/endadjust.tex >"$d/compile.out" 2>&1
if grep -q 'Overfull' "$d/endadjust.log" 2>/dev/null; then
  fail "endadjust-overfull-check" "$d/endadjust.log"
else
  pass "endadjust-overfull-check"
fi
# hanging-punct.tex: ログ内判定（HANG-PASS/FAIL）
d=$(outdir_for t3-rules hanging-punct 2)
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$d" \
  tests/fixtures/pdflatex-rules/hanging-punct.tex >"$d/compile.out" 2>&1
if grep -q 'HANG-FAIL' "$d/hanging-punct.log" 2>/dev/null; then
  fail "hanging-punct-log-assertions" "$d/hanging-punct.log"
elif grep -q 'HANG-PASS' "$d/hanging-punct.log" 2>/dev/null; then
  echo "PASS: hanging-punct-log-assertions ($(grep -c 'HANG-PASS' "$d/hanging-punct.log") assertions)"
else
  fail "hanging-punct-log-assertions" "$d/hanging-punct.log"
fi
# 行頭禁則のbbox機械検証（閉じ約物が行頭に来ないこと; 5 fixtures）
k1=$(outdir_for t3-rules kinsoku pdf)
k2=$(outdir_for t3-rules punctuation-consecutive pdf)
k3=$(outdir_for t3-rules punct-width pdf)
k4=$(outdir_for t3-rules preclose-latin pdf)
k5=$(outdir_for t3-rules boundary-ja-la pdf)
if python3 tests/check-kinsoku.py "$k1"/kinsoku.pdf "$k2"/punctuation-consecutive.pdf \
     "$k3"/punct-width.pdf "$k4"/preclose-latin.pdf "$k5"/boundary-ja-la.pdf \
     >"$OUT/t3-rules/kinsoku-check.out" 2>&1; then
  pass "kinsoku-bbox-line-head-scan (5 fixtures)"
else
  fail "kinsoku-bbox-line-head-scan" "$OUT/t3-rules/kinsoku-check.out"
fi

# ---- T3b: 行末追込みの4エンジンparity（endadjust-lineend）----
# 2026-10-24 時点で f665eba の addendadj 修正により parity は成立している
# （tests/reference/kinsoku-lines.md 訂正節参照）。通常ゲートとして
# 0.1pt で固定検査する（P3 の行末候補列再構成が参照から離れないため）。
d=$(outdir_for t3b endadjust-lineend pdflatex)
run_compile x "$d" pdflatex tests/fixtures/pdflatex-rules/endadjust-lineend.tex
dp_rc=$?
d=$(outdir_for t3b endadjust-lineend lualatex)
run_compile x "$d" lualatex tests/fixtures/pdflatex-rules/endadjust-lineend.tex
dl_rc=$?
d=$(outdir_for t3b endadjust-lineend platex)
run_compile x "$d" platex tests/fixtures/pdflatex-rules/endadjust-lineend.tex
dp2_rc=$?
dvipdfmx -o "$d/x.pdf" "$d/endadjust-lineend.dvi" >"$d/dvipdfmx.out" 2>&1
dp2_pdf=$?
d=$(outdir_for t3b endadjust-lineend uplatex)
run_compile x "$d" uplatex tests/fixtures/pdflatex-rules/endadjust-lineend.tex
du_rc=$?
dvipdfmx -o "$d/x.pdf" "$d/endadjust-lineend.dvi" >"$d/dvipdfmx.out" 2>&1
du_pdf=$?
t3b_log="$OUT/t3b/endadjust-lineend"
mkdir -p "$t3b_log"
if [ "$dp_rc" -ne 0 ] || [ "$dl_rc" -ne 0 ] || [ "$dp2_rc" -ne 0 ] \
   || [ "$du_rc" -ne 0 ] || [ "$dp2_pdf" -ne 0 ] || [ "$du_pdf" -ne 0 ]; then
  fail "endadjust-lineend-parity-compile" "$OUT/t3b/endadjust-lineend"
else
  if python3 tests/check-endadjust-parity.py \
       "$OUT/t3b/endadjust-lineend/pdflatex/endadjust-lineend.pdf" \
       "$OUT/t3b/endadjust-lineend/platex/x.pdf" \
       "$OUT/t3b/endadjust-lineend/uplatex/x.pdf" \
       "$OUT/t3b/endadjust-lineend/lualatex/endadjust-lineend.pdf" \
       >"$t3b_log/parity.out" 2>&1; then
    pass "endadjust-lineend-parity (4-engine line-1 xMax within 0.1pt)"
  else
    fail "endadjust-lineend-parity" "$t3b_log/parity.out"
  fi
fi

# ===========================================================================
echo "== T5: 文書フィクスチャ =="
# ===========================================================================
for f in tests/fixtures/pdflatex-mixed.tex tests/fixtures/pdflatex-bench/long.tex; do
  name=$(basename "$f" .tex)
  d=$(outdir_for t5-doc "$name")
  run "doc-$name" "$d" pdflatex "$f"
done
for f in tests/fixtures/pdflatex-coexist/*.tex; do
  name=$(basename "$f" .tex)
  # P9 昇格済みの2ゲート（today-wareki / label-japanese）は下の専用ブロック
  # が複数パス・チェック付きで検査するためここではコンパイルのみ行う。
  d=$(outdir_for t5-coexist "$name")
  run "coexist-$name" "$d" pdflatex "$f"
done
# ---- P9（label・date・space）: 昇格済みの通常ゲート ----
# label-packages: 3パス収束。3パスは同一 outdir で回す（aux を引き継ぐ）。
# 判定: 最終パスで「ラベル変更/Rerun」警告が出ないこと + 全面解決。
lp=$(outdir_for t5-coexist label-packages 3pass)
lp_rc=0
for passno in 1 2 3; do
  if ! run_compile x "$lp" pdflatex \
       tests/fixtures/pdflatex-coexist/label-packages.tex; then
    lp_rc=1
  fi
done
if grep -q 'Label(s) may have changed' \
     "$lp/label-packages.log" 2>/dev/null; then
  lp_rc=1
fi
if [ "$lp_rc" -ne 0 ]; then
  fail "label-packages-3pass" "$lp/compile.out"
else
  pass "label-packages-3pass"
fi
if python3 tests/check-label-packages.py "$lp/label-packages.pdf" \
     "$lp/label-packages.log" >"$lp/check.out" 2>&1; then
  pass "label-packages-matrix (ref/pageref*/eqref/autoref/nameref/cref/hyperref/refcount)"
else
  fail "label-packages-matrix" "$lp/check.out"
fi
# date-boundaries: 和暦5境界日 + 元年 + \西暦true/\和暦 切替
db=$(outdir_for t5-coexist date-boundaries 1)
if run_compile x "$db" pdflatex \
     tests/fixtures/pdflatex-coexist/date-boundaries.tex; then
  if python3 tests/check-date-boundaries.py "$db/date-boundaries.pdf" \
       >"$db/check.out" 2>&1; then
    pass "date-boundaries (5 era dates + gan-nen + style toggle)"
  else
    fail "date-boundaries" "$db/check.out"
  fi
else
  fail "date-boundaries" "$db/compile.out"
fi
# space-dispatcher: \　命令・literal U+3000・\jaspace の共存
sd=$(outdir_for t5-coexist space-dispatcher 1)
if run_compile x "$sd" pdflatex \
     tests/fixtures/pdflatex-coexist/space-dispatcher.tex; then
  if python3 tests/check-space-dispatcher.py "$sd/space-dispatcher.pdf" \
       >"$sd/check.out" 2>&1; then
    pass "space-dispatcher (command/literal/jaspace coexist)"
  else
    fail "space-dispatcher" "$sd/check.out"
  fi
else
  fail "space-dispatcher" "$sd/compile.out"
fi
# kanji-numbers.tex: ログ内判定
d=$(outdir_for t5-coexist kanji-numbers 2)
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$d" \
  tests/fixtures/pdflatex-coexist/kanji-numbers.tex >"$d/compile.out" 2>&1
if grep -q 'KANSUJI-FAIL' "$d/kanji-numbers.log" 2>/dev/null; then
  fail "kanji-numbers-log-assertions" "$d/kanji-numbers.log"
elif grep -q 'KANSUJI-PASS' "$d/kanji-numbers.log" 2>/dev/null; then
  echo "PASS: kanji-numbers-log-assertions ($(grep -c 'KANSUJI-PASS' "$d/kanji-numbers.log") assertions)"
else
  fail "kanji-numbers-log-assertions" "$d/kanji-numbers.log"
fi
# mag-tombow.tex: 描画座標の mag 不変性
d=$(outdir_for t5-coexist mag-tombow 2)
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$d" \
  tests/fixtures/pdflatex-coexist/mag-tombow.tex >"$d/compile.out" 2>&1
if python3 tests/check-tombow-mag.py "$d/mag-tombow.pdf" >"$d/tombow.out" 2>&1; then
  pass "tombow-mag1200-stream-parity"
else
  fail "tombow-mag1200-stream-parity" "$d/tombow.out"
fi
# trimmarks-banner.tex: 実PDFの幾何検証（自己申告 BANNER-PD-PASS は廃止）
d=$(outdir_for t5-coexist trimmarks-banner 2)
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$d" \
  tests/fixtures/pdflatex-coexist/trimmarks-banner.tex >"$d/compile.out" 2>&1
if python3 tests/check-banner-slots.py "$d/trimmarks-banner.pdf" \
     >"$d/banner.out" 2>&1; then
  pass "trimmarks-banner-geometry (6 slots, fixed windows, pymupdf)"
else
  fail "trimmarks-banner-geometry" "$d/banner.out"
fi
# trimmarks-twoside.tex (P8): 奇偶ページ属性のshipout/beforeフック検証
#   - 各ページのTrimBox/BleedBoxがページ奇偶に従って分かれていること
#   - 旧\@outputpageのtl_putパッチで出ていた "Missing number" が無いこと
#   - dドライバからpapersize specialが出ないこと（"Non-PDF special
#     ignored!" がログに無いこと）
d=$(outdir_for t5-coexist trimmarks-twoside 1)
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$d" \
  tests/fixtures/pdflatex-coexist/trimmarks-twoside.tex >"$d/compile.out" 2>&1
tw_rc=$?
if grep -q 'Missing number' "$d/trimmarks-twoside.log" 2>/dev/null; then
  tw_rc=1
fi
if grep -q 'Non-PDF special ignored' "$d/trimmarks-twoside.log" 2>/dev/null; then
  tw_rc=1
fi
if [ "$tw_rc" -ne 0 ] \
   || ! python3 tests/check-trimmarks-pageattr.py "$d/trimmarks-twoside.pdf" \
        >"$d/pageattr.out" 2>&1; then
  fail "trimmarks-twoside-pageattr (P8 shipout/before hook)" "$d/pageattr.out"
else
  pass "trimmarks-twoside-pageattr (P8 shipout/before hook)"
fi
# trimmarks-tate-banner.tex (P8): 縦組文書の回転バナースロットが
# uplatex ground truth（dvipdfmx経由・同一フィクスチャ実測）と
# 0.5pt以内で一致すること。20スロット（2ページ×10スロット族）。
d=$(outdir_for t5-coexist trimmarks-tate-banner 1)
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$d" \
  tests/fixtures/pdflatex-coexist/trimmarks-tate-banner.tex >"$d/compile.out" 2>&1
if python3 tests/check-banner-tate.py "$d/trimmarks-tate-banner.pdf" \
     >"$d/tatebanner.out" 2>&1; then
  pass "trimmarks-tate-banner-geometry (P8, uplatex GT windows)"
else
  fail "trimmarks-tate-banner-geometry (P8)" "$d/tatebanner.out"
fi
# reference-mark-interlinear.tex: ログ内判定（INTER-PASS x3）
d=$(outdir_for t5-coexist reference-mark-interlinear 2)
pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$d" \
  tests/fixtures/pdflatex-coexist/reference-mark-interlinear.tex >"$d/compile.out" 2>&1
n_inter=$(grep -c 'INTER-PASS' "$d/reference-mark-interlinear.log" 2>/dev/null)
n_inter=${n_inter:-0}
if grep -q 'INTER-FAIL' "$d/reference-mark-interlinear.log" 2>/dev/null \
   || [ "$n_inter" -ne 3 ]; then
  fail "interlinear-log-assertions" "$d/reference-mark-interlinear.log"
else
  pass "interlinear-log-assertions (3 assertions)"
fi

# ===========================================================================
echo "== T5b: wareki today / Japanese label（P9昇格済み: 通常ゲート）=="
# ===========================================================================
# today-wareki: pdflatex 対 lualatex 参照（同一ソース・固定日時）
tw_d=$(outdir_for t5b today-wareki pdflatex)
tw_l=$(outdir_for t5b today-wareki lualatex)
tw_rc=0
if ! run_compile x "$tw_d" pdflatex \
     tests/fixtures/pdflatex-coexist/today-wareki.tex; then
  tw_rc=1
fi
if ! run_compile x "$tw_l" lualatex \
     tests/fixtures/pdflatex-coexist/today-wareki.tex; then
  tw_rc=1
fi
python3 tests/check-today-wareki.py "$tw_d/today-wareki.pdf" \
     "$tw_l/today-wareki.pdf" >"$OUT/t5b/today-wareki/check.out" 2>&1
tw_check=$?
if [ "$tw_rc" -ne 0 ] || [ "$tw_check" -ne 0 ]; then tw_result=1; else tw_result=0; fi
if expect_xfail today-wareki; then
  # 期待値反転モード: 成功が正、失敗は FAIL
  if [ "$tw_result" -eq 0 ]; then pass "today-wareki"; else
    fail "today-wareki" "$OUT/t5b/today-wareki/check.out"; fi
else
  verdict "today-wareki" "$OUT/t5b/today-wareki/check.out" "$tw_result"
fi

# label-japanese: 2パス・aux検査・lualatex 参照
lj_d=$(outdir_for t5b label-japanese pdflatex)
lj_l=$(outdir_for t5b label-japanese lualatex)
lj_rc=0
for passno in 1 2; do
  if ! run_compile x "$lj_d" pdflatex \
       tests/fixtures/pdflatex-coexist/label-japanese.tex; then
    lj_rc=1
  fi
  if ! run_compile x "$lj_l" lualatex \
       tests/fixtures/pdflatex-coexist/label-japanese.tex; then
    lj_rc=1
  fi
done
python3 tests/check-label-japanese.py "$lj_d/label-japanese.pdf" \
     "$lj_d/label-japanese.aux" "$lj_l/label-japanese.pdf" \
     >"$OUT/t5b/label-japanese/check.out" 2>&1
lj_check=$?
if [ "$lj_rc" -ne 0 ] || [ "$lj_check" -ne 0 ]; then lj_result=1; else lj_result=0; fi
if expect_xfail label-japanese; then
  if [ "$lj_result" -eq 0 ]; then pass "label-japanese"; else
    fail "label-japanese" "$OUT/t5b/label-japanese/check.out"; fi
else
  verdict "label-japanese" "$OUT/t5b/label-japanese/check.out" "$lj_result"
fi

# ===========================================================================
echo "== T7: 3エンジン回帰（コンパイル + バックエンド非読込 + ベースライン照合）=="
# ===========================================================================
for f in tests/fixtures/basic-mixed.tex tests/fixtures/math-japanese.tex \
         tests/fixtures/tate-vertical.tex; do
  name=$(basename "$f" .tex)
  for e in platex uplatex lualatex; do
    d=$(outdir_for t7 "$name" "$e")
    run "reg-$name-$e" "$d" "$e" "$f"
    # バックエンドが読み込まれていないこと
    if grep -q 'jlreq-pdftex' "$d/$name.log" 2>/dev/null; then
      fail "reg-$name-$e-backend-isolation" "$d/$name.log"
    else
      pass "reg-$name-$e-backend-isolation"
    fi
    # ベースライン照合（実装前に記録した正規化バイトとの比較）
    if [ $e = lualatex ]; then ext=pdf; else ext=dvi; fi
    base="tests/reference/baselines/$e/$name.$ext"
    if [ ! -f "$base" ]; then
      fail "reg-$name-$e-baseline (missing baseline $base)" "$base"
      continue
    fi
    python3 tests/normalize-output.py "$ext" "$d/$name.$ext" >"$d/normalized.$ext" 2>"$d/normalize.err" \
      || { fail "reg-$name-$e-baseline (normalize error)" "$d/normalize.err"; continue; }
    if cmp -s "$d/normalized.$ext" "$base"; then
      pass "reg-$name-$e-baseline (byte-identical to pre-implementation record)"
    else
      echo "FAIL: reg-$name-$e-baseline (output differs from baseline; see $d/normalized.$ext vs $base)" >&2
      FAILED=$((FAILED+1))
    fi
  done
done

# \jidori/\akigumi は4エンジンで定義必須（l/u/p側の定義喪失回帰ガード）。
for e in platex uplatex lualatex; do
  d=$(outdir_for t7 jidori-akigumi "$e")
  run "reg-jidori-$e" "$d" "$e" tests/fixtures/pdflatex-rules/jidori-akigumi.tex
done

# ===========================================================================
echo "== T8: pdfTeX 縦組み（shipout rotation; tate .def 欠損はFAIL）=="
# ===========================================================================
# tate JFM データは必須資源（T0 で検査済み。ここでは欠けていたら即FAIL）。
if [ ! -f jlreq-pdftex-jfm-tate.def ]; then
  fail "tate-fixtures" "jlreq-pdftex-jfm-tate.def"
else
  # pdflatex+tate はエラーにならない（実験的回転経路 + ロード時警告）
  d=$(outdir_for t8 tate-ok)
  printf '\\documentclass[pdflatex,tate]{jlreq}\n\\begin{document}あ\\end{document}' >"$d/tate-ok.tex"
  if pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$d" \
       "$d/tate-ok.tex" >"$d/compile.out" 2>&1 \
     && grep -q 'pdfTeX tate support is EXPERIMENTAL' "$d/tate-ok.log" 2>/dev/null; then
    pass "tate-option-compiles-with-warning"
  else
    fail "tate-option-compiles-with-warning" "$d/compile.out"
  fi
  # tate fixtures: コンパイル + ログ内 TATE-PASS 判定
  #   pdflatex-tate-pairs.tex はsmokeのみ（期待値と実値が同じペア表を読む
  #   循環検査であるため成功基準から外した。実値検証は T1 の JFM .def
  #   等価性検査 check_jfm_pdftex.lua が担う）。ここではコンパイル成立のみ。
  for f in tests/fixtures/pdflatex-tate-basic.tex tests/fixtures/pdflatex-tate-pairs.tex; do
    name=$(basename "$f" .tex)
    d=$(outdir_for t8 "$name")
    run "tate-$name" "$d" pdflatex "$f"
    case $name in
      pdflatex-tate-pairs)
        # smoke: ログ内判定は循環検査のため成功基準に含めない
        ;;
      *)
        if grep -q 'TATE-FAIL' "$d/$name.log" 2>/dev/null; then
          fail "$name-log-assertions" "$d/$name.log"
        elif grep -q 'TATE-PASS' "$d/$name.log" 2>/dev/null; then
          echo "PASS: $name-log-assertions ($(grep -c 'TATE-PASS' "$d/$name.log") assertions)"
        else
          fail "$name-log-assertions" "$d/$name.log"
        fi
        ;;
    esac
  done
  # T3: 注（脚注/後注/傍注）と浮遊体の縦組みフィクスチャ
  for f in tests/fixtures/pdflatex-tate-notes.tex tests/fixtures/pdflatex-tate-float.tex; do
    name=$(basename "$f" .tex)
    d=$(outdir_for t8 "$name")
    run "tate-$name" "$d" pdflatex "$f"
    if grep -q 'TATE-FAIL' "$d/$name.log" 2>/dev/null; then
      fail "$name-log-assertions" "$d/$name.log"
    elif grep -q 'TATE-PASS' "$d/$name.log" 2>/dev/null; then
      echo "PASS: $name-log-assertions ($(grep -c 'TATE-PASS' "$d/$name.log") assertions)"
    else
      fail "$name-log-assertions" "$d/$name.log"
    fi
  done
  # P5: 局所方向・縦中横フィクスチャ（dir-* / tcy-*）
  #   tcy-star-error は意図的な ClassError を含むため -halt-on-error
  #   なしで実行し、ログ内 TATE-PASS とエラー文言の両方を検査する。
  for f in tests/fixtures/pdflatex-tate/dir-roundtrip.tex \
           tests/fixtures/pdflatex-tate/dir-callers.tex \
           tests/fixtures/pdflatex-tate/dir-index-yoko.tex \
           tests/fixtures/pdflatex-tate/tcy-digits.tex \
           tests/fixtures/pdflatex-tate/tcy-fontchange.tex; do
    name=$(basename "$f" .tex)
    d=$(outdir_for t8 "$name")
    run "tate-$name" "$d" pdflatex "$f"
    if grep -q 'TATE-FAIL' "$d/$name.log" 2>/dev/null; then
      fail "$name-log-assertions" "$d/$name.log"
    elif grep -q 'TATE-PASS' "$d/$name.log" 2>/dev/null; then
      echo "PASS: $name-log-assertions ($(grep -c 'TATE-PASS' "$d/$name.log") assertions)"
    else
      fail "$name-log-assertions" "$d/$name.log"
    fi
  done
  d=$(outdir_for t8 tcy-star-error)
  pdflatex -interaction=nonstopmode -output-directory="$d" \
    tests/fixtures/pdflatex-tate/tcy-star-error.tex >"$d/compile.out" 2>&1
  if grep -q 'TATE-FAIL' "$d/tcy-star-error.log" 2>/dev/null; then
    fail "tcy-star-error-log-assertions" "$d/tcy-star-error.log"
  elif grep -q 'is not allowed in yoko mode' "$d/tcy-star-error.log" 2>/dev/null \
    && grep -q 'direction.of.an.unknown.box' "$d/tcy-star-error.log" 2>/dev/null \
    && grep -q 'TATE-PASS' "$d/tcy-star-error.log" 2>/dev/null; then
    echo "PASS: tcy-star-error-log-assertions ($(grep -c 'TATE-PASS' "$d/tcy-star-error.log") assertions + 2 expected errors)"
  else
    fail "tcy-star-error-log-assertions" "$d/tcy-star-error.log"
  fi
  # T4→P6: pdflatex-tate-math.tex のアサーションは「測定シフト vs
  # 独立計算した δ 式（plcore adjustbaseline と同一式を fixture 内で
  # 再実装）」に改訂済み（旧 0.343zw 実装定数との自己申告比較は撤去）。
  # everymath 1回・mathsurround 1対・境界グルー・禁則はこのフィクスチャが、
  # raw box ClassError と one-shot 副作用は math-* フィクスチャ群が担う。
  d=$(outdir_for t8 pdflatex-tate-math)
  run "tate-pdflatex-tate-math" "$d" pdflatex \
    tests/fixtures/pdflatex-tate-math.tex
  if grep -q 'TATE-FAIL' "$d/pdflatex-tate-math.log" 2>/dev/null; then
    fail "pdflatex-tate-math-log-assertions" "$d/pdflatex-tate-math.log"
  elif grep -q 'TATE-PASS' "$d/pdflatex-tate-math.log" 2>/dev/null; then
    echo "PASS: pdflatex-tate-math-log-assertions ($(grep -c 'TATE-PASS' "$d/pdflatex-tate-math.log") assertions)"
  else
    fail "pdflatex-tate-math-log-assertions" "$d/pdflatex-tate-math.log"
  fi
  # ---- P6: 一回実行契約（everymath/everydisplay/mathmc/mbox/amstext） ----
  d=$(outdir_for t8 pdflatex-tate-math-oneshot)
  run "tate-pdflatex-tate-math-oneshot" "$d" pdflatex \
    tests/fixtures/pdflatex-tate/pdflatex-tate-math-oneshot.tex
  if grep -q 'TATE-FAIL' "$d/pdflatex-tate-math-oneshot.log" 2>/dev/null; then
    fail "pdflatex-tate-math-oneshot-log-assertions" "$d/pdflatex-tate-math-oneshot.log"
  elif [ "$(grep -c 'TATE-PASS' "$d/pdflatex-tate-math-oneshot.log" 2>/dev/null)" = 6 ]; then
    pass "pdflatex-tate-math-oneshot-log-assertions (6 assertions)"
  else
    fail "pdflatex-tate-math-oneshot-log-assertions" "$d/pdflatex-tate-math-oneshot.log"
  fi
  # ---- P6: raw primitive box 境界（ClassError 2件を含むため halt なし） ----
  d=$(outdir_for t8 pdflatex-tate-math-rawbox)
  pdflatex -interaction=nonstopmode -output-directory="$d" \
    tests/fixtures/pdflatex-tate/pdflatex-tate-math-rawbox.tex >"$d/compile.out" 2>&1
  if grep -q 'TATE-FAIL' "$d/pdflatex-tate-math-rawbox.log" 2>/dev/null; then
    fail "pdflatex-tate-math-rawbox-log-assertions" "$d/pdflatex-tate-math-rawbox.log"
  elif grep -q 'TATE-PASS: LEGAL' "$d/pdflatex-tate-math-rawbox.log" 2>/dev/null \
    && grep -q 'TATE-PASS: RAWERR' "$d/pdflatex-tate-math-rawbox.log" 2>/dev/null \
    && grep -q 'TATE-PASS: VBOXERR' "$d/pdflatex-tate-math-rawbox.log" 2>/dev/null \
    && grep -q 'raw~primitive~box.*hbox' "$d/pdflatex-tate-math-rawbox.log" 2>/dev/null \
    && grep -q 'raw~primitive~box.*vbox' "$d/pdflatex-tate-math-rawbox.log" 2>/dev/null \
    && grep -q 'Replace~it~with' "$d/pdflatex-tate-math-rawbox.log" 2>/dev/null; then
    pass "pdflatex-tate-math-rawbox-log-assertions (3 assertions + 2 expected ClassErrors)"
  else
    fail "pdflatex-tate-math-rawbox-log-assertions" "$d/pdflatex-tate-math-rawbox.log"
  fi
  # ---- P6: moving argument（section/TOC/mark/bookmark/eqref; 2パス） ----
  mvd=$(outdir_for t8 pdflatex-tate-math-movarg)
  mv_rc=0
  for passno in 1 2; do
    if ! run_compile x "$mvd" pdflatex \
         tests/fixtures/pdflatex-tate/pdflatex-tate-math-movarg.tex; then
      mv_rc=1
    fi
  done
  if grep -q 'Label(s) may have changed' "$mvd/pdflatex-tate-math-movarg.log" 2>/dev/null; then
    mv_rc=1
  fi
  if grep -q 'Reference `eq:mv'"'"' on page' "$mvd/pdflatex-tate-math-movarg.log" 2>/dev/null; then
    mv_rc=1
  fi
  # しおり: 数式を含む見出しの PDF 文字列（hyperref math fallback）が
  # UTF-16BE で .out に残る。数式部分 a+b は \000a\000+\000b として
  # 現れるため、その存在で検査する（日本語部分の byte 並びは
  # フォント/normalizer に依存させない）。
  if ! grep -q '\\000a\\000+\\000b' "$mvd/pdflatex-tate-math-movarg.out" 2>/dev/null; then
    mv_rc=1
  fi
  if ! grep -q 'TATE-PASS: BODY' "$mvd/pdflatex-tate-math-movarg.log" 2>/dev/null; then
    mv_rc=1
  fi
  if [ "$mv_rc" -ne 0 ]; then
    fail "pdflatex-tate-math-movarg (section/mark/bookmark/eqref)" "$mvd/compile.out"
  else
    pass "pdflatex-tate-math-movarg (section/mark/bookmark/eqref, 2 passes, refs resolved)"
  fi
  # boxdump（\showbox の ! OK のため -halt-on-error 不使用; END マーカで成立確認）
  d=$(outdir_for t8 tate-boxdump)
  pdflatex -interaction=nonstopmode -output-directory="$d" \
    tests/fixtures/pdflatex-tate-boxdump.tex >"$d/compile.out" 2>&1
  if ! grep -q 'TATE-GALLEY-END' "$d/pdflatex-tate-boxdump.log" 2>/dev/null; then
    fail "tate-boxdump-compile" "$d/compile.out"
  elif python3 tests/check-tate-boxdump.py "$d/pdflatex-tate-boxdump.log" \
       >"$d/boxdump.out" 2>&1; then
    pass "tate-boxdump-kinsoku"
  else
    fail "tate-boxdump-kinsoku" "$d/boxdump.out"
  fi

  # ---- T8b: 縦中横（\tatechuyoko）通常ゲート（P5 昇格済み） ----
  # 仕様: \tatechuyoko{12} は縦組みで直立・1zw正規化（advance=1zw・
  # cross=体幅半分ずつ・baseline=進行起点; uplatex showbox 実測契約）、
  # star 形は縦組みでも同一構造・横組みでは透過、横組み非star形は
  # ClassError。P5 で \jlreq@iftdir が live 化し gate は PASS する。
  tcy_d=$(outdir_for t8b tcy-basic)
  tcy_rc=0
  if ! run_compile x "$tcy_d" pdflatex \
       tests/fixtures/pdflatex-tate/tcy-basic.tex; then
    tcy_rc=1
  fi
  if [ -f "$tcy_d/tcy-basic.pdf" ]; then
    python3 tests/check-tatechuyoko.py "$tcy_d/tcy-basic.pdf" \
      >"$tcy_d/tcy.out" 2>&1 || tcy_rc=1
  else
    tcy_rc=1
  fi
  if [ "$tcy_rc" -eq 0 ]; then pass "tatechuyoko-basic"; else
    fail "tatechuyoko-basic" "$tcy_d/compile.out"; fi
fi

# ===========================================================================
echo ""
echo "== サマリ =="
echo "workdir: $OUT"
echo "FAILED: $FAILED"
echo "XFAIL:  $XFAILED${XFAIL_NAMES:+ ($XFAIL_NAMES )}"
echo "XPASS:  $XPASSED${XPASS_NAMES:+ ($XPASS_NAMES )}"
if [ "$XPASSED" -gt 0 ]; then
  echo ""
  echo "XPASS 検出: 以下の既知不良は実装で解消された可能性があります。"
  echo "  昇格手順: KNOWN_DEFECTS から削除し、該当検査を通常セクションへ"
  echo "  移動した上で docs/pdftex-tests.md を更新してください:"
  for n in $XPASS_NAMES; do echo "    - $n"; done
  exit 1
fi
if [ "$FAILED" -eq 0 ]; then
  echo ""
  echo "ALL TESTS PASSED${XFAILED:+ (with $XFAILED expected XFAIL${XFAILED:+s}:$XFAIL_NAMES )}"
  exit 0
else
  echo ""
  echo "$FAILED TEST(S) FAILED"
  exit 1
fi

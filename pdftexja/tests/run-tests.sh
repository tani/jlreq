#!/bin/sh
# pdfTeX-ja standalone test suite (no jlreq): compiles the fixtures with
# the in-tree package (make fonts first) and checks the PTJTEST markers.
cd "$(dirname "$0")/.." || exit 1
P="$(pwd)"
TEXINPUTS=".:$P//:${TEXINPUTS:+$TEXINPUTS}"
TEXFONTS="${TEXFONTS:+$TEXFONTS}$P/fonts:"
TEXENCS="${TEXENCS:+$TEXENCS}$P/fonts:"
export TEXINPUTS TEXFONTS TEXENCS
OUT=$(mktemp -d "${TMPDIR:-/tmp}/pdftexja-tests.XXXXXXXX") || exit 1
echo "workdir: $OUT"
FAILED=0
for f in tests/fixtures/*.tex; do
  n=$(basename "$f" .tex)
  d="$OUT/$n"; mkdir -p "$d"
  ok=1
  for pass in 1 2; do
    pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$d" "$f" \
      >"$d/compile.out" 2>&1 || ok=0
  done
  if [ $ok -eq 0 ]; then
    echo "FAIL: $n (compile; see $d/compile.out)"; FAILED=$((FAILED+1)); continue
  fi
  grep "PTJTEST-PASS" "$d/$n.log" | sed 's/^PTJTEST-/  /'
  if grep -q "PTJTEST-FAIL:" "$d/$n.log"; then
    grep "PTJTEST-FAIL:" "$d/$n.log"
    echo "FAIL: $n"; FAILED=$((FAILED+1)); continue
  fi
  case $n in
    yoko-basic|tate-basic)
      if ! pdftotext "$d/$n.pdf" - | tr -d '\n ' | grep -q '句読点'; then
        echo "FAIL: $n (text extraction)"; FAILED=$((FAILED+1)); continue
      fi;;
  esac
  echo "PASS: $n"
done
echo "FAILED: $FAILED"
[ $FAILED -eq 0 ]

#!/usr/bin/env python3
"""行頭禁則検証: 実PDFのbboxから、閉じ約物（」』）。，・？！…‥）が
行頭（左余白 x<100pt）に来ていないかを機械判定する。
Usage: check-kinsoku.py <pdf> [<pdf> ...]
"""
import subprocess, sys, re

PUNCT = set('」』）。，・？！…‥')

def check(pdf):
    out = subprocess.run(['pdftotext', '-bbox', pdf, '-'],
                        capture_output=True, text=True).stdout
    rows = {}
    for line in out.splitlines():
        m = re.search(r'xMin="([0-9.]+)" yMin="([0-9.]+)"[^>]*>([^<]+)<', line)
        if m:
            rows.setdefault(round(float(m.group(2))), []).append(
                (float(m.group(1)), m.group(3)))
    bad = []
    for y, ws in sorted(rows.items()):
        ws.sort()
        t = ws[0][1]
        if t and t[0] in PUNCT and ws[0][0] < 100:
            bad.append(t[:3])
    return bad

ok = True
for pdf in sys.argv[1:]:
    bad = check(pdf)
    if bad:
        print(f'FAIL {pdf}: line-head punctuation {bad}')
        ok = False
    else:
        print(f'PASS {pdf}')
sys.exit(0 if ok else 1)

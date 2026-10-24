#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""DVI/PDF baseline normalizer (tests/reference/baselines 用).

出力ファイルから実行環境由来の可変成分のみを取り除き、バイト比較可能な
正規化コピーを stdout へ書く。docs/pdftex-tests.md の正規化契約と同一:

  DVI (platex/uplatex): comment フィールドの "YYYY.MM.DD:MMDD" タイム
    スタンプを DATE に置換。
  PDF (lualatex): /CreationDate /ModDate の "D:YYYYMMDDHHmmSS..." を
    DATE に、/ID [\...] を /ID XXX に置換。

sed は DVI/PDF の非 UTF-8 バイト列で不正エンコードとして空出力を返す
環境があるため、バイト列処理は本スクリプトで行う。
Usage: normalize-output.py <dvi|pdf> <file>
"""
import re
import sys

DVI_TS = re.compile(rb"[0-9]{4}\.[0-9]{2}\.[0-9]{2}:[0-9]{4}")
PDF_DATE = re.compile(rb"(D:[0-9]{14}[+\-Zz0-9'\"/]*)")
PDF_ID = re.compile(rb"/ID \[[^]]*\]")


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: normalize-output.py <dvi|pdf> <file>\n")
        return 2
    kind, path = sys.argv[1], sys.argv[2]
    data = open(path, "rb").read()
    if kind == "dvi":
        out = DVI_TS.sub(b"DATE", data)
    elif kind == "pdf":
        out = PDF_DATE.sub(b"(DATE)", data)
        out = PDF_ID.sub(b"/ID XXX", out)
    else:
        sys.stderr.write("normalize-output.py: unknown kind %r\n" % kind)
        return 2
    sys.stdout.buffer.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())

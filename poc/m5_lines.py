#!/usr/bin/env python3
"""M5 数値比較: uplatex 参照系と pdflatex バックエンドの行分割（ブレー
クポイント列）を pdftohtml -xml 出力から再構成して比較する。
Usage: m5_lines.py <up.xml> <pdf.xml>
出力: 段落ごとの行分割表 + 分岐点の一覧（オフセット・周辺文字）。
"""
import re, sys

def runs(path):
    out = []
    for m in re.finditer(
        r'<text top="(\d+)" left="(\d+)" width="(\d+)" height="\d+" font="\d+">([^<]*)</text>',
        open(path, encoding='utf-8').read()):
        top, left, width, txt = m.groups()
        out.append((int(top), int(left), int(width), txt.replace(' ', '')))
    return out

def to_lines(rs, ytol=6):
    rs = sorted(rs)
    lines = []  # (top, [(left,width,txt)])
    for top, left, width, txt in rs:
        if not txt:
            continue
        placed = False
        for ln in lines:
            if abs(ln[0] - top) <= ytol:
                ln[1].append((left, width, txt)); placed = True; break
        if not placed:
            lines.append([top, [(left, width, txt)]])
    lines.sort(key=lambda l: l[0])
    # concat per line in x order; record x0, x1
    res = []
    for top, items in lines:
        items.sort()
        text = ''.join(t for _, _, t in items)
        x0 = items[0][0]
        x1 = max(l + w for l, w, _ in items)
        res.append((top, x0, x1, text))
    return res

def pagesplit(lines):
    # ページ境界: top が大きくリセットされる点で切る
    pages, cur, prev = [], [], -10**9
    for ln in lines:
        if prev > -10**9 and ln[0] < prev - 300:
            pages.append(cur); cur = []
        cur.append(ln); prev = ln[0]
    if cur:
        pages.append(cur)
    return pages

# 段落はコーパスと同じ認識で切る（空行に相当する top ギャップで分ける）
def paras(lines):
    out, cur, prev = [], [], None
    for ln in lines:
        if prev is not None and ln[0] - prev > 60:
            out.append(cur); cur = []
        cur.append(ln); prev = ln[0]
    if cur:
        out.append(cur)
    return out

def analyze(path, name):
    rs = runs(path)
    pages = pagesplit(to_lines(rs))
    all_lines = [ln for pg in pages for ln in paras(pg)]
    flat = []
    for pg in pages:
        flat += paras(pg)
    print(f'== {name}: {len(flat)} 段落ブロック')
    results = []
    for p in flat:
        txt = ''.join(l[3] for l in p)
        seq, off = [], 0
        for top, x0, x1, t in p:
            seq.append((off, off + len(t), t[0] if t else '', t[-1] if t else '', x1))
            off += len(t)
        results.append((txt, seq))
    return results

def main():
    up = analyze(sys.argv[1], 'uplatex')
    pd = analyze(sys.argv[2], 'pdflatex')
    for i, ((utxt, useq), (ptxt, pseq)) in enumerate(zip(up, pd), 1):
        tag = 'P%d' % i
        if utxt != ptxt:
            print(f'{tag}: 文字列不一致 up={len(utxt)} pdf={len(ptxt)}')
        print(f'{tag}: up {len(useq)}行 vs pdf {len(pseq)}行')
        n = max(len(useq), len(pseq))
        divs = []
        for j in range(n):
            a = useq[j] if j < len(useq) else None
            b = pseq[j] if j < len(pseq) else None
            mark = '' if a != b else ''
            if a != b:
                divs.append(j)
            print(f'  L{j+1}: up={a and (a[1], a[3], a[4])}  pdf={b and (b[1], b[3], b[4])}')
        if divs:
            # 最初の分岐点周辺
            j = divs[0]
            u_end = useq[j][1] if j < len(useq) else None
            p_end = pseq[j][1] if j < len(pseq) else None
            ctx_u = utxt[max(0, (u_end or 0)-6):(u_end or 0)+6] if u_end else ''
            ctx_p = ptxt[max(0, (p_end or 0)-6):(p_end or 0)+6] if p_end else ''
            print(f'  *** 最初の分岐: 行{j+1} 末: up末[{ctx_u}] vs pdf末[{ctx_p}]')

if __name__ == '__main__':
    main()

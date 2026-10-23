FONT_DIS = __import__('sys').argv[1] if len(__import__('sys').argv)>1 else 'u30.dis'
#!/usr/bin/env python3
"""Full Type1 charstring interpreter (charstring-only ops) -> ink bbox.

Em units: FontMatrix 0.001, so charstring units are 1/1000 em (1em=1zw).
Handles: hsbw sbw rmoveto hmoveto vmoveto rlineto hlineto vlineto
rrcurveto hvcurveto vhcurveto rrcurvebox flex variants via subr expansion.
callsubr is expanded from the subroutine index (t1disasm keeps
/subr entries in the Private dict).
"""
import re, sys, json

# pass 1: collect subrs from the Private dict section
subrs = {}
in_private = False
cur_sub = None
cur_body = []
for line in open(FONT_DIS):
    s = line.strip()
    if s.startswith('dup') and in_private:
        m = re.match(r'^dup\s+(\d+)\s+(-?[\d.]+)\s+RD\s+(-?\+?)', s)
        m2 = re.match(r'^dup\s+(\d+)\s+(-?[\d.]+)\s+', s)
        if m2 and cur_sub is None and not s.startswith('dup 0 '):
            pass
    if s == '/Subrs' or s.startswith('/Subrs'):
        in_private = True
        continue
    if in_private:
        m = re.match(r'^dup\s+(\d+)\s+', s)
        if m:
            cur_sub = int(m.group(1)); cur_body = []
            continue
        if cur_sub is not None:
            if s == 'NP' or s == '|-' or s.startswith('ND'):
                subrs[cur_sub] = cur_body; cur_sub = None; cur_body=[]
            elif s and not s.startswith('%'):
                cur_body.append(s)

print("subrs collected:", len(subrs), file=sys.stderr)

# pass 2: interpret glyph charstrings with subr expansion
glyphs = {}
cur = None
x = [0.0, 0.0]
calldepth = 0
lineiter = None

def bb(px, py):
    b = cur['b']
    if px < b[0]: b[0] = px
    if py < b[1]: b[1] = py
    if px > b[2]: b[2] = px
    if py > b[3]: b[3] = py

def run(tokens):
    global x
    st = []
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if re.match(r'^-?[\d.]+$', t):
            st.append(float(t)); i += 1; continue
        op = t
        if op == 'hsbw':
            pass
        elif op == 'sbw':
            pass
        elif op == 'rmoveto' and len(st) >= 2:
            x[0]+=st[-2]; x[1]+=st[-1]; bb(x[0],x[1]); st=[]
        elif op == 'hmoveto' and len(st) >= 1:
            x[0]+=st[-1]; bb(x[0],x[1]); st=[]
        elif op == 'vmoveto' and len(st) >= 1:
            x[1]+=st[-1]; bb(x[0],x[1]); st=[]
        elif op == 'rlineto' and len(st) >= 2:
            x[0]+=st[-2]; x[1]+=st[-1]; bb(x[0],x[1]); st=[]
        elif op == 'hlineto' and len(st) >= 1:
            x[0]+=st[-1]; bb(x[0],x[1]); st=[]
        elif op == 'vlineto' and len(st) >= 1:
            x[1]+=st[-1]; bb(x[0],x[1]); st=[]
        elif op == 'rrcurveto' and len(st) >= 6:
            a,b_,c,d,e,f = st[-6:]
            bb(x[0]+a, x[1]+b_); bb(x[0]+a+c, x[1]+b_+d)
            x[0]+=a+c+e; x[1]+=b_+d+f; bb(x[0],x[1]); st=[]
        elif op == 'hvcurveto' and len(st) >= 4:
            a,b_,c,d = st[-4:]
            bb(x[0]+a, x[1]); bb(x[0]+a, x[1]+b_)
            x[0]+=a+c; x[1]+=b_+d; bb(x[0],x[1]); st=[]
        elif op == 'vhcurveto' and len(st) >= 4:
            a,b_,c,d = st[-4:]
            bb(x[0], x[1]+a); bb(x[0]+b_, x[1]+a)
            x[0]+=b_+d; x[1]+=a+c; bb(x[0],x[1]); st=[]
        elif op == 'callsubr' and len(st) >= 1:
            idx = int(st[-1]); st=[]
            body = subrs.get(idx)
            if body:
                for ln in body:
                    toks2 = ln.split()
                    if toks2: run(toks2)
        elif op in ('closepath','endchar','hstem','vstem','hstem3','vstem3',
                    'dotsection','seac','div','dup','roll','index','pop',
                    'callothersubr','setcurrentpoint','hsbw'):
            st = []
        else:
            st = []
        i += 1

for line in open(FONT_DIS):
    s = line.strip()
    m = re.match(r'^/(\S+)\s*\{', s)
    if m:
        cur = {'name': m.group(1), 'b':[1e9,1e9,-1e9,-1e9]}
        x=[0.0,0.0]
        continue
    if cur is None: continue
    if s.startswith('}'):
        if cur['b'][0] <= cur['b'][2]:
            glyphs[cur['name']] = cur['b']
        cur=None; continue
    toks = s.split()
    if toks: run(toks)

json.dump(glyphs, open('bboxes.json','w'))
print("glyphs with ink:", len(glyphs), file=sys.stderr)

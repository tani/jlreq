# pdfTeX-ja 内部設計（pdftexja-internals）

pdfTeX-ja（`pdftexja`）の内部構造。公開APIは `../README.md`，jlreq から見た
対応状況は jlreq リポジトリの `docs/pdftex-compatibility.md`。

> 経緯: 本実装は当初 jlreq の pdfTeX バックエンド（`jlreq-pdftex*.sty`，内部接頭辞
> `\jlreqpdf@`）として作られ，その後 LuaTeX-ja と jlreq の関係にならって
> 独立パッケージ pdfTeX-ja（内部接頭辞 `\ptj@`）と，それを使う jlreq に分割した。
> 以下の実測記録・歴史的経緯の記述は分割前のものを名前だけ読み替えて残している
> （「jlreq.cls の d 分岐」は現在は pdftexja の公開APIを呼ぶだけの薄い層）。

## 全体構造

```text
pdftexja.sty               … 入口（パッケージオプション）
├── pdftexja-core.sty      … 土台（フォント・CJK状態・単位・方向・出力ラッパ・
│                              数式キャプチャ・label key・漢字制御綴・tombow）
├── pdftexja-jfmglue.sty   … 組版規則（JFMグルー・禁則・和欧文間隔・行末調整・縦グリフ）
├── pdftexja-ruby.sty      … ruby.sty provider 適合（自動）
├── ptjfm-<name>.def       … JFMデータ（pdftexja-jfmconv.lua が LuaTeX-ja の
│                              jfm-<name>.lua から生成; 既定 ujis/ujisv）
├── pdftexja-kinsoku.tex   … 既定の禁則・jaxspmode 表（ltj-kinsoku.tex から生成）
└── fonts/pdftexja-fontprofile-<set>.def + 補助縦TTF/TFM/enc
pdftexja-adjust.sty        … 優先順位付き伸縮の段落 ptjparagraph（任意）

jlreq.cls（pdflatex） → \RequirePackage[jfm=jlreq…,tjfm=jlreqv…,…]{pdftexja}
                        + ptjfm-jlreq*.def（jlreq 側が生成・同梱する12変種）
```

LuaTeX-ja との対応: pdftexja ≒ luatexja-core，ptjfm-*.def ≒ jfm-*.lua（実行時
Lua が無いため事前変換），pdftexja-adjust ≒ luatexja-adjust（ただし環境単位），
pdftexja-ruby は luatexja-ruby ではなく CJK バンドルの ruby.sty への適合層。

## pdftexja-core.sty（土台）

1. **bxcjkjatype[<fontset>,noCJKpunct,scale=<scale>]** をロード。CJKutf8（UTF-8
   デコーダ）＋フォント（既定 IPAex Type 1: C70/ipxm,ipxg）。`noCJKpunct`は約物処理の
   二重適用防止（JFM規則が空きを管理するため）。
2. **always-on CJK状態**: `\CJK@global/\CJK@active/\CJK@local` を `\global` に
   差し替え，`\CJK@envStart{}{UTF8}{<family>}` + `\CJKspace` を一度発行。以後UTF-8の
   多バイト文字がファイル全体で有効になり，クラスロード中の `\hbox{阿}` 等の
   和文リテラルがそのまま評価できる。
   - 副作用: 漢字制御綴（`\if西暦`等）が作れない→ `\ptjdefkanjics`（後述）。
   - `\makeatletter` 再発行必須（CJKの遅延ロードが catcode を戻すため）。
3. **単位エミュレーション**: `\zw`/`\zh` = `\ptj@zwreg`（dimenレジスタ）への
   マクロ。`2\zw` は plain TeX の `<factor><internal>` 構文で動作。
   `\ptj@zwreg` は `\size@update` に追加したフックで `\f@size × scale` として
   フォントサイズ変更に追従する（scale はパッケージオプション／`\ptjsetparameter`）。
   `\Cht/\Cdp/\Cwd/\Cvs/\Chs` を `\newdimen` で宣言。
4. **フォント**: `\mcfamily/\gtfamily/\mgfamily` は bxcjkjatype 任せ（C70系）。
   欧文NFSSは別系統。boldは `\CJKbold` をselectfontフックで `\f@series` 追跡して発行。
5. **単位の書き換え**: `\ptjconvertunits` が長さ指定のトークン列中の `<数字>zw` 等を
   `\zw` 等に置換する（クラスがオプション値に使う）。

## pdftexja-jfmglue.sty（組版規則）

1. **文字フック**: CJK.sty内部の `\CJKsymbol `（robust命令の内部）を
   `\AtBeginDocument` でラップ（bxcjkjatypeが再定義するためロード時では上書きされる）。
   全UTF-8経路がここに集約され，文字の「10進コードポイント = plane×256+バイト値」
   を受け取る（`\CJK@plane`は16進2桁 → `\ptj@setclassof` で復元）。
   後続覗きは `\CJK@ignorespaces` を受動化（`\@empty`）したうえで，4つのヘルパ
   （`\CJK@X`/`\CJK@XX`/`\CJK@XXX`/`\CJK@XXXX`）をラップし，ヘルパ自身の条件分岐が
   閉じた後に `\futurelet` が走る形で `\ptj@peek@a` を差し込む（pdftexja-jfmglue.sty:753–783）。
2. **状態機構**: `\ptj@lastclass`（0〜25のJFMクラス + 27=latin + 90=段落境界 +
   93=明示空白後）。段落開始（`para/begin`フック）で90へリセット。
3. **ペアグルー**: 生成データ `pair@<from>@<to>` は **マクロ呼び出し形式**
   `\ptj@pairfields{nat}{str}{shr}{ratio}{spri}{shpri}{knat}{kstr}{kshr}`
   で格納（`{{...}}`二重括弧形式は引数再括弧化で分割不能のため，この形式になった。
   TeXの引数取得は外括弧を剥がし置換時に再括弧化する）。
   - 定義ペア: **9フィールド全評価**。nat/str/shr は左右zwの
     two_paverage ブレンド（`b = zw_prev + r*(zw_cur - zw_prev)`，
     ltj-jfmglue.lua:812-857 と同一式，単一JFMなので両側同一のb）で
     実寸化。ratio/spri/shpri は評価して spri/shpri を
     `\ptj@pairspri/@pairshpri` へ記録（ptjparagraph の
     前提データ）。kanjiskip付随成分 knat/kstr/kshr はフラグ付きで
     現行 `\jlreqkanjiskip` から別glueノードとして発行
     （`\ptj@emitkcomp`）。
   - 未定義ペア: **現行値フォールバック**——固定 0/.25zw 定数を廃止し，
     現行 `\jlreqkanjiskip`/`\jlreqxkanjiskip` のグルー指定をそのまま
     （fil order も保持）。
   - **行末調整**: 直前クラスの end_adjust は
     行中のshrink畳み込みを行わず，**候補列** `kern(e1) penalty(p)
     kern(e2-e1) penalty(p) ... kern(-em) penalty(10000)` + ペアグルー
     として発行（`\ptj@eawalk`，ltj-adjust.lua insert_lineend_kern
     と同一構造。0候補は列内に保持，行中は正味0，行末breakだけが選択
     候補eを行に残す）。境界penaltyは p=post(prev)+pre(next) を
     全候補へ一括適用（`\ptj@boundaryp`）。禁則(p>=10000)時も
     グルーの伸縮成分はkern化で捨てない（kernmode 固定カーン処理は廃止）。
4. **禁則**: クラス番号テーブルで行頭/行末禁則ペナルティ10000を境界penalty
   p に合成（jlreq.cls の setpre/postbreakpenalty aux はこの表へ
   実書き込みし，`\jlreqsetup` の禁則キーが実効する）。
5. **和欧文間**: 境界で `\jlreqxkanjiskip`（0.25zw + 0.25zw - 0.125zw）。
   xsp規則（かな側のみ許容等）もクラスフラグで再現。
   **段落先頭のLA→JA境界**: lastclass=90 かつ `\lastnodetype=0`
   （char ノード＝先行欧文走行）のとき先行をクラス27として扱う
   （判定は CJK@X helper head の `\ptj@latadj` で実行——
   デコーダ内の font whatsit により `\pre` 内では lastnodetype が
   常に -1 になるため。latin-adjacency.tex 7アサーション）。
6. **局所方向（2026-10-24 実装、後に改訂）**: 方向状態 `\ptj@dir`
   （count, 0=yoko/1=tate）は begin document で `\if@tate` から播種
   （`ptj@setmaindir`）。判定:
   `\jlreqpdftex@ifydir/@iftdir`（バックエンド内部）と
   `\jlreq@ifydir/@iftdir`（jlreq.cls d 分岐, `\ifnum1=\ptj@dir\fi`
   形式——expl3構文下で空白が食われるため被比較数を末尾に置く）。
   （旧 frame tuple による `\ptj@dir` の保存復帰は
   frame 機構ごと撤去——下の semantic frames 参照。バックエンド箱工場・
   theindex は nest ガード/page フラグで方向を自前管理する。）
   **箱工場** `pdftexja-core.sty`:
   `\ptj@yokobox{body}` / `\ptj@tatebox{body}`（同方向なら恒等）
   および `\ptj@yokobox@strut{ht}{dp}{body}`（body の ht/dp を指定値に
   固定してから埋める。縦中横の 1zw 正規化用）。交叉埋め込み
   `\ptj@embed@yoko@in@tate`（`\rotatebox{90}` 依存の明示算術:
   寸法事前退避→回転→`\kern-ht`→`\lower w/2`→`\wd=ht+dp`・`\ht=\dp=w/2`）は
   pTeX の yoko-in-tate 自動埋め込みと同一契約（uplatex showbox・PDF bbox
   実測: advance=ht+dp, cross=体幅半分ずつ, baseline=進行起点）。
   **安全契約**: 未知 box の方向照会 `\ptj@boxdir` は ClassError
   （無告知 yoko fallback なし。工場製 box の再利用は「現 frame の方向」が
   契約——pdfTeX に box 属性は存在しない）。
   **ページ方向** `\ptj@pagedir@count` + `\ptj@pagedir{0|1}`:
   出荷回転は `\if@tate && pagedir=1` のときのみ掛かる（theindex 等の
   横組み論理ページは回転なしで出荷）。フラグは縦出力ラッパ
   （次節）が読む。cls theindex d 分岐は
   `clearpage → pagedir=0 → dir=0 → \hsize=\textheight`（pTeX の \yoko ページ
   の寸法役割交換, uplatex 実測: 2段幅=(textheight-colsep)/2）を行い、
   終端で `pagedir=1 → dir=1 → \hsize=\textwidth` を復帰。
   ゲート: tests/fixtures/pdflatex-tate/{dir-roundtrip,dir-callers,
   dir-index-yoko,tcy-digits,tcy-fontchange,tcy-star-error}.tex
   （T8 が TATE-PASS/TATE-FAIL・エラー文言を検査）。

## 出力ルーチンと semantic frames（2026-10-24 追記）

### 薄い出力ラッパ（kernel 本体丸写しの撤去）

かつてはカーネル `\@outputpage` の本体をソースに丸写しし、家具行の幅を
`\hb@xt@\textheight` に差し替えていたが撤去した。現行構成
（pdftexja-core.sty「tate output」節）:

- **保存**: begin document でその時点のカーネル `\@outputpage` を
  `\ptj@saved@outputpage` に `\let` して呼び出す。**d+tate のみ**
  インストール（yoko/p/u/l は一切通さない）。
- **ラッパの仕事は2つだけ**:
  1. `pagedir=1` のとき本文箱 `\@outputbox` を `\rotatebox{-90}` で
     回転して戻す（回転はこの一箇所。yoko 論理ページ=theindex は無回転）。
  2. 家具行の幅: カーネル本体は `\hb@xt@\textwidth{\@thehead}` で柱・
     ノンブル行を組むが、縦組みページの最終枠巾は版面高なので、
     saved 本体の実行中だけ `\textwidth\textheight`（局所 group）。
     **論理寸法（版面巾 = 行長）と最終枠巾（版面高）の区別はこの一箇所に
     集約**し、散在する raise/kern や寸法上書きはしない。
- カーネルの進化（tagging socket、catcode ブロック——旧コピーはこれを
  落としていた、今後の修正）は自動的に追従する。build/page/* フック・
  kernel の hook 付き shipout・trimmarks の `\@tombowreset@@paper`
  （build/page/reset）は元実装内部でそのまま走る。
- ゲート: `out-hook-probe`（tate+yoko 各3ページで build/page/before・
  after・shipout/before が各ページ1回だけ発火）、`outputpage-copy-gone`
  （`\shipout `/`\@begindvi`/`\stepcounter{page}` の backend ソース内
  grep が0件であることを機械検査）。

### 縦組みの Cht/Cdp（論理寸法で縦家具計算）

`\hbox{阿}` の ht/dp は pdfTeX 縦組みではグリフ層の横組メトリクスに
なる（実測 Cht=8.8pt/Cdp=1.2pt）が、pTeX の `\cht/\cdp` は縦 JFM
class 0 の h/d（0.5/0.5zw = 5pt/5pt）。この差は
`oddsidemargin`/`topmargin`/`footskip` の縦組み幾何（`-Cht+Cdp` の項）
にそのまま混入し、uplatex 対照の一定オフセット（3.8pt）として
初期評価の「数ミリの家具由来オフセット」に残っていた。jlreq.cls の
測定直後に生成縦 JFM データ（`ptj@jfm@class@0` の h/d）×現在zw で
上書きする（`\ptj@tate@chtc@dp`）。実測: 修飾後
Cht=Cdp=5.0pt、縦家具オプション対照の余白差は 0.0000pt。

### savepos と論理行方向

`\pdfsavepos` が記録する座標は shipout 回転（cm）の**前**の内枠座標で
デザイン寸法（mag 不変）である（トンボ実測と同じ根拠。実測:
`\mag=1200` でも同一文書の raw `\pdflastxpos` は同一値）。
内枠の X 方向が縦組みの読み方向＝論理行方向なので、
`\jlreq@calc@current@linewidth` の d 分岐は縦組みでもそのまま論理行
方向の測定になる。aux の frame id は `\jlreq@reference@count` 連番
ラベル（`jlreq@rest@width.pos.X.<n>`）で、pass 2 が pass 1 の原点を
消費する。

数値表（2026-10-24 実測、いずれも pass 2 の確定値）:

| 対照項目 | pdfTeX | upLaTeX | mag=1200 (pdfTeX) |
|---|---|---|---|
| 割注前 current linewidth（20zw 行・6 セル） | 60.0pt | 60.0pt | 60.0pt |
| 割注前 rest linewidth | 140.0001pt | 140.0001pt | 140.0001pt |
| 割注行 linewidth | 200.0001pt | 200.0001pt | 200.0001pt |
| 合印（interlinear）挟み込みのペアグルー差分 | 0.0pt | 0.0pt | — |
| marginpar/遅延脚注マーカの行方向相対距離 | 160.0007pt | 160.0007pt | — |

**mag≠1000 の補正**: クラスの mag 補償（`\pdfhorigin=1truein`・側余白の
`−1truein`）で原点と側余白が物理 1in 基準に揃うため、計測式の末項も
`−1in`（デザイン）ではなく `−1truein`（物理）にした（jlreq.cls
d 分岐）。mag=1000 では 1truein=1in で無変換。これにより論理行
方向の current/rest は mag 不変（上表のとおり mag=1200 でも同一値）。

**PDF インクレベル対照**（`savepos-anchor-pdf` ゲート +
`tests/check-anchor-parity.py`、pymupdf、あ原点合わせ後。
2026-10-25 のフォローアップで脚注ブロック残差を閉じた後の実測）:

| 対照項目 | worst Δ |
|---|---|
| 本文グリフ走り（あ..こ、先頭行10字） | **0.0010pt**（ゲート閾値 0.1pt） |
| 脚注罫線位置 / 罫線長 / 罫線→本文列間隔 | **0.011pt**（10pt）/ **0.038pt**（12pt）（`footnote-parity` ゲート、閾値 0.5pt） |
| 脚注テキスト列頭（☆）・脚注内（１）マーク列頭 | **0.011pt**（10pt）/ **0.04pt**（12pt）（同上） |
| 行内合印（interlinear mark）オープナー（（＊） の （ | (+3.49, −1.42)pt — 1本文行に複数脚注があるときの**先頭列残差**（下記） |
| 複数脚注の2列目以降の列頭・列間隔 | **0.00pt**（fn2 列頭・列ピッチ 13.748pt が up と一致） |

**脚注ブロック残差の解決（2026-10-25）**: かつての「tate 脚注・合印
マイクロレイアウト」残差（旧実測: 罫線 −8.54pt / 脚注本文列頭 −1.72pt /
（１）マーク −3.71pt / 罫線→本文列 10.58 vs 17.40pt、いずれも 10pt。
合印オープナー (+1.49, +7.61)pt、脚注テキスト (−1.71, +2.39)/(−4.00,
+1.28)pt、脚注列間隔 11.458 vs 13.748pt）は、以下の独立した5原因の
重畳だった。いずれも uplatex を oracle に実測で特定・修正した:

1. **脚注罫線カーンの誤捕捉**（jlreq.cls 罫線定義）: クラス読込時の
   `\footnotesize` グループ内で `\size@update` が走らず `\jlreq@zh`
   が本文サイズのまま評価されるため、罫線後カーンが
   `1.5*(\baselineskip−10pt)=2.25pt` に誤捕捉されていた（uplatex は
   upTeX の `\zh` プリミティブがサイズ追従し 5.24995pt を捕捉）。
   d エンジンに限り `\ptj@zwreg=.8\jlreq@jafontsize` を明示して
   評価するようにした（uplatex の値とビット一致を実測確認）。
2. **補助縦フォントが現在サイズに追従しない**（pdftexja-core.sty）:
   補助 TFM を design size 10pt のまま `\font` していたため、
   footnotesize の縦約物（（）。 等）が 9.96pt で組まれ（uplatex は
   7.97pt）、挿入物行の高さがストラットではなくこの未スケール字形
   の ink で決まっていた。`at\ptj@zwreg`（selectfont で追従）で
   実寸化した。
3. **縦字形が横倒しに刷られていた**（pdftexja-jfmglue.sty vert 経路）:
   内枠は出荷回転（−90°）の**回転前**空間のため、内容はすべて +90°
   予備回転して組む必要がある（rot 経路は `\rotatebox{90}` で実施）。
   vert 経路（補助縦フォントの真縦字形）は素のまま描いていたため、
   **全補助縦字形が最終ページで 90° 横倒し**だった（実測: 脚注 （ の
   形状が native と不一致）。rot 経路と同じ回転をかけた。
4. **半角クラス縦字形の置き型**（同 vert 経路）: native vf（jlreq-v）は
   全角アドバンスの字形を `−(1zw−セル幅)` だけ行頭側へずらして描き、
   ink がセルの行頭端から全角分だけ次側へはみ出る（uplatex 実測:
   （ セル [c, c+0.5em] に対し ink [c, c+1em]）。同じずらしを
   ボックス内先頭カーンで再現し、ht/dp も JFM クラス値（縦組 0.5/0.5）
   で正規化した（`\ptj@splitcls` が h/d も保存）。
5. **挿入物の行内配置**（jlreq.cls `\@makefntext` d+tate ラッパ）:
   pdfTeX 側の縦字形ボックスは ht=エム/dp=0 の規約（本文は出荷回転の
   第一行カーンで補正済み）のため、そのままでは挿入物内のエム箱が
   行基準線から 0.5zh 行頭側に置かれる。挿入物組版中のみ
   `\ptj@insctx` フラグで縦字形の ht/dp を JFM クラス値に
   正規化させ（折返し行・複数段落脚注を含む全行で有効）、ページ最初
   の脚注には行頭側に高さ `footnotesep+0.5zh` のストラットを、
   各脚注段落には行末に深さ `0.5842*baselineskip` のストラットを
   足して、罫線位置・本文列頭を native に合わせた（10pt/12pt で
   0.01pt 一致を gate 固定）。

**残る既知残差（2件、いずれも登録済み・未解決）**:

1. **複数脚注段落時の先頭段列頭**: 1つのページに複数の脚注段落が
   あるとき、**先頭**脚注段落の列頭が +4.95pt（10pt）行末側にずれる
   （2段落目以降の列頭・列間隔は完全一致）。先頭段落にだけ足す高さ
   ストラットが、下に更に段落がある場合の先頭段の位置に影響する
   ため。単一脚注（`footnote-parity` ゲートのパリティ測定対象）は
   完全一致。複数段落時の先頭段は今後の課題。
2. **行内合印オープナーの先頭列残差**: 1本文行に複数脚注がある
   ときの（＊）オープナー（合印チェーン）は (+3.49, −1.42)pt
   （旧実測 (+1.49, +7.61) から改善、ただし 0.1pt 閾値未達）。
   複数脚注の **fn2 列目以降**の列頭は 0.00pt 完全一致。先頭列の
   合印チェーンは今後の課題（fn1 列だけに影響する合印 − ストラット
   干渉）。


### tate TOC「Leaders not followed by proper glue」——解決

報告のあった「2パス目で必ず落ちる」不良は**2つの独立した原因**の重畳:

1. **frame-pop `\aftergroup`**: 旧 semantic frames は各 box の
   入口で frame を push し、閉じ時に `\aftergroup\ptj@frame@pop` で
   pop していた。`\aftergroup` は box 直後に**実代入トークン**を挿入する
   が、`\leaders\hbox{...}<glue>` は box と glue の間に展開不能トークンを
   許さない——**全リーダー箱**（TOC ドット、ユーザーの `\leaders`/
   `\xleaders`）が内容に関係なく落ちた（yoko/tate・CJK 有無無関係;
   article+rules.sty 単独でも再現）。これが「旧実装以来再現」の正体。
2. **数式内部ゲートの引数形**: `\ptj@math@internal{...}` は必ず
   グループ引数を取るため `{\leaders\hbox{..}}\hfill` の形を作り、
   リーダー箱と glue の間に**群終端**が入る。`\leaders` の glue 走査は
   群終端を越えられない——**純TeXでも再現**する（plain article +
   `{\leaders\hbox{a}}\hfill`）。

**修正**: (1) は semantic frames の全面再構成（下記）で `\aftergroup` を
撤去。(2) はグループを作らない `\ptj@math@internal@on/@off` 対命令
に置き換え（jlreq.cls `\@dottedtocline`）。ゲート: `toc-twopass`
（tate・subsection 入り・2パス双方で Leaders エラーゼロ + TOC-PASS マーカ）。

### semantic frames の現行構成（旧設計からの置換）

box 境界の状態隔離は2つの機構で行い、**どちらも `\aftergroup` を使わない**:

- **入口**: everyhbox/everyvbox に前置した `\ptj@box@enter` が
  `\ptj@box@neutralize`（lastclass=90, lastnodechar=-1, pend=0,
  lastzw=現行, glyphmark=0; **inhibit は保存**——box 直前の
  `\inhibitglue` が box 内最初の境界も抑止する一発契約のため）で
  box 内部を中立状態で開始させる。バックエンド内部箱（charbox・
  math 箱・測定箱）は `\ptj@nest` ガードで素通り。
- **閉じ**: トークン挿入なし。読み取り点が直前に閉じた**ユーザー箱**を
  検出したとき（`\lastnodetype` 13/14 かつ glyphmark=0）に boxbdd
  再中立化（`\ptj@boxbdd`: 境界疑似クラス90でペア評価）を行う。
  読み取り点: `\ptj@pre`（各和文グリフ）、`\ptj@para@endhook`、
  クラス側 `\tatechuyoko`/`\　` の lastnodechar 読み
  （`\ptj@boxbddlastchar`）。他のノードが間に入る場合は peek 機構が
  状態を再駆動するため旧設計と収束する（実測: `\hbox{あ}Xい` の X→い 境界は
  両設計で同一の xkanjiskip）。
- **glyphmark**: 各グリフ観測で1、（非バックエンド）box 入口で0。
  縦組みでは**全グリフが回転 charbox**（`\lastnodetype=13`）なので、
  この印なしには「自前の charbox」と「ユーザー箱」を区別できない。
- 既知の残り角: `\leaders\hbox{..<和文グリフ>}`（リーダー箱の末尾が裸の
  和文グリフ）は、peek の egroup 再開 `\futurelet` が箱縁で走るため
  依然失敗する。LaTeX の TOC リーダー箱はグリフの後に `\null` を置くため
  この経路を通らない（pdftexja-jfmglue.sty の該当コメント参照）。

### 家具オプションの縦組み対照（実測）

`furniture-options` フィクスチャ（tate・twoside・twocolumn・
gutter=15zw, fore_edge=8zw, head_space=10zw, foot_space=6zw）での
uplatex 同一ソース対照（2026-10-24 実測）:

| 対照項目 | pdfTeX | upLaTeX | 差 |
|---|---|---|---|
| textwidth / textheight | 551.31902 / 270.7686pt | 同左 | 0 |
| columnwidth / columnsep | 265.6595pt / 20pt | 同左 | 0 |
| oddsidemargin | 12.7299pt（Cht 修正後） | 12.7299pt | 0 |
| evensidemargin | 82.73001pt（同上） | 82.73001pt | 0 |
| 遅延脚注カウンタ / 出荷後 textwidth 不変 | 2 / FURN-PASS | 2 / 同 | 0 |
| marginpar・遅延脚注マーカの行方向相対距離 | 160.0007pt | 160.0007pt | 0.0000pt |

（Cht/Cdp 修正前は余白系に一定 3.8pt のオフセットがあった——上記
「縦組みの Cht/Cdp」節のとおり、修正で消えた。marginpar 列/側と
遅延注位置は `savepos-marginpar` ゲートが行方向相対距離で対照する。
脚注領域内部のマイクロレイアウト残差は「savepos と論理行方向」節の
PDF 対照表参照。）

## 数式キャプチャ（2026-10-24 追記）

active-$ 機構は撤去した。`$` は catcode 3 のままで、カーネルの
`\frozen@everymath` を差し替えて行内数式を捕捉する:
```
\frozen@everymath = {\ptj@math@entry}
```
- **入口**: 保存済みの元 frozen トークン（`\aftergroup\@ignorefalse`
  `\advance\@math@level\@ne` `\check@mathfonts` `\the\everymath`）は
  捕捉時に「外側の空数式」でちょうど1回だけ実行する。`\mathsurround`
  はこの空数式に1対だけ付く（内側は `\m@th`）。
- **本体の再組版**: `\raise−δ\hbox{\m@th$<body>$}`。同一式の再入力
  （内側 `$..$`、`\text` 内の数式）は one-shot guard で素通り。
- **素通りの入口**（捕捉しない——実測で破綻するため）:
  * `\@currenvir` が表示数式環境（equation/align/gather/multline/
    split/matrix 族/eqnarray/displaymath。amsmath の本体はインライン
    `$..$` で組まれるため、これを捕捉すると環境機構が破綻する）。
  * tabular の内部 `$`（latex.ltx:16560 `\hbox\bgroup $..\halign..$`
    構成。`\@tabular` をラップしてフラグ化）。
  * クラス内部の数式（目次ドットリーダーの `$\m@th\mkern..$`。
    `\ptj@math@internal{..}` で保護）。
  * yoko 文書全体（uplatex は行内数式に一切シフトを掛けない——
    `\ybaselineshift=0` のまま。実測: `\hbox{$x$}` が raw 数式寸法
    と完全一致。実装当初と byte 互換の素通り）。
- **δ（行内数式の基準線シフト）**: plcore.ltx:776-792 `\adjustbaseline`
  と同一式・同一演算順:
  `δ = (h_M+d_M−JH−JD)/2 + JD − d_M`（M=現在の欧文フォントを無補正で
  測定、JH/JD=現JFM class 0 の高さ/深さ×zw）。計算点は plcore と同じ
  「サイズ更新時」（selectfont フック; ファミリ切替では再計算しない
  —— uplatex 実測と同一）。実測: 10pt δ=3.44438pt、14pt δ=4.89066pt
  （uplatex `\tbaselineshift` と sp 一致）。
- **text-in-math 2層**: 方向一致部品（`\mathmc/\mathgt`）は
  `counter = (δ_t−δ_yoko)×factor/1000`（factor 1000/700/500 =
  ptex-base.ch [36.720] shift_sub_exp_box と同一係数）を box に
  `\raise` で与える。静止位置 = plain 位置 + (−δ_yoko_formula)
  （10pt: +0.35562pt 上方 = uplatex GT10 実測と一致）。
- **mathja**: `\mathchoice` 4分岐は uplatex 互換の実サイズ（f@size/
  sf@size/ssf@size）を維持しつつ、display/text の同一サイズ分岐は
  box+copy 共有で組版回数 4→3（本体副作用の削減）。
- **raw primitive box 境界**: 捕捉本体のトップレベルに明示的な
  `\hbox/\vbox/\vtop/\vcenter` があると実行前に ClassError（置換提案
  `\mbox{...}` / `\text{...}` 付き）。wrapper 引数 `{..}` は1引数として
  不透過（= exempt）。マクロ展開で生成される primitive は契約外。
- ~~tate + `\tableofcontents` のドットリーダーが 2 パス目で
  "Leaders not followed by proper glue" になる~~ → **解決済み**。
  数式キャプチャとは無関係だった: 実因は (1) 旧 semantic frames の
  frame-pop `\aftergroup` が全リーダー箱を破壊、(2) 本節の内部数式
  ゲートの引数形が `{\leaders\hbox{}}\hfill` を作り群終端で glue 走査を
  妨げていた——2つの独立バグ。詳細・ゲートは「出力ルーチンと
  semantic frames」節参照。

## ptjfm-jlreq*.def（生成データ）

`make_pdftexja_jfm.lua`（ビルド時のみ実行，`make pdftexja-jfm`）が横組み
`jfm-jlreq.lua`・縦組み `jfm-jlreqv.lua` から生成。**12変種**
（方向2 × `open_bracket_pos` 3 × ぶら下げ2）: 横組みは無印（既定）,
`-b`, `-z`, `-bz`, `-n`, `-bn`、縦組みは `-tate` に同じ接尾辞
（`-tate`, `-tate-b`, `-tate-z`, `-tate-bz`, `-tate-n`, `-tate-bn`）。
一覧の唯一のソースは manifest `ptjfm-jlreq-manifest.lua`
（pdftexja/doc/pdftexja-jfm.md 参照）。`make check-pdftexja-jfm` で
再生成差分ゼロを検査（CIゲート）。
検証スクリプト `check_jfm_pdftexja.lua` が全ペア・全クラス・全文字
（12変種それぞれ）を検査。**実行時にLuaは不要**（生成済み.defを
`\input` するだけ）。

データ形式の要点:
- 文字→クラス: `cls@<hex>`（ロード時に `dcls@<10進>` へ再キー）
- クラス寸法: `class@<n>{w}{h}{d}{align}`
- ペア: マクロ呼び出し形式（上記）
- end_adjust: `endadj@<n>{詰め幅}`

## 既知の制限（作業記録は pdflatex-worklog ブランチ）

- ~~段落先頭のLA→JA境界にxkanjiskipが入らない~~ → **解決（2026-10-24）**。
  判定は `\lastnodetype`——「直前ノードが char（欧文走行）」だけを条件とし，
  `\ptj@latadj`（CJK@X ヘルパheadで実行; デコーダ内の font whatsit
  により `\pre` 内では lastnodetype は常に -1 になる，実測）が
  lastclass=90 && lastnodetype=0 のとき先行欧文をクラス27に昇格させる。
  字下げボックス（hlist=1）・明示空白（glue=11）・カーン（12）・直前box・
  空段落は欧文と誤判定されない（latin-adjacency.tex 7アサーション）。
  歴史的経緯: かつては「構造的に取得不能」と合意していた制限で，
  `\everypar` マーカーカーン署名（CJKの±1sp/±2sp機構と干渉）は不採用。
- ~~IPAexの約物グリフは全幅（JFM半幅は空き規則にのみ反映）~~ → **実装済み**
  （2026-10-23）。JFMクラスメトリクスの `class@<n>{w}{h}{d}{align}` に従い，
  w<1zw の約物はグリフを `\hbox to <w>\jlreq@zw` に align（left/middle/right
  ＝JFMの配置指定）で納め，天付き側へのオーバーハングを再現
  （`\ptj@placeglyph`。箱はグリフ自然の高さ・深さを保持，`\hss` スペーサで
  収縮）。w=1zw は箱なし素出しでノード列も不変。インク幾何は platex 参照と
  一致（punct-width.tex、13アサーション）。
- ~~ぶら下げ組み: pdfTeXに行末突出し機構がないため不可能~~ →
  **実装履歴（`\pdfprotrudechars`/`\rpcode` 機構，2026-10-23）→ 候補列機構へ置換（2026-10-24）**。
  この機構は `\pdfprotrudechars=2` + `\rpcode=1000` で実現していたが，マージン
  カーンが二重計上され，名目 0.5zw の突出しが実測 9.6pt（約1zw）に
  なっていた。**現行機構**: ぶら下げは -b 変種 JFM のクラス6/7
  end_adjust 負候補 {-0.5, 0, 0.5} として候補列（kern/penalty 列）で
  表現され，`\pdfprotrudechars`/`\rpcode`/裸字形分岐/負 hangkern は
  すべて撤去。視覚突出しは F2 の JFM 幅付き字形box（0.5zw box + 全幅
  グリフ, align=left）の本来のインクはみ出しで，負候補は行詰めの
  選択肢を与える。実測（IPAex, hsize=95pt）: 行1 、終端のインク xMax が
  名目行端から +4.63pt（uplatex HaranoAji 参照 +4.43pt と同程度，差は
  フォントのインク形状による）。通常段落末尾は para/end フックが最終和文字の
  負最小候補を tail kern として parfillskip の前に挿入する
  （`\ptj@para@endhook`，ltj insert_lineend_kern_tail 相当;
  実測: 最終行ノード列に `kern -5.0` を確認）。microtype との二重調整は
  生じない: 本バックエンドは `\rpcode` を一切設定せず，欧文 protrusion
  設定には触れない。
- 優先順位付き伸縮（通常段落）: 行末調整の shrink畳み込み近似は
  **撤去（2026-10-24）**——end_adjust は行中0・行末のみ有効な
  候補列で表現（前述）。ペアグルーの優先順位（spri/shpri）は評価の上
  `\ptj@pairspri/@pairshpri` に記録され，厳密な優先順位付き配分は
  `ptjparagraph` 環境がこのデータを消費する。通常段落の
  伸縮は native TeX 改行器の一括伸縮のまま（利用者承認の二層設計）。
  歴史的バグ記録（保持）: 畳み込み実装は csname直後の `\fi` を引数として
  食い詰め量が常に 1zw になるバグがあった（2026-10-23 修正，f665eba;
  現行は畳み込み自体が存在しない）。

### 解決済み既知問題: グリフ後peekがCJKデコーダ末尾の `\fi` を拾う欠陥（2026-10-23修正）

グリフ後peek（`\ptj@peek`）は，旧実装では CJK ヘルパの `\ifx…\else…\fi`
分岐の**内側**で `\futurelet` を実行していたため，「次トークン」には常に
ヘルパ自身の末尾 `\fi` が見え，`\ptj@peek@lat`（CJK→欧文の
xkanjiskip 発行）はバックエンド史上**一度も発火していなかった**（`\tracingall`
で実証）。テストの外観が正常に見えた理由は2つ: pairs.tex の ja-la 期待値が
数値的同値（`10+2.5+12.77779` == `10+15.27779（abcの実幅）`）で不発を
検知できないトートロジーだったこと，かな→欧文には設計上そもそも空きが
入らない（xspc は pre-only クラス）ため実害が隠れていたこと。
修正は pdftexja-jfmglue.sty:753–783: `\CJK@ignorespaces` を受動化
（`\@empty`）し，peek を 4 ヘルパ（`\CJK@X/XX/XXX/XXXX`）のラッパとして
条件分岐が閉じた後に走らせる。回帰フィクスチャ
tests/fixtures/pdflatex-rules/boundary-ja-la.tex（漢a=17.5pt＝xkanjiskip
2.5pt入り／漢abc=27.77779pt／」a=15.0pt＝pair@2@27＝0.5zw復活／
あx=15.27798pt＝xspc抑制は設計どおり）を追加し，pairs.tex の ja-la
期待値も実値 27.77779pt の真の回帰ガードに訂正。**リリース影響のあった
サイレント欠陥であったため，解決済みとして記録する。**

## 命名の鉄則（2026-10-23 追記）

TeXの制御綴名に数字は使えない。**名前に数字を含む定義は必ず**
`\expandafter\def\csname <name>\endcsname{...}` 形式で行う。
`pdftexja-jfmglue.sty` の禁則テーブル（`\ptj@kin@pre@2` 等）が
素の `\def` で定義され、全禁則が無効化されていた実例あり
（JFMペアデータは csname 形式だったのに手書きテーブルは失念）。
呼び出し側の `\csname ptj@kin@pre@\number\ptj@curclass\endcsname`
は、定義側と同じ csname 形式でのみ一致する。

## label key 正規化（2026-10-24 追記）

常時-on CJK 下では日本語ラベル key（UTF8 byte 列）が
`\csname r@<key>\endcsname` 内で裸展開され、byte マクロ内部の
`\global`/`\futurelet` が `\csname` 構成を壊す（Missing \endcsname）。
対称正規化 `\ptj@labelkey`（pdftexja-core.sty）で解決する:

  * **二段階 edef**: 段階1 `\protected@edef`（`\let\protect\@unexpandable@protect`）で通常マクロ・カウンタを kernel の
    `\label` 書込経路と同一条件で展開し、UTF8 byte は CJK byte マクロの
    保護分岐（`\else \noexpand<byte> \fi`）で凍結。段階2 で
    `\detokenize` を結果に適用し catcode 12 の同一 byte 列にする
    （`\detokenize` は引数を展開しないため段階1を必ず先に行う）。
  * **接続点（対称性）**: write=`\label`（begindocument フック）、
    read=aux の `\newlabel`（**begindocument/before** フック — kernel は
    aux を `begindocument` フックより前に `\@input` するため、
    `\AtBeginDocument` では間に合わない。これが本実装の唯一の非自明な
    フック位置）、query=`\ref`/`\pageref`（kernel `\@setref` と同一の
    二段構成 `\jlreq@pdf@setref` — `\expandafter#2#1\@empty..` 形。
    一段 `#2\csname..` では selector が cs トークン自体を掴み全fieldが
    出力される罠あり）。
  * **パッケージ面**: nameref `\NR@setref`、hyperref `\label@hyperref`/
    `\HyRef@autoref`、refcount `\refused`/`\rc@set`（`@cref` 接尾辞の
    csname 融合「`\ptj@labelkey@out@cref`」に注意 — 接尾辞は
    マクロ経由で連結する）、cleveref `\@cref` 入口の key list 事前正規化
    （cleveref 内部の `\edef\@tempa{#2}` がアクティブ byte を暴発させる
    ため）+ `\cref@getref`/`\cpageref@getref`。`\getrefnumber` は
    `\romannumeral` + `\detokenize` で完全展開性を維持（kernel の
    展開型照合も書込側と元々非対称のためマクロ入り key は従来同等）。
  * **ASCII 不変**: ASCII key は byte 不変（HEAD tree との aux cmp 一致）。

## 漢字制御綴（`\ptjdefkanjics`）

8-bit の pdfTeX は複数byteを綴名に取れないので，`\西暦true` は「\ + 先頭byte
1文字」の **control symbol** と後続のアクティブbyte列として読まれる。
`\ptjdefkanjics{<名前>}{<置換>}` は置換を `\ptj@kcs@<detokenize済み名前>` に
登録し，先頭byteの control symbol（`\csname\string<byte>\endcsname` で定義;
アクティブ byte を `\csname` 内で直接使うと CJK デコーダが暴発するため
`\string` が必須）を汎用ディスパッチャにする。ディスパッチャは pTeX と同じ
規則で名前を読む: 最初の1文字（UTF-8 のbyte数だけ引数として消費）が
漢字・かな（々〆〇・かな・CJK統合漢字・互換漢字・拡張B以降）なら，続く
漢字・かな・ASCII英字の最長列を名前とし（control word 扱い: 直後の空白を
捨てる），それ以外の1文字（`　` 等）なら control symbol とする。名前の終端で
読みすぎた token は入力へ戻す（括弧・空白は `\futurelet` で先読みして
消費しない）。未登録の名前は `Undefined control sequence` 相当のエラー。
（分割前は `\西暦true`/`\西暦false`/`\和暦`/`\　` の4綴りを静的に照合する
専用実装だった。）

## 禁則・jaxspmode（文字単位）

分割前は jlreq の JFM クラス番号に対する表（クラス 1,12 行末禁則，2,4–11,
300–302 行頭禁則，9–11,15,16 preonly，4 postonly）をバックエンドが直書きして
いた。pdfTeX-ja ではこれを LuaTeX-ja と同じ**文字単位**の表にした:
`\ptj@kpre@<cp>` / `\ptj@kpost@<cp>` / `\ptj@kjxsp@<cp>`（LuaTeX-ja の番号:
0 inhibit, 1 preonly, 2 postonly, 3 allow; 未設定は 3）。既定値は
`pdftexja-kinsoku.tex`（`ltj-kinsoku.tex` から `pdftexja-mkkinsoku.lua` が生成;
多バイト文字のみ）。境界ペナルティは p = post(直前文字) + pre(次文字)，
和欧文境界の可否は 欧文→和文 で次文字の mode が 1/3，和文→欧文 で
直前文字の mode が 2/3 のとき。直前文字は `\ptjlastnodechar`（`\inhibitglue`
の後でも更新される; 合成用の結合文字は基底文字を保つ），次文字は
`\ptj@curcp`。jlreq は LuaLaTeX と同じコードで自分の文字リストを
`\ptjsetparameter` に渡す。

## JFM のクラス番号

実行時の状態機械は擬似クラス 27（alchar: 欧文・数式境界），90（parbdd/boxbdd:
段落・箱の先頭），93（明示空白の後: 境界グルーなし）を予約している。
`pdftexja-jfmconv.lua` は JFM の alchar/parbdd/boxbdd を持つクラスを 27/90 に
付け替え，衝突する通常クラスは 1000 以降へ移す（jfm-jlreq.lua は元から
27/90 なので無変換; jfm-ujis.lua は 199→90，boxbdd の 99 は parbdd と同一視して
落とす）。JFM の `kern` は `\ptj@pairkern{nat}{ratio}` として出力し，境界で
`\kern` になる（グルーと違い改行可能点にならない）。

## 厳密段落環境 ptjparagraph（2026-10-25 追記）

`pdftexja-adjust.sty`（文書またはクラスが `pdftexja` の後に読み込む; jlreq は
常に読み込む）が `\begin{ptjparagraph}...\end{ptjparagraph}`
（引数なし・一環境一段落）を提供する。通常段落は native 経路のまま。

- **パラメータ一括保存**: 環境入口で linewidth/indent/skip群/font/方向/
  JFM/禁則に加え pretolerance/tolerance/emergencystretch, line/hyphen/
  exhyphen penalties, adj/doublehyphen/finalhyphen demerits, looseness,
  hangindent/hangafter, parshape, spaceskip/xspaceskip,
  baselineskip/lineskip/lineskiplimit, club/widow/interline/broken
  penalties と e-TeX penalty 配列（`\numexpr\<array> <idx>\relax` で
  読む——`\the\<array>` は不可, probed）、prevgraf/prevdepth を保存する。
  **実測の落とし穴**: `\numexpr\parshape 0\relax`（行数読み）は形状が
  非アクティブなとき「0」をカレントリストに typeset するため破棄箱の
  中で読む; `\parshapelength` は dimen で行数ではない;
  `\prevgraf` は `\setbox=\vbox{...\par}` 直後には読めず行数は
  walk から回収する。
- **構成要素は実行時に「またぎ」環境で捕捉**: トークン grab
  （`\def#1\end{env}`）は不可能——`\def` の引数テキストに `{` が書けない
  （probed: TeX は `#1\end ->testenv.` のような壊定義を黙って作る）。
  begin 側で `\setbox<measbox>=\vbox\bgroup` を開き本体をそのまま
  1 回 typeset し、end 側で `\par\egroup` で閉じる。
- **保存レジスタのスコープ**: 環境は LaTeX の env group の内側で走るの
  で、保存レジスタへの代入は `\global` にする（probed: group 抜けで
  0pt に戻り snapshot 検証が落ちる）。プール box レジスタ
  （`\ptj@par@PB@<n>`、64 個）は **load 時に一括確保**する——walk は
  box group の内側で `\newbox` した `\chardef` が group close で
  消える（probed: プール copy が void で読み返る）。
- **native repack と逆走**: 影 paragraph を `\vbox{\hsize=保存値 本体\par}`
  で一度だけ改行し、廃棄 vbox を lastbox/unskip/unpenalty/unkern で
  逆走する。**実測の落とし穴**:
  - `\lastnodetype` の番号は 0=char, 1=h/vlist, 3=rule, 11=glue,
    12=kern, 13=penalty（probed; 想定しやすい 10/11/13 と異なる）。
  - `\immediate\write`/`\typeout` は last-node tracker を -1 に戻す
    （`\message` は無害）。走査中は pop と代入だけにする。
  - マーカー `\vadjust{\kern<id>sp\kern-<id>sp}` は vlist 内で
    負→正の順に並ぶ。単独の layout kern（規則 backend の para/end
    tail kern 等）と区別するため「次の node が kern かつ厳密な負数
    かつ両者非ゼロ」の pair 判定を先に行う。
  - walk の handler は末尾で次 step を**直接呼ぶ**（`\let\next=...` だけ
    だと 1 node で止まる; probed）。再帰の途中で `\fi` を
    `\expandafter` で先読みすると復帰時に後続トークンが多重実行され
    る（probed: assemble が行数+1回走る）——末尾呼び出しは
    `\expandafter\loop\fi` 形にして driver から一度だけ呼ぶ。
  - **行数回収は walkbox の外で**: walk を `\setbox<walkbox>=\vbox{...}`
  の中で走らせると TeX は internal vertical mode なので、その中で
  行 box を `\box` 出力しても（破棄される）walkbox に落ちる
  （probed: 厳密行が無言で消える）。recount/assemble は walkbox
  close の後で実行する。
  - penalty 一覧は**カンマ区切り**で保存し kernel の `\pl@for` で
    再生する（空白区切り + 独自 split は空要素/終端で無限ループに
    なる; probed）。interline glue は `\the<skip>` の全文
    （fil order 込み）で保存し `\vskip` で再生する。
- **行末回復（end_adjust e）**: 各行 box を `\hbox{\unhcopy<行>}` の
  **構築中**に copy し、その内側で penalty/kern/glue を型駆動で pop
  して tail 級数の和を回復する。loop は引数なし形にする（引数つき
  continuation は終端の `\relax{1}` が**行番号を紙面に typeset する**;
  probed）。pop は必ず copy の内側で（外側だと page の vlist から
  node を削る; probed: レイアウト破壊）。
- **行の出力**: 測定行 box（native breaker が選んだ改行・候補 e・
  glue 伸縮込み）を pool からそのまま `\box` で outer vlist へ移し、
  walk が回収した interline penalty/glue を行間に再生する。測定中の
  parskip は 0、出力で ambient parskip を一度だけ挿入。最終行 depth を
  outer `\prevdepth` に、行数を `\prevgraf` に反映する。
  pool レジスタ名は text（`ptj@par@PB@k`）で保存されるため、
  使用側は **二重 `\csname`** でレジスタに戻す（`<primitive>` 1 回につき
  `\expandafter` 1 個で十分; 三重にすると残り `\csname` が素通りして
  化ける; probed）。
- **入力モデルの禁止構成**: `\footnote`/`\footnotemark`/`\marginpar`/
  `\[` は測定中に差し替えて具体的エラー
  （`<construct>~is~not~allowed~inside~ptjparagraph`）を出す。
  未知マクロは TeX 自身の Undefined control sequence で止まる。
  `\hspace` は glue item（tier 50）として捕捉するが、
  **`\skip={...}`（波括弧 glue）は本 backend では誤走査する**
  （probed: "Missing number {" + 0pt になる）ため scratch macro 経由の
  非括弧代入にする。`\allowbreak`/`\nobreak`/`\linebreak` は hook
  しない——規則 backend が内部で使う経路を壊す（probed: 括弧を含む
  本文で測定が無限ループ）。`\mbox`/`\makebox` は opaque item として
  一回だけ box 化する（kernel の `\mb@xt@` は本 format build に
  ないため位置指定は `\hb@xt@`+`\hss` で自前実装; `[2zw]` の `zw`
  キーワードは pdfTeX には unit として存在しない——クラス既定の
  制限で、pt 等で指定する）。
- **配分エンジン（実装済み・段階ゲート付き）**: 測定中は規則 backend の
  グルー発行器（`\ptj@emitglue@do`/`\ptj@emitkcomp`）をラップし、
  全ペアグルー/companion を作成順に境界表 `\ptj@par@BD@<seq>`
  （{nat}{str}{shr}{sord}{shord}{stier}{shtier}{role}）へ記録する。
  role は 1=JFM pair / 2=kanjiskip companion / 3=xkanjiskip class
  （境界のどちらかが class 27、fallback も 2/3 に分類）/
  4=explicit・語間・skip zone。tier 値は ltj-adjust.lua:79-101 +
  jlreq.cls:583-585 の縮尺どおり **JFM spri/shpri×10、kanjiskip 0、
  xkanjiskip +10/−30、explicit 50**。行ごとに: (a) 行内部を逆走
  （`\unhcopy` を構築中 hbox の中で pop）して node 表
  `NW@<n>@<j>`/`NS@<n>@<j>` を記録、(b) グルーを境界表と
  (nat,str,shr) 完全一致で照合して tier/role を決め前方索引の
  `GI@<n>@<k>` へ、(c) 残余 R=行幅−自然和を sp で計算し、tier 値
  の降順（50,20,10,0,−10,−20,−30）に飽和まで充填、部分充填 tier
  は容量比例、shrink は符号を分けて処理し有限容量超過は
  PackageWarning（組版不良報告）、(d) 行を再構成（pop+再挿入で
  位置を保ち、グルーを最終サイズの kern へ置換）——の 4 段階。
  実装上の注意（実測）: tex 発現は末尾再帰の引数を必ず明示的に
  渡すこと（`\expandafter\loop\fi` 形で引数を省くと次トークンを
  誤って食う）; `\skip={...}` の波括弧 glue 代入は本 backend では
  誤走査する; 名前渡しの split helper は二段展開にする
  （csname 展開 + マクロ本体展開）。
- **配分の適用（完了、distphase=4）**: 行 box の再構成まで通る。
  測定中は 1zw 和文グリフも box 化（`\ptj@boxglyphs=1`、
  rules.sty 側フラグ + latadj 拡張で native 改行との差を解消済み）
  し、行内部を完全走査可能にする。各行: PASS 1 で tail から全 node
  を pop して専用 slot（RB@<k>、load 時確保 1024 個）へ退避、
  PASS 2 で head から再構成——box は slot から一回だけ移し、
  glue は **kern(nat+delta)** へ置換（skip zone=role 5 は fil order
  込みで native glue 保持）、kern/penalty は NS 表から再出力。
  **行は測定幅へ \hbox to で pack**（native breaker が hsize へ
  pack したのと同一契約; 自然 pack だと parfill 領域の 0 自然長で
  264pt vs 440pt の不一致——probed）。実測検証
  （`\ptj@par@verifywd` を定義するとログ出力）:
  `measured=440.0001pt rebuilt=440.0001pt delta=0.0pt VERDICT=OK`
  （全行、1sp 以内）。配分実測（hsize=211pt、finite stretch 必要な
  行）: tier-50 glue 群に delta=+0.06667pt ずつ配分。
- **ltj 準拠の fil 除外**: parfillskip（無限 order の glue）が
  ある行は配分をスキップし全 delta=0（ltj aw_step2 の
  `res.order > 0 → return` と同一意味。parfill の吸収分を有限
  glue へ配ると過伸長になる——probed: 末行の 130pt 残余）。
  行内の非再出力 node（whatsit/ins/mark/disc/bare char）は
  **distskip**（native 行 box のまま）。
- **BD 表照合（位置非依存 scan に修正）**: 境界グルー記録との照合は
  表先頭からの位置非依存 first-match に改めた（cursor 消費型は
  行の head-first 走査と表の tail-first カーソルで整列がずれ、
  約物 pair が explicit tier(50) に誤分類されていた——実測:
  」pair が一方の行で −10/−20、別の行で 50/50）。同一 JFM から
  生成される表では同一 spec は必ず同一 tier を持つため、位置
  非依存で正しい。さらに **fallback pair グルー（未定義
  pair@0@0 の漢字-漢字境界=生 kanjiskip）の記録漏れ**を
  emitglue 入口の wrap で解消（role 2 / tier 0）。実測:
  漢字-漢字境界は 0/0、」・。pair は −10/−20 と安定分類。
- **2-tier 差の実証（strict-tierdiff fixture）**: hsize=158pt で
  stretch 需要 8pt の行について、native 一括比例伸縮なら
  `\hspace{0pt plus 30pt}` は 8×30/55=4.36pt、各漢字間グルーは
  0.36pt を受けるところ、tier engine は tier-50 の明示グルーに
  全量 8.00002pt を配り、kanjiskip(0)/JFM pair(−10) tier は 0
  （`TIERTOP` ログで検証; runner gate strict-tierdiff-* 4件）。
- **aw_step1_last 最終行候補再選択（実装・実測）**: 最終行の
  end_adjust 候補を parfillskip 条件で再選択——slack(e)=残余−e を
  辞書順 (|slack|, |e|, e) で比較し、native 選択と異なれば
  F@win として再構成行の末尾 kern に差分 (e_win−e_native) を
  適用。実測（hsize=70pt、末尾「。」の一行段落）:
  `FINS: native-e=0.0pt win-e=5.0pt rem=5.0pt slack=0.0pt`
  ——native は e=0、parfill 条件は e=5pt（0.5zw ぶら下げ）を
  選ぶ。候補表は生成 .def の endadj（各クラス2フィールド）を
  直接 unpack して評価（再帰 sentinel walker は tail group を
  誤飲して \fi を洩らしたため廃棄——probed）。
- **再構成の内容保全（重大な潜在欠陥の修正）**: PASS-1 のスロット
  \setbox は測定 \hbox グループ内で実行されるため local——
  グループ閉鎖で全スロットが void になり、PASS-2 が空行を
  出力していた。RBWD 幅照合は \hbox to が何もなくても幅を
  保つためこれを検出できず、日本語グリフが全て消えた行が
  「検証済み」と見なされていた（実測: distphase=3 で 33 字、
  =4 で 2 字——global \setbox で解決）。distskip フラグも
  同一理由で global 化（コピー \hbox グループ内で true に
  しても外で消えていた）。
- **skip zone の fil 復元**: role-5 glue は walk 時に
  `\the\lastskip` の全文（"nat plus X fil..."）を NSf 表に記録し、
  再構成ではそれを verbatim 再出力する。分割フィールドから
  "nat plus... fil" を組み立てる方法は単語間空白が失われ
  mis-parse、リテラル 'fil' グリフが行末に出力されていた
  （probed; `\advance<skip><glue>` が natural のみ加算する仕様も
  同根）。

## 厳密段落の実測メモ（probe 記録）

- `\prevdepth` は `\unvbox` で 0 に戻る; 行 box の `\box` 追加後は
  その box の depth が `\prevdepth` に入る。
- `\setbox\@cclv` は page builder の所有物——測定に使うと
  「`\box255 is not void」/「No pages of output」を起こす。専用 scratch
  box を使う。
- `\vbox\bgroup`...`\par\egroup` のまたぎ環境は tate でも動作する
  （局所方向エンジンと干渉しない）。

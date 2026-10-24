# pdfTeXバックエンド内部設計（pdftex-internals）

jlreqのpdfLaTeX対応（実験的）の内部構造。`docs/pdftex-compatibility.md` は対応状況，
本書は実装の内部構造。

## 全体構造

```text
jlreq.cls（公開API・版面設計: 共通）
├── l: LuaTeX-ja既存経路
├── p/u: (u)pLaTeX既存経路
└── d（pdfTeX）:
    ├── jlreq-pdftex.sty        … 土台（フォント・単位・CJK状態）
    ├── jlreq-pdftex-rules.sty  … 組版規則（JFMグルー・禁則・和欧文間隔）
    └── jlreq-pdftex-jfm*.def   … 生成済みJFMデータ（4変種）
```

## jlreq-pdftex.sty（土台）

1. **bxcjkjatype[ipaex-type1,noCJKpunct]** をロード。CJKutf8（UTF-8デコーダ）＋
   IPAex明朝/ゴシックType 1フォント（C70/ipxm,ipxg）。`noCJKpunct`は約物処理の
   二重適用防止（jlreq自身のJFM規則が空きを管理するため）。
2. **always-on CJK状態**: `\CJK@global/\CJK@active/\CJK@local` を `\global` に
   差し替え，`\CJK@envStart{}{UTF8}{ipxm}` + `\CJKspace` を一度発行。以後UTF-8の
   多バイト文字がファイル全体で有効になり，クラスロード中の `\hbox{阿}` 等の
   和文リテラルがそのまま評価できる（G1の解決策）。
   - 副作用: 漢字制御綴（`\if西暦`等）が作れない→ASCII名で再実装。
   - `\makeatletter` 再発行必須（CJKの遅延ロードが catcode を戻すため）。
3. **単位エミュレーション**: `\zw`/`\zh` = `\jlreq@jareg`（dimenレジスタ）への
   マクロ。`2\zw` は plain TeX の `<factor><internal>` 構文で動作。
   `\jlreq@jareg` は `\f@size × \jlreq@jafontscale` としてフォントサイズ変更に追従
   （setfontsizehook経由）。`\Cht/\Cdp/\Cwd/\Cvs/\Chs` を `\newdimen` で宣言し，
   クラスロード時の `\hbox{阿}` 測定がそのまま動く。
4. **フォント**: `\mcfamily/\gtfamily/\mgfamily` は bxcjkjatype 任せ（C70系）。
   欧文NFSSは別系統。boldは `\CJKbold`（PDF text rendering 2 Tr による擬似太字，
   IPAexに太字フェースがないため）をselectfontフックで `\f@series` 追跡して発行。
5. **オプション値の書き換え**: クラスロード時に長さ系オプション値中のリテラル
   `zw`/`zh` を `\jlreq@zw`/`\jlreq@zh` に置換するパスを実行
   （`\ProcessKeyOptions`直後，エンジン確定後）。

## jlreq-pdftex-rules.sty（組版規則）

1. **文字フック**: CJK.sty内部の `\CJKsymbol `（robust命令の内部）を
   `\AtBeginDocument` でラップ（bxcjkjatypeが再定義するためロード時では上書きされる）。
   全UTF-8経路がここに集約され，文字の「10進コードポイント = plane×256+バイト値」
   を受け取る（`\CJK@plane`は16進2桁 → `\jlreqpdf@setclassof` で復元）。
   後続覗きは `\CJK@ignorespaces` を受動化（`\@empty`）したうえで，4つのヘルパ
   （`\CJK@X`/`\CJK@XX`/`\CJK@XXX`/`\CJK@XXXX`）をラップし，ヘルパ自身の条件分岐が
   閉じた後に `\futurelet` が走る形で `\jlreqpdf@peek@a` を差し込む（jlreq-pdftex-rules.sty:753–783）。
2. **状態機構**: `\jlreqpdf@lastclass`（0〜25のJFMクラス + 27=latin + 90=段落境界 +
   93=明示空白後）。段落開始（`para/begin`フック）で90へリセット。
3. **ペアグルー**: 生成データ `pair@<from>@<to>` は **マクロ呼び出し形式**
   `\jlreqpdf@pairfields{nat}{str}{shr}{ratio}{spri}{shpri}{knat}{kstr}{kshr}`
   で格納（`{{...}}`二重括弧形式は引数再括弧化で分割不能のため，この形式になった。
   TeXの引数取得は外括弧を剥がし置換時に再括弧化する）。
   - 定義ペア: **9フィールド全評価（P3）**。nat/str/shr は左右zwの
     two_paverage ブレンド（`b = zw_prev + r*(zw_cur - zw_prev)`，
     ltj-jfmglue.lua:812-857 と同一式，単一JFMなので両側同一のb）で
     実寸化。ratio/spri/shpri は評価して spri/shpri を
     `\jlreqpdf@pairspri/@pairshpri` へ記録（P11 jlreqparagraph の
     前提データ）。kanjiskip付随成分 knat/kstr/kshr はフラグ付きで
     現行 `\jlreqkanjiskip` から別glueノードとして発行
     （`\jlreqpdf@emitkcomp`）。
   - 未定義ペア: **現行値フォールバック（P3）**——固定 0/.25zw 定数を廃止し，
     現行 `\jlreqkanjiskip`/`\jlreqxkanjiskip` のグルー指定をそのまま
     （fil order も保持）。
   - **行末調整（P3 で近似を置換）**: 直前クラスの end_adjust は
     行中のshrink畳み込みを行わず，**候補列** `kern(e1) penalty(p)
     kern(e2-e1) penalty(p) ... kern(-em) penalty(10000)` + ペアグルー
     として発行（`\jlreqpdf@eawalk`，ltj-adjust.lua insert_lineend_kern
     と同一構造。0候補は列内に保持，行中は正味0，行末breakだけが選択
     候補eを行に残す）。境界penaltyは p=post(prev)+pre(next) を
     全候補へ一括適用（`\jlreqpdf@boundaryp`）。禁則(p>=10000)時も
     グルーの伸縮成分はkern化で捨てない（kernmode 固定カーン処理は廃止）。
4. **禁則**: クラス番号テーブルで行頭/行末禁則ペナルティ10000を境界penalty
   p に合成（jlreq.cls の setpre/postbreakpenalty aux は P3 以降この表へ
   実書き込みし，`\jlreqsetup` の禁則キーが実効する）。
5. **和欧文間**: 境界で `\jlreqxkanjiskip`（0.25zw + 0.25zw - 0.125zw）。
   xsp規則（かな側のみ許容等）もクラスフラグで再現。
   **段落先頭のLA→JA境界（P3）**: lastclass=90 かつ `\lastnodetype=0`
   （char ノード＝先行欧文走行）のとき先行をクラス27として扱う
   （判定は CJK@X helper head の `\jlreqpdf@latadj` で実行——
   デコーダ内の font whatsit により `\pre` 内では lastnodetype が
   常に -1 になるため。latin-adjacency.tex 7アサーション）。
6. **局所方向（P5, 2026-10-24）**: 方向状態 `\jlreqpdf@dir`（count, 0=yoko/1=tate）
   は frame tuple の一要素（`\jlreqpdf@frame@push/@pop` が
   lastclass/lastnodechar/pend/inhibit/lastzw とともに保存復帰;
   jlreq-pdftex-rules.sty:199-213）。主文書方向は `\if@tate` から
   begin document で播種（`jlreqpdf@setmaindir`）。判定:
   `\jlreqpdftex@ifydir/@iftdir`（バックエンド内部）と
   `\jlreq@ifydir/@iftdir`（jlreq.cls d 分岐, `\ifnum1=\jlreqpdf@dir\fi`
   形式——expl3構文下で空白が食われるため被比較数を末尾に置く）。
   **箱工場** `jlreq-pdftex.sty`:
   `\jlreqpdf@yokobox{body}` / `\jlreqpdf@tatebox{body}`（同方向なら恒等）
   および `\jlreqpdf@yokobox@strut{ht}{dp}{body}`（body の ht/dp を指定値に
   固定してから埋める。縦中横の 1zw 正規化用）。交叉埋め込み
   `\jlreqpdf@embed@yoko@in@tate`（`\rotatebox{90}` 依存の明示算術:
   寸法事前退避→回転→`\kern-ht`→`\lower w/2`→`\wd=ht+dp`・`\ht=\dp=w/2`）は
   pTeX の yoko-in-tate 自動埋め込みと同一契約（uplatex showbox・PDF bbox
   実測: advance=ht+dp, cross=体幅半分ずつ, baseline=進行起点）。
   **安全契約**: 未知 box の方向照会 `\jlreqpdf@boxdir` は ClassError
   （無告知 yoko fallback なし。工場製 box の再利用は「現 frame の方向」が
   契約——pdfTeX に box 属性は存在しない）。
   **ページ方向** `\jlreqpdf@pagedir@count` + `\jlreqpdf@pagedir{0|1}`:
   出荷回転は `\if@tate && pagedir=1` のときのみ掛かる（theindex 等の
   横組み論理ページは回転なしで出荷）。フラグは P7（出力ルーチン薄層化）
   のインターフェース。cls theindex d 分岐は
   `clearpage → pagedir=0 → dir=0 → \hsize=\textheight`（pTeX の \yoko ページ
   の寸法役割交換, uplatex 実測: 2段幅=(textheight-colsep)/2）を行い、
   終端で `pagedir=1 → dir=1 → \hsize=\textwidth` を復帰。
   ゲート: tests/fixtures/pdflatex-tate/{dir-roundtrip,dir-callers,
   dir-index-yoko,tcy-digits,tcy-fontchange,tcy-star-error}.tex
   （T8 が TATE-PASS/TATE-FAIL・エラー文言を検査）。

## jlreq-pdftex-jfm*.def（生成データ）

`make_pdftex_jfm.lua`（ビルド時のみ実行，`make pdftex-jfm`）が `jfm-jlreq.lua`
単一ソースから生成。4変種: 無印（既定）, `-b`（ぶら下げデータ入り）, `-z`
（zenkakunibu_nibu）, `-bz`。`make check-pdftex-jfm` で再生成差分ゼロを検査
（CIゲート）。検証スクリプト `check_jfm_pdftex.lua` が全402ペア・25クラス・
403文字を検査。**実行時にLuaは不要**（生成済み.defを `\input` するだけ）。

データ形式の要点:
- 文字→クラス: `cls@<hex>`（ロード時に `dcls@<10進>` へ再キー）
- クラス寸法: `class@<n>{w}{h}{d}{align}`
- ペア: マクロ呼び出し形式（上記）
- end_adjust: `endadj@<n>{詰め幅}`

## 既知の制限（詳細は各実装報告書を参照）

- ~~段落先頭のLA→JA境界にxkanjiskipが入らない~~ → **解決（2026-10-24、P3）**。
  判定は `\lastnodetype`——「直前ノードが char（欧文走行）」だけを条件とし，
  `\jlreqpdf@latadj`（CJK@X ヘルパheadで実行; デコーダ内の font whatsit
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
  （`\jlreqpdf@placeglyph`。箱はグリフ自然の高さ・深さを保持，`\hss` スペーサで
  収縮）。w=1zw は箱なし素出しでノード列も不変。インク幾何は platex 参照と
  一致（punct-width.tex、13アサーション）。
- ~~ぶら下げ組み: pdfTeXに行末突出し機構がないため不可能~~ →
  **実装履歴（H1機構，2026-10-23）→ P3 で置換（2026-10-24）**。
  H1 は `\pdfprotrudechars=2` + `\rpcode=1000` で実現していたが，マージン
  カーンが二重計上され，名目 0.5zw の突出しが実測 9.6pt（約1zw）に
  なっていた。**P3 の現行機構**: ぶら下げは -b 変種 JFM のクラス6/7
  end_adjust 負候補 {-0.5, 0, 0.5} として候補列（kern/penalty 列）で
  表現され，`\pdfprotrudechars`/`\rpcode`/裸字形分岐/負 hangkern は
  すべて撤去。視覚突出しは F2 の JFM 幅付き字形box（0.5zw box + 全幅
  グリフ, align=left）の本来のインクはみ出しで，負候補は行詰めの
  選択肢を与える。実測（IPAex, hsize=95pt）: 行1 、終端のインク xMax が
  名目行端から +4.63pt（uplatex HaranoAji 参照 +4.43pt と同程度，差は
  フォントのインク形状による）。通常段落末尾は para/end フックが最終和文字の
  負最小候補を tail kern として parfillskip の前に挿入する
  （`\jlreqpdf@para@endhook`，ltj insert_lineend_kern_tail 相当;
  実測: 最終行ノード列に `kern -5.0` を確認）。microtype との二重調整は
  生じない: 本バックエンドは `\rpcode` を一切設定せず，欧文 protrusion
  設定には触れない。歴史的構造メモ（H1時代の箱詰め不可・whatsit介在の
  突出し不発火条件）は poc/README-g3b.md に記録。
- 優先順位付き伸縮（通常段落）: 行末調整の shrink畳み込み近似は
  **P3 で撤去（2026-10-24）**——end_adjust は行中0・行末のみ有効な
  候補列で表現（前述）。ペアグルーの優先順位（spri/shpri）は評価の上
  `\jlreqpdf@pairspri/@pairshpri` に記録され，厳密な優先順位付き配分は
  第11段階の `jlreqparagraph` 環境がこのデータを消費する。通常段落の
  伸縮は native TeX 改行器の一括伸縮のまま（利用者承認の二層設計）。
  歴史的バグ記録（保持）: 畳み込み実装は csname直後の `\fi` を引数として
  食い詰め量が常に 1zw になるバグがあった（2026-10-23 修正，f665eba;
  現行は畳み込み自体が存在しない）。

### 解決済み既知問題: グリフ後peekがCJKデコーダ末尾の `\fi` を拾う欠陥（2026-10-23修正）

グリフ後peek（`\jlreqpdf@peek`）は，旧実装では CJK ヘルパの `\ifx…\else…\fi`
分岐の**内側**で `\futurelet` を実行していたため，「次トークン」には常に
ヘルパ自身の末尾 `\fi` が見え，`\jlreqpdf@peek@lat`（CJK→欧文の
xkanjiskip 発行）はバックエンド史上**一度も発火していなかった**（`\tracingall`
で実証）。テストの外観が正常に見えた理由は2つ: pairs.tex の ja-la 期待値が
数値的同値（`10+2.5+12.77779` == `10+15.27779（abcの実幅）`）で不発を
検知できないトートロジーだったこと，かな→欧文には設計上そもそも空きが
入らない（xspc は pre-only クラス）ため実害が隠れていたこと。
修正は jlreq-pdftex-rules.sty:753–783: `\CJK@ignorespaces` を受動化
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
`jlreq-pdftex-rules.sty` の禁則テーブル（`\jlreqpdf@kin@pre@2` 等）が
素の `\def` で定義され、全禁則が無効化されていた実例あり
（JFMペアデータは csname 形式だったのに手書きテーブルは失念）。
呼び出し側の `\csname jlreqpdf@kin@pre@\number\jlreqpdf@curclass\endcsname`
は、定義側と同じ csname 形式でのみ一致する。

## label key 正規化（P9, 2026-10-24 追記）

常時-on CJK 下では日本語ラベル key（UTF8 byte 列）が
`\csname r@<key>\endcsname` 内で裸展開され、byte マクロ内部の
`\global`/`\futurelet` が `\csname` 構成を壊す（Missing \endcsname）。
対称正規化 `\jlreqpdf@labelkey`（jlreq-pdftex.sty）で解決する:

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
    csname 融合「`\jlreqpdf@labelkey@out@cref`」に注意 — 接尾辞は
    マクロ経由で連結する）、cleveref `\@cref` 入口の key list 事前正規化
    （cleveref 内部の `\edef\@tempa{#2}` がアクティブ byte を暴発させる
    ため）+ `\cref@getref`/`\cpageref@getref`。`\getrefnumber` は
    `\romannumeral` + `\detokenize` で完全展開性を維持（kernel の
    展開型照合も書込側と元々非対称のためマクロ入り key は従来同等）。
  * **ASCII 不変**: ASCII key は byte 不変（HEAD tree との aux cmp 一致）。

## 漢字綴りディスパッチャ（P9, 2026-10-24 追記）

`\西暦true`/`\西暦false`/`\和暦`/`\　` は「\ + 先頭byte 1文字」の
**control symbol**（8-bit エンジンは複数byteを綴名に取れない）として
捕捉する。`\csname\string<byte>\endcsname` で綴名 byte の control symbol
を定義し（アクティブ byte を `\csname` 内で直接使うと CJK デコーダが
暴発するため `\string` で catcode 12 化が必須）、本体は残り byte 列を
1 token ずつ消費照合（`\futurelet`+`\ifx` は chardef とアクティブ文字の
意味が異なり一致しないため消費先行型 `\ifx` 直接比較）して
protected ASCII 命令へ置き換える。`\西暦true/false` は共通接頭辞
（西・暦の残りbyte）消費後に ASCII 単語を読み分ける（引数grabは空白を
飛ばすため `\futurelet` で先読み; `\futurelet<cs><handler>{arg}` の
peek は handler 引数の `{` を見るため handler は引数なしにする）。
候補列は登録ごとに `\unexpanded\expandafter{\the\toks0}` で実体化する
（共有 toks 参照だと最終登録が全 control symbol を上書きする）。

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
   - 定義ペア: nat/str/shr をzw倍して `\hskip`。
   - 未定義ペア: `\jlreqkanjiskip`/`\jlreqxkanjiskip`（かな連続の伸縮）。
   - **行末調整近似（M5）**: 直前クラスの end_adjust（.defの `endadj@<n>`）の
     詰め量をグルーのshrinkに加算。優先順位・「行末限定」の意味論はpdfTeX改行器に
     表現不可能（G3分析）。
4. **禁則**: クラス番号テーブルで行頭/行末禁則ペナルティ10000をグルー前後に挿入
   （jlreq.cls の pre/postbreakpenalty 設定と同一の対象クラス）。
5. **和欧文間**: 境界で `\jlreqxkanjiskip`（0.25zw + 0.25zw - 0.125zw）。
   xsp規則（かな側のみ許容等）もクラスフラグで再現。

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

- 段落先頭のLA→JA境界にxkanjiskipが入らない——limitation agreed（構造的）。
  段落状態リセット自体は para/begin フック（jlreq.cls:1090）で `lastclass=90`
  に正しく行われるが，「直前が欧文」という知識だけが取得不能:
  pdfTeXでは欧文文字にフックを掛けられないためフラグの立て下ろしが健全に
  行えず，`\everypar` のマーカーカーン署名は CJK.sty 自身の ±1sp/±2sp
  マーカー機構と干渉して読めず，字下げボックスやゼログルーの署名は
  曖昧（F3プローブで検証）。代替の見込みが立たないため制限として合意。
- ~~IPAexの約物グリフは全幅（JFM半幅は空き規則にのみ反映）~~ → **実装済み**
  （2026-10-23）。JFMクラスメトリクスの `class@<n>{w}{h}{d}{align}` に従い，
  w<1zw の約物はグリフを `\hbox to <w>\jlreq@zw` に align（left/middle/right
  ＝JFMの配置指定）で納め，天付き側へのオーバーハングを再現
  （`\jlreqpdf@placeglyph`。箱はグリフ自然の高さ・深さを保持，`\hss` スペーサで
  収縮）。w=1zw は箱なし素出しでノード列も不変。インク幾何は platex 参照と
  一致（punct-width.tex、13アサーション）。
- ~~ぶら下げ組み: pdfTeXに行末突出し機構がないため不可能~~ → **実装済み**
  （2026-10-23、H1機構）。「行末突出し機構なし」は誤りと判明: 
  `\pdfprotrudechars=2` とグリフごとの `\rpcode=1000`（突出し量1em）で実現
  （jlreq-pdftex-rules.sty:357–378）。-b/-bz 変種選択時のみ有効化し，
  クラス6/7（句読点）は箱に包まず裸 char で出力後に `\kern -0.5zw` を出す
  （行中はF2の箱と同じ0.5zw詰め，行末のカーンブレイクではパック時に
  0化される）。実測: 右マージンカーン −10.0pt，インクが名目行端から
  0.5zw 外へ出る（hanging-punct.tex、5アサーション）。構造的なノード条件
  （箱詰め不可・補正カーンとペアグルー間にwhatsitを置かない等）は
  poc/README-g3b.md に記録。whatsit が介在する配置では突出しが静かに
  効かなくなる（行は正しく組め、破綻しない）ことも制限として記録。
- 優先順位付き伸縮: shrinkへの畳み込み近似のみ（pdfTeXの改行器に
  厳密な意味論は表現不能）。ただし実文コーパス比較でブレークポイント選択への
  実害は非計測（poc/README-m5-numeric.md）。なお end_adjust 畳み込みは
  csname直後の `\fi` を引数として食い詰め量が常に 1zw になるバグがあったが，
  ブレース群駆動の走査に修正済み（2026-10-23）。

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

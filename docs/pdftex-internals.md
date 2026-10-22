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
   後続覗きは `\CJK@ignorespaces` を `\futurelet` ベースの `\jlreqpdf@peek` へ再設定。
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

- 段落先頭のLA→JA境界にxkanjiskipが入らない（直前CJK不在だとpeekが発火しない）
- IPAexの約物グリフは全幅（JFM半幅は空き規則にのみ反映）
- ぶら下げ組み: pdfTeXに行末突出し機構がないため不可能（-b変種データは将来用）
- 優先順位付き伸縮: 同上，shrinkへの畳み込み近似のみ

## 命名の鉄則（2026-10-23 追記）

TeXの制御綴名に数字は使えない。**名前に数字を含む定義は必ず**
`\expandafter\def\csname <name>\endcsname{...}` 形式で行う。
`jlreq-pdftex-rules.sty` の禁則テーブル（`\jlreqpdf@kin@pre@2` 等）が
素の `\def` で定義され、全禁則が無効化されていた実例あり
（JFMペアデータは csname 形式だったのに手書きテーブルは失念）。
呼び出し側の `\csname jlreqpdf@kin@pre@\number\jlreqpdf@curclass\endcsname`
は、定義側と同じ csname 形式でのみ一致する。

# PoC G3-bis: pdfTeX によるぶら下げ（行末突出し）の可否判定

結論: **可能であった（条件つき）**。`hanging_punctuation` オプション経路で実装済み
（`jlreq-pdftex-rules.sty` の `\ifjlreqpdf@hang` ブロック、fixture
`tests/fixtures/pdflatex-rules/hanging-punct.tex`）。先行メモ
「pdfTeX には行末突出し機構がないため不可能」は**誤り**で、実際の制約は
もっと具体的なノードレベルの条件だった。以下が全記録。

PoC: `poc/g3-protrusion.tex`（pdflatex でコンパイル可・rc=0）。
ログの `G3-PANEL-X=YES/NO (rightmargin=…)` が各パネルの判定結果
（`\rightmarginkern` 読み戻し、YES = 右マージンカーンが非ゼロ）。

| パネル | ノード列（、＝U+3001, ipxm plane-30 slot 1, rpcode=1000） | 判定 |
|---|---|---|
| A | 裸 、`[kern -0.5zw]`、pair glue、CJK マーカ OFF | **YES**（-10.0pt 突出し発火） |
| B | A + CJK マーカーカーン（`\kern-2sp\kern2sp`）有り | NO（マーカが行端走査を止める） |
| C | F2 現行の `\hbox to 0.5zw` 箱詰めグリフ | NO（箱が走査を止める） |
| D | カーンとグルーの間に whatsit（`\pdfsavepos`） | NO（ブレイクが glue 側に移る） |
| E | A + 直前に `\penalty10000`（行頭禁則相当） | YES（penalty は阻害しない） |

PDF 上の目視証拠（pdftohtml -xml、単位 ≈ pt×1.578）: パネル A/E の
1行目は 、 が左端+343 に置かれ ink 右端 358 > 名目行端 ≈ 351
（**約 0.5zw のマージン突出**）。B/C/D は 、 が次行頭（左端+201）に
落ちる（行長を失って回り込む＝突出しが発火しないときの行動）。

## 機構（pdfTeX、ソース pdftex.web で裏付け）

1. **protrusion の実現形`:行パック時（`hpack`）に、行端の文字を探し
   （`find_protchar_right/left`）、そこに **margin kern ノードを挿入**する
   （右: `\kern -w (right margin)` と \showbox に見える）。負のカーンで
   「行の自然長」を縮め、両端揃えの再配分で行内グルーがその分伸び、
   行端グリフが物理的に右へ押し出される。**行内に伸長できるグルーが
   無いと光学的に見えない**（`\pdfprotrudechars=2` なら改行可能性
   （feasibility）にも影響する: `shortfall += total_pw`）。
2. **行端走査は型で止まる（`cp_skipable`）**。越えられるのは
   ins/mark/adjust/penalty/whatsit（ximage 系を除く）・空 disc・
   幅0の math・**幅0または normal/auto サブタイプのカーン**・zero glue・
   完全に空の箱。**越えられないのは `subtype=explicit` の非ゼロカーン
   （素の `\kern`）と空でない箱**。
   ⇒ 現行 F2 の `\hbox to 0.5zw{...}` を行端に置くと必ず走査が止まり、
   CJK.sty が全和字の後に置く目印カーン（-2sp/+2sp、\kern プリミティブ
   = explicit 非ゼロ）も止める。
3. **カーン直後のブレイク（`kern_break`）は「直後が glue」で成立**し、
   パック時にそのカーンは **幅 0 に書き換えられる**（`width(q):=0`）。
   ⇒ 「JFM クラス幅 < 全角グリフ幅」の差分補正を **負のカーンで後置**す
   れば、行中では 0.5zw 詰め・行末では（0化されるので）突出しと両立する。
   これが唯一の両立形である（代替: 負グルーだと行末に残らないので突出し
   は出るが、今度は中間の 0.5zw 詰めが正しくない）。
4. **glue の直前に glue/penalty/explicit kern/math があるとその glue は
   ブレイク不可**（tex.web 系の既定則）。whatsit（`\pdfsavepos`、hyperref
   等）はこの禁止リストに**含まれない**。よって補正カーンとペアグルーの
   間に whatsit が入ると (a) glue が合法ブレイクになり、(b) kern_break は
   「直後が glue」を満たさず不成立になり、ブレイクは glue 側に移る。
   0 化されない補正カーンが行端に残り行端走査を止めるので **突出しが
   静かに効かなくなる**（行はちゃんと組める＝劣化、破綻しない）。
   ⇒ fixture では段落中に whatsit を置かない。hyperref の `\label` 等を
   、 の直後に置く実文でも同じ劣化を起こし得る（制限として記録）。
5. `\rpcode f c = n` は **quad（1em）の千分率**（`char_pw = n/1000 ×
   quad(f)`）。全角（1zw=1em）グリフの突出し量 -1zw は rpcode=1000。
   代入は `pdf_mem` 直書きで**常にグローバル**（`\global` 不要、代入の
   たびに行なっても安い）。
6. **禁則ペナルティは阻害しない**（penalty ノードは skipable）。
   状態機構の [penalty 10000][、] という並びはそのままでよい。
   ペアグルーは改行点で破棄されるので、改行後の行端には残らず阻害しない。

## 実装との対応（jlreq -b 変種データ → pdfTeX パラメタ）

- -b 変種の `endadj@6/7 = {-0.5}{0}{0.5}`: フィールド列は優先度逆順で、
  負の値 -0.5 が「ぶら下げ突出し量」（jlreq の jfm-jlreq は句読点の
  行末 0.5zw 突出）。これは **グリフ（全幅 1zw）の半分が行外に出る**
  ことに相当する。IPAex Type1 グリフは全幅で字面インクは上半分にある
  ため、**margin kern -1zw（rpcode=1000）でグリフを 1zw 右へ**押せば
  インクがちょうど 0.5zw マージンに出る（fixture の `\rightmarginkern`
  読み戻し値 -10.0pt と一致）。
- 正の値（0.5）の畳み込みは従来どおり shrink への加算（walk 修正済み、
  下記 M5 バグ修正の項）。
- CJK マーカーカーンは、ぶら下げ有効時（`\ifjlreq@burasage`）に限り
  AtBeginDocument で無効化した（`\CJK@kern/\CJK@CJK` を空に）。効果は
  ペアグルーが `\lastkern` を潰すため本バックエンド上で既に機能してい
  ないものの无害化である。
- フォントインスタンス（`\curr@fontshape/\f@size/\CJK@plane`）ごとに
  グリフ描出の際 `\rpcode` を遅延設定（スロット = CJKフックが渡すプレー
  ン内バイト値、plane-30 でも plane-FF（，．）でも成立）。

## H1 で実証した前提の訂正（互換表用）

- 「pdfTeX に行末突出し機構が存在しない」→ **誤り**。`\pdfprotrudechars=2`
  + `\rpcode` で実現可能（fixture・PoC ログ・PDF ink 座標で実証）。
- 正しい制限はノードレベル: 行端グリフは裸 char である必要がある
  （箱詰め不可）・行端に非ゼロの明示カーンが残らないこと・補正カーンと
  ペアグルーの間に whatsit が来ないこと。現行の診断は上表参照。

## M5 関連の修正（この PoC の副産物）

`\jlreqpdf@addendadj` は csname 構築直後の `\fi` を第2引数として食い、
詰め量が常にデータ無関係の 1zw（= 10pt）になっていた（改行時の過剰な
詰め許容）。ブレース群駆動のフィールド走査に直し、正の値の合計
（既定 0.5zw/クラス2,6,7、0.25zw/クラス5）だけを shrink に加える。
-b 変種でも合計は同じ 0.5zw で、負の値は H1 ブロックが別途担う。

# pdfTeX 対応状況・公開 API 互換マトリクス（pdftex-compatibility）

- **対象リポジトリ**： [abenori/jlreq](https://github.com/abenori/jlreq)（基準コミット `ac06fd0`、2025-07-17 版 + M1 エンジン検出パッチ適用後の作業ツリー）
- **作成日**： 2026-10-23
- **位置づけ**： `PLAN.md` §2.2 が定義する監査成果物のひとつ。公開機能・オプションごとの pdfTeX 対応状況を `implemented / pending / blocked` で追跡する（PLAN.md §6.3「文書API互換表：全項目を `pass / limitation agreed / blocked` で追跡」）。
- **現時点の状態（2026-10-23、M1–M6・M8 実装完了、横組みスコープ全完了）**： pdfTeX で `\documentclass{jlreq}` は横組文書として動作する（実験的サポート）。バックエンド `jlreq-pdftex.sty`（フォント・単位・メトリック・`\kansuji`）＋ `jlreq-pdftex-rules.sty`（JFMペアグルー・禁則・和欧文間隔・end_adjust近似・約物JFM幅・ぶら下げ突出し）＋ 生成済みJFMデータ4変種（`jlreq-pdftex-jfm*.def`）。Q/H単位（全長さ系オプション＋`\jlreqsetup`）、`\sidenote`両型、数式内和文（`\mathmc`/`\mathgt`）、`\kansuji`、jlreq-trimmarks（トンボ＋回転バナー）、`reference_mark=interlinear`、`\mag` 可変運用まで実装・検証済み。縦組み（`tate`）は明示エラー（G4判定: structurally blocked——判定記録は `docs/pdftex-tate-eval.md`）。既知の制限・残作業は本文のマトリクスと `docs/pdftex-audit.md` を参照。

## 1. ステータス定義

| ステータス | 意味 |
|---|---|
| **implemented** | pdfTeX で動作することをテスト（回帰スイート `tests/run-pdftex-tests.sh`）で示した機能 |
| **pending** | バックエンド実装（M2–M8）で対応予定。機能は公開 API として維持される |
| **limitation agreed** | 実測の結果、pdfTeXの機構上再現不能と確定した制限（PLAN §1.2「limitation agreed」）。代替手段・理由を備考に記録 |
| **blocked** | pdfTeX の原理的制約により、対応の見込みが立たない、または特別な合意（PLAN.md §7 ゲート失敗時のスコープ協議）を要する機能 |

工程（M0–M9）とゲート（G1–G4）は PLAN.md §4・§7 の定義に従う。完全性レベル L1（API互換）／L2（規則互換）／L3（出力互換）は PLAN.md §1.2 の定義に従う。

## 2. クラスオプション（`\documentclass[…]{jlreq}`）

`jlreq.cls` 内の全 `\DeclareKeys [jlreq]` ブロック（104–117, 135–147, 290–297, 301–345, 347–405 行）から抽出した全オプション。

### 2.1 エンジン・文書タイプ

| オプション | 定義行 | 役割 | pdfTeX ステータス | 対応工程 | 備考 |
|---|---|---|---|---|---|
| `uplatex` / `platex` / `lualatex` | jlreq.cls:106–108 | エンジン明示指定 | **implemented**（既存） | M1 | pdfTeX で指定すると実エンジンとの不一致エラー（jlreq.cls:458–477） |
| `pdflatex` | jlreq.cls:109 | pdfTeX 明示指定 | **implemented** | M1 | 指定・自動判定ともに pdfTeX 経路で完走（全フィクスチャ rc=0） |
| `article` / `report` / `book` / `article_type=…` | jlreq.cls:110–113 | 文書タイプ | **implemented** | M6 | `book`（\chapterが「第1章」出力）・`report` 実測 rc=0 |

### 2.2 紙・版面

| オプション | 定義行 | 役割 | pdfTeX ステータス | 対応工程 | 備考 |
|---|---|---|---|---|---|
| `paper=…`（a0–a10, b0–b10, b0j–b10j, c2–c8, a4var, b5var, letter, legal, executive, ansia–ansie, hagaki, または `幅,高さ`） | jlreq.cls:135–147, 194–276 | 用紙サイズ | **implemented** | M2/M6 | `paper=b5` 実測（options-sweep.tex）。`\pdfpagewidth`/`\pdfpageheight` は pdfTeX 互換で流用 |
| `a0paper`–`a10paper` 等（サイズ名キー一式） | jlreq.cls:206–276 | 用紙サイズショートカット | **implemented** | M2/M6 | `a4paper` 実測。上に同じ |
| `fontsize=…` / `10pt` / `11pt` / `12pt` | jlreq.cls:290–294 | 欧文フォントサイズ | **implemented** | M2/M6 | `fontsize=12pt` 検証済み（options-sweep.tex）。Q/H単位も**implemented**（桁対応の書き換えで 1Q=1H=0.25mm に変換）: `fontsize=13Q` 実測 9.24695pt（options-qh-units.tex）。`fontsize=1.2zw` のような zw/zh 指定は自己参照になるため jlreq.cls:611–626 のガードが明示 ClassError を発する（以前は暗黙に 0pt 化していた） |
| `jafontsize=…` | jlreq.cls:295 | 和文フォントサイズ | **implemented** | M2 | `jafontsize=13pt` 実測: JAFS=13pt/FS=13pt/SCALE=1。`jafontsize=13Q` も実測（options-qh-units.tex、Q/H単位対応済み） |
| `jafontscale=…` | jlreq.cls:296 | 和文/欧文サイズ比 | **implemented** | M2 | `jafontscale=1.2` 実測: SCALE=1.2/JAFS=11.99997pt 正常 |
| `line_length=…` | jlreq.cls:301 | 行長 | **implemented** | M6 | `line_length=40zw` 検証済み（options-sweep.tex） |
| `number_of_lines=…` | jlreq.cls:304 | 1 ページ行数 | **implemented** | M6 | `number_of_lines=10` 検証済み（options-sweep.tex） |
| `head_space=…` / `foot_space=…` / `gutter=…` / `fore_edge=…` / `fore-edge=…` | jlreq.cls:309–321 | 天・地・のど・小口 | **implemented** | M6 | options-sweep.tex で検証（pt指定）。縦組（`tate`）併用時の座標系は M7 |
| `baselineskip=…` / `linegap=…` | jlreq.cls:336–339 | 行送り | **implemented** | M6 | `baselineskip=20pt` 検証済み（options-sweep.tex）。zw/zhリテラルはクラスロード時書き換えパスで処理 |
| `column_gap=…` | jlreq.cls:332 | 段間 | **implemented** | M6 | `column_gap=2zw` 検証済み（options-sweep.tex + microtype-twocolumn.tex で二段組実測） |
| `sidenote_length=…` | jlreq.cls:355 | 傍注の長さ | **implemented** | M6 | `sidenote_length=5zw` 実測 rc=0（zwリテラル書き換え対象リストに追加済み） |
| `headfoot_verticalposition=…` / `headfoot_sidemargin=…` | jlreq.cls:326–329 | 柱・ノンブル位置 | **implemented** | M6 | `3zw`/`2zw` 指定実測 rc=0（zwリテラル書き換え対象） |

### 2.3 組み方

| オプション | 定義行 | 役割 | pdfTeX ステータス | 対応工程 | 備考 |
|---|---|---|---|---|---|
| `open_bracket_pos=`（`zenkaku_tentsuki`/`zenkakunibu_nibu`/`nibu_tentsuki`） | jlreq.cls:344 | 行頭括弧配置（3.1.5） | **implemented**（データ選択） | M4 | `zenkakunibu_nibu` 指定でJFM variant `z`（クラス1幅1.0+全クラス→1グルー−0.5）を選択、`nibu_tentsuki` は既定にフォールバック（pLaTeXと同一挙動）。行頭括弧フック自体は段落開始リセットのみで、空き規則はJFMデータが担う |
| `hanging_punctuation` | jlreq.cls:347 | ぶら下げ組み（3.8.2） | **implemented**（`-b`/`-bz` 変種のみ） | M5 | `\pdfprotrudechars=2`＋`\rpcode`（グリフごと遅延設定、突出し量1em=1zw）で行末突出し機構を実装（jlreq-pdftex-rules.sty:357–378）。実測: 右マージンカーン −10.0pt、インクが名目行端より 0.5zw 外へ出る（hanging-punct.tex、HANG-PASS 5アサーション）。先行メモ「pdfTeXに行末突出し機構なし」は誤りと判明（poc/README-g3b.md） |
| `narrow_kanjiskip` | jlreq.cls:350 | jsarticle 互換の詰め字間 | **implemented** | M4 | 実測: `\jlreqkanjiskip` = `0pt plus .1zw minus .01zw` に変化。未定義ペアのフォールバックグルーとして実行時に適用 |
| `use_reverse_pagination` | jlreq.cls:362 | 逆ノンブル | **implemented** | M6 | 実測 rc=0（auxラベル機構はエンジン非依存） |
| `disablejfam` | jlreq.cls:402 | 数式内和文の無効化 | **implemented** | M6 | jfam 相当は enablejfam（既定）で実装済み: `\mathmc`/`\mathgt` は `\mathchoice` ボックス経由で和文を供給（jlreq.cls:1329–1335）。数式中の直接和文入力・行列セル内和文も動作（math-jfm.tex、math-matrix.tex）。disablejfam 指定時は `\mathmc`/`\mathgt` 未定義のまま（(u)pTeX と同一パリティ、math-jfm-disablejfam.tex） |
| `tate` | jlreq.cls:376 | 縦組み | **blocked** | M7 | **G4 判定: structurally blocked**（判定記録: `docs/pdftex-tate-eval.md`）。`\tate`/`\adjustbaseline`（jlreq.cls:532）は pdfTeX に存在しない。bxcjkvert は CTAN `language/japanese/BX/bxcjkjatype/` 配下に実在（v0.5a）し取得・再評価済み——CJKvert の副作用は解消するが提供範囲はグリフ回転＋方向切替までで、約物の縦用配置（実測で 、。が cell 左下、要件は右上）・縦中横・縦 JFM・用紙モデルは全層未到達（poc/v3-*.tex）。明示エラーゲートを維持（T2 回帰監視） |
| `landscape` | jlreq.cls:372 | 横置き | **implemented** | M2 | `landscape,a4paper` 実測: 841.89×595.28pt（縦横交換） |
| `tombo` / `tombow` / `mentuke` | jlreq.cls:373–375 | トンボ（jlreq-trimmarks.sty へ案内） | **implemented** | M6 | jlreq-trimmarks は pdfTeX でトンボ描画・TrimBox/BleedBox・回転バナー（`\rotatebox{-90}` 代替）に対応（trimmarks.tex、trimmarks-banner.tex）。クラスオプション経由の案内は従来どおり警告で trimmarks.sty へ |
| `oneside` / `twoside` / `onecolumn` / `twocolumn` / `titlepage` / `notitlepage` | jlreq.cls:382–387 | ページ構成 | **implemented** | M6 | `twoside`+`titlepage`（book）実測 rc=0、`twocolumn` 実測（microtype-twocolumn）、`notitlepage`+`onecolumn`+`oneside`（report）実測 rc=0 |
| `draft` / `final` | jlreq.cls:388–389 | 下書きモード | **implemented** | M6 | `draft` 実測 rc=0 |
| `openright` / `openany` / `leqno` / `fleqn` | jlreq.cls:395–398 | 書籍構成・数式番号 | **implemented** | M6 | `openright`+`leqno`+`fleqn` 実測 rc=0 |
| `jlreq_notes` | jlreq.cls:405 | JLREQ 注記の表示 | **implemented** | M1 相当 | `\message` のみでエンジン非依存。ただし注記の「行長は52文字以下…」（jlreq.cls:1631 等）は版面計算成立後に意味を持つ |

## 3. `\jlreqsetup` キー

`jlreq.cls` 内の全 `\keys_define:nn { jlreqsetup }` ブロック（3393, 3481, 3490, 3524, 3735, 3828, 3852, 3922, 3995, 4032, 5343, 5430, 5638, 5816, 5844, 5980, 6175, 6248, 6283, 6320, 6516 行）から抽出した全キー。pdfTeX 経路でも `\jlreqsetup` はそのまま動作し、長さ値のリテラル `zw`/`zh`/`Q`/`H` 書き換え（jlreqsetup 用の latin-zw/Q/H 書き換えパス）にも対応済み（jlreqsetup-zw.tex）。

| キー（代表例） | 定義行（代表） | 役割 | pdfTeX ステータス | 対応工程 | 備考 |
|---|---|---|---|---|---|
| `reference_mark=`（`inline`/`interlinear`） | jlreq.cls:3393–3427 | 合印（4.2.3） | **implemented**（inline / interlinear 両方） | M6 | `inline` 実測 rc=0。`interlinear` も implemented（fixjfm シムのスナップショット/リストアで状態機構との整合を確保）: 合印を跨ぐ JA ペアグルーが直接配置と一致（30.0pt==30.0pt、reference-mark-interlinear.tex、INTER-PASS 3アサーション） |
| `footnote_indent=…` / `footnote_second_indent=…` | jlreq.cls:3481, 3490 | 脚注の字下げ（4.2.5） | **implemented** | M6 | `2\zw`/`1\zw` 形式に加えリテラル `2zw` も対応（jlreqsetup の latin-zw 書き換え）: `footnote_indent=2zw` 実測 JSETUP-FNI=20.0pt（jlreqsetup-zw.tex） |
| `endnote_counter=…` / `endnote_second_indent=…` / `endnote_position=…` | jlreq.cls:3735, 3829, 3852 | 後注（4.2.4） | **implemented**（キー設定） | M6 | `endnote_second_indent=2\zw`+`endnote_position=headings` 実測 rc=0 |
| `sidenote_type=` / `sidenote_counter=…` / `sidenote_symbol=…` / `sidenote_keyword_font=…` | jlreq.cls:3922, 3995 | 傍注（4.2.7） | **implemented** | M6 | `\sidenote` 命令が両型で動作（下表4.1参照）: number 型（sidenote.tex）、symbol 型（sidenote-symbol.tex）とも rc=0 |
| `warichu_opening=…` / `warichu_closing=…` | jlreq.cls:4032–4045 | 割注（3.4）の括弧 | **implemented** | M6 | options-sweep.tex で検証、\warichu 自動2行折返し実測（footnotes-warichu.tex、3パスで安定） |
| `caption_font=…` / `caption_label_font=…` / `caption_label_format=…` / `caption_after_label_space=…` / `caption_align=…` | jlreq.cls:5343, 5430 | キャプション | **implemented** | M6 | caption_font/label_format 検証済み（options-sweep.tex）、caption を含む表・図は table-tabular/graphicx-xcolor で実測 |
| `abstract_with_maketitle=` | jlreq.cls:5638 | abstract の配置 | **implemented** | M6 | `abstract_with_maketitle=true`+\maketitle 実測 rc=0 |
| `itemization_beforeafter_space=…` / `itemization_itemsep=…` / `itemization_labelsep=…` / `itemization_label_length=…` | jlreq.cls:5816 | 箇条書き | **implemented** | M6 | itemization_* 検証済み（options-sweep.tex）、リスト実測（lists.tex） |
| `quote_indent=…` / `quote_end_indent=…` / `quote_fontsize=…` / `quote_beforeafter_space=…` | jlreq.cls:5844 | 引用 | **implemented** | M6 | quote_indent=2\zw 実測 rc=0。リテラル形式も対応: `quote_indent=2zw` 実測 JSETUP-QI=20.0pt、`quote_end_indent=0.5zw` 実測 JSETUP-QEI=5.0pt（jlreqsetup-zw.tex） |
| `tableofcontents_heading=…` / `tableofcontents_twocolumn=` | jlreq.cls:5980 | 目次 | **implemented** | M6 | `tableofcontents_heading` 実測 rc=0（2パス）。リーダーの\inhibitglueはno-opシムで無害化、headings-toc-aux.tex で目次・\ref 往復実測 |
| `frontmatter_*` / `mainmatter_*` / `backmatter_*`（pagebreak/pagestyle/counter/heading/precode/postcode/pagination 計 21 キー） | jlreq.cls:6176, 6249, 6284 | 前付・本体・後付 | **implemented**（既定動作） | M6 | \frontmatter/\mainmatter/\backmatter 実測 rc=0（book、ローマ数字→アラビア数字切替）。個別キー上書きは未網羅 |
| `appendix_counter=…` / `appendix_heading=…` / `appendix_precode=…` / `appendix_postcode=…` | jlreq.cls:6321 | 付録 | **implemented**（横組既定） | M6 | \appendix+\chapter 実測 rc=0（横組）。縦組時の `\tatechuyoko*` は M7 |
| `year_style=`（`seireki`/`wareki`） | jlreq.cls:6516–6519 | 西暦/和暦 | **implemented**（横組） | M6 | `wareki` 実測 rc=0。\todayは横組固定。`\kansuji` は展開可能マクロとして実装済み（4.1の行を参照） |

## 4. 公開命令・環境

### 4.1 基本組版（横組み）

| 命令/環境 | 定義行 | 役割 | pdfTeX ステータス | 対応工程 | 備考 |
|---|---|---|---|---|---|
| `\zw` / `\zh` / `\Cht` / `\Cdp` / `\Cwd` / `\Cvs` / `\Chs` | jlreq.cls:1333–1338（C* 系）、524–527（zw/zh） | 全角単位・文字寸法 | **implemented** | M2 | G1実証済み: Cwd=10.0/Cht=8.8/Cdp=1.2/Cvs=17/Chs=10pt @10pt、\zw/\zh=dimenレジスタマクロ（サイズ追従）。pairs.tex 7計測で精度確認 |
| `\jafontsize` | jlreq.cls:1295 | 和文サイズ指定付きフォントサイズ変更 | **implemented** | M2 | jafontsize=13pt/jafontscale=1.2 実測（表2.2参照） |
| `\mcfamily` / `\gtfamily` / `\bfseries` 等の和文ファミリ連動 | jlreq.cls:1156–1162 | 欧文 NFSS と和文ファミリの連動 | **implemented** | M2/M6 | bxcjkjatypeフック（C70/ipxm・ipxg）＋selectfontフックのseries追跡（カーネル判定 b始まり=太字）。\gtfamily見出し実測（mixed）、CJKbold 2 Tr 実測（italic-substitution.tex） |
| `\jaspace=`（`zenkaku`/`nibu`/`shibu`） | jlreq.cls:1180, 1205 | 和文間隔 | **implemented** | M4 | `\jaspace{zenkaku}`/`{nibu}` 実測 rc=0（全角・二分の\hskip）。`\　`綴は**blocked**: pdfTeXではU+3000がletterでなく制御綴化できない（`\ifcat A　`=FALSE実測）。U+3000リテラル文字はCJK文字として正常出力 |
| 区切り約物（`！？`）直後の空き | jlreq.cls:1223–1230 | 区切り約物（4.2.8）直後の空き | **implemented**（JFMデータ） | M4 | jlreq APIは文字入力ベースで、直後の空きはJFMクラスペアグルー（クラス5の pair 5→c グルー）で処理。`\！`なる単独命令はjlreq APIではなくpTeXカーネル由来（pdfTeXでは未定義=非API） |
| `\jidori` | jlreq.cls:6433, 6450 | 字取り（2.2.2） | **implemented** | M4 | 自前グルー規則のjidorimode=2（文字間 0pt+1fil、\hbox to Lで均等分散）。実測: \jidori{60pt}{字取} で文字間13.2ptに分散 |
| `\akigumi` | jlreq.cls:6462 | 空き組み | **implemented** | M4 | jidorimode=1（文字間に固定空き）。実測: \akigumi{3pt}{空き組} で文字間13.0pt（10pt字面+3pt空き） |
| `\tatechuyoko` | jlreq.cls:6336 | 縦中横 | **blocked** | M7 | **G4**。縦組み専用。pdfTeX で縦組の縦中横は M7 の実証対象 |
| `\warichu` / `\inlinenote` | jlreq.cls:4020, 4026 | 割注（3.4） | **implemented** | M6 | \warichu 自動位置計算2行折返し実測（footnotes-warichu.tex、3パス安定）。括弧測定はJFMデータ、\inhibitglueはno-opシム |
| `\footnote` / `\footnotemark` / `\footnotext` | jlreq.cls:3532–3555（フック適用） | 脚注（4.2.5） | **implemented** | M6 | footnotes-rules.tex で3種すべて実測 rc=0（脚注内の禁則・ペアグルーもbbox走査で確認）。注記フックの`\lastnodechar`依存は-1固定で無害化 |
| `\endnote` / `\endnotemark` / `\endnotext` / `\theendnotes` | jlreq.cls:3746, 3751, 3798 | 後注（4.2.4） | **implemented** | M6 | キー実測（表3.1）＋脚注と同一の注記経路 |
| `\sidenote` / `\sidenotemark` / `\sidenotetext` | jlreq.cls:3929–3931, 3974–3976 | 傍注（4.2.7） | **implemented** | M6 | 両型とも動作（sidenote.tex、sidenote-symbol.tex、rc=0）。旧障害の根因は2件とも修正済み: (1) `\marginpar` ボックス調整の `\jlreq@jareg` 桁連結（`Dimension too large`、jlreq.cls:1468–1477 修正）、(2) 既定＊マークの素 `\edef` がアクティブ CJK 文字を潰す問題（`\protected@edef` 化、jlreq.cls:4204–4217）。縦組時の傍注は M7 |
| `\西暦` / `\和暦` / `\today` / `\kansuji` | jlreq.cls:6471–6473, 6496 | 日付表記・漢数字 | **implemented**（横組） | M6 | year_style=wareki 実測。\todayは横組`\number`版固定。`\kansuji` は pTeX と同一仕様の桁置換展開可能マクロ `\jlreq@pdf@kansuji` として実装（jlreq-pdftex.sty:162–209）、`\jlreq@Kanji` の使用時 ClassError は撤去（jlreq.cls:1631–1636）。13値を uplatex と突合して全一致（kanji-numbers.tex、KANSUJI-PASS 13アサーション）。`\thechapter` 再定義経由の横組利用もフィクスチャ実証済み |
| `\　`（`U+3000`）の後続空白無視 | jlreq.cls:1180–1203 | 全角空白の後の空白処理 | **blocked**（綴不可） | M4 | `\　`綴自体がpdfTeXで成立しない（上記）。U+3000リテラルは空白単体を直接含むため後続空白無視は不要 |

### 4.2 見出し

| 命令/環境 | 定義行 | 役割 | pdfTeX ステータス | 対応工程 | 備考 |
|---|---|---|---|---|---|
| `\DeclareBlockHeading` / `\NewBlockHeading` / `\RenewBlockHeading` / `\ProvideBlockHeading` | jlreq.cls:2402, 2690–2696 | 別行見出しの宣言 | **implemented** | M6 | `font={size=14pt}` で宣言+使用を実測 rc=0。行取り計算の`\hbox{阿}`はG1実証済みメトリックで動作 |
| `\DeclareTobiraHeading` / `\NewTobiraHeading` / `\RenewTobiraHeading` / `\ProvideTobiraHeading` | jlreq.cls:1869, 1967–1973 | 扉見出しの宣言 | **implemented** | M6 | `number=true`で宣言+使用を実測 rc=0 |
| `\DeclareRuninHeading` / `\NewRuninHeading` / `\RenewRuninHeading` / `\ProvideRuninHeading` | jlreq.cls:3085, 3170–3176 | 同行見出しの宣言 | **implemented** | M6 | `font={size=12pt}`で宣言+使用を実測 rc=0 |
| `\DeclareCutinHeading` / `\NewCutinHeading` / `\RenewCutinHeading` / `\ProvideCutinHeading` | jlreq.cls:3264, 3306–3312 | 柱見出し（cut-in）の宣言 | **implemented** | M6 | `font={size=12pt}`で宣言+使用を実測 rc=0 |
| `\ModifyHeading` / `\SaveHeading` | jlreq.cls:3316, 3343 | 見出しの変更・保存 | **implemented** | M6 | `ModifyHeading{section}{number=false}`+`SaveHeading{section}{\savedsec}` 実測 rc=0 |
| `\SetBlockHeadingSpaces` | jlreq.cls:2740 | 別行見出しの空き設定 | **implemented** | M6 | `{_section {lines=2}}` 構文で実測 rc=0（uplatex/lualatexでも同一入力動作で回帰なし） |
| `chapter` / `section` / `subsection` 等の標準見出し | jlreq.cls:6548–6584（横組縦組両定義） | 標準見出し | **implemented**（横組）／**blocked**（縦組定義） | M6 / M7 | book/article双方で \chapter(第1章)/\section/\subsection 実測（full2/full3.tex、headings-toc-aux.tex）。縦組用定義は G4 |
| `\maketitle` / `abstract` 環境 | jlreq.cls:5527, 5557, 5641 | 表題・概要 | **implemented** | M6 | 実測: 表題/著者/日付/概要出力（full2.tex）。abstractはarticle/reportのみ（bookでは非定義=上流仕様どおり） |

### 4.3 ページスタイル・ページ構成

| 命令/環境 | 定義行 | 役割 | pdfTeX ステータス | 対応工程 | 備考 |
|---|---|---|---|---|---|
| `\DeclarePageStyle` / `\NewPageStyle` / `\ModifyPageStyle` | jlreq.cls:4964, 5238, 5247 | ページスタイルの宣言 | **implemented**（横組） | M6 | NewPageStyle+ModifyPageStyle 実測 rc=0。`tate`指定の縦組柱は M7 |
| `headings` / `myheadings` 等の既定ページスタイル | jlreq.cls:6599–6626 | 標準ページスタイル | **implemented** | M6 | `\pagestyle{headings}` 実測 rc=0。plain/headings/myheadings全て横組定義 |
| `\frontmatter` / `\mainmatter` / `\backmatter` | jlreq.cls:6234, 6261, 6308 | 前付・本体・後付 | **implemented** | M6 | book実測: ローマ数字ノンブル(iii/iv)→アラビア数字(1)切替、\appendix で付録A出力（full3.tex） |
| `\appendix` | jlreq.cls:6326 | 付録 | **implemented** | M6 | 実測: 付録A出力（full3.tex） |
| `\tableofcontents` / `theindex` / `thebibliography` | jlreq.cls:5955, 6066, 6038 | 目次・索引・参考文献 | **implemented**（toc/bibliography） | M6 | 目次リーダー・\bibitem 実測（full2/full3.tex、headings-toc-aux.tex）。`theindex` は横組文書で`\yoko`がno-opのため実質利用可 |
| `figure` / `table` / `caption` | jlreq.cls:5476, 5504（環境）、5306–5340（キャプション機構） | 図表 | **implemented** | M6 | figure/table+caption、tabular 実測 rc=0（env.tex、table-tabular.tex、graphicx-xcolor.tex） |
| `enumerate` / `itemize`（`\@listi`–`\@listvi` 再定義） / `quote` / `quotation` / `verse` / `description` | jlreq.cls:5835–5842（リスト初期化）、5873, 5893（quote 系）、5739（description） | 箇条書き・引用 | **implemented** | M6 | 6環境すべて実測 rc=0（env.tex、lists.tex） |

### 4.4 関連パッケージの公開 API

| パッケージ | 対象 | pdfTeX ステータス | 対応工程 | 備考 |
|---|---|---|---|---|
| `jlreq-helpers.sty` | エンジン検出・共通マクロ | **implemented**（検出部分、M1） | M1 | `\jlreq@helper@guessengine`（jlreq-helpers.sty:377–394）が `\pdftexversion` で `d` を返す。その他のマクロはエンジン非依存 |
| `jlreq-complements.sty` | thebibliography/theindex/定理環境のカスタマイズ | **implemented**（横組） | M6 | `pdflatex` オプション追加（jlreq-complements.sty:21–22）．pdfTeX 分岐: `\__jlreq_complements_iftdir:` 常に偽（横組のみ），`\inhibitglue` 無害化，`\jlreq@zw` はバックエンドの `\jlreq@jareg` にフォールバック．検証: amsthm定理・thebibliography・theindex入り文書がrc=0（tests/fixtures/pdflatex-coexist/） |
| `jlreq-trimmarks.sty` | トンボ・裁ち落とし | **implemented** | M6 | `pdflatex` エンジンオプション追加。plcore相当の最小実装を分離ファイル `jlreq-trimmarks-pdftex.def` で提供（`\iftombow`/`\@tombowwidth`/`\@@paper*`/`\@tombowreset@@paper` + `build/page/reset`・`shipout/background` フック，lltjcoreと同一設計）。**分離の理由**: d分岐の中身にpTeXで実在する条件名（`\iftombow`等）が含まれるため，`\ifx`偽の条件スキップが対応を壊す（実証済み）。PDF属性（TrimBox/BleedBox）は `\pdfpageattr` 経由の専用ドライバ `d`。検証: 4エンジンでrc=0，トンボ描画・拡大紙面（642.9×852.7pt）・抽出正常（tests/fixtures/pdflatex-coexist/trimmarks.tex）。回転バナーも implemented: `\rotatebox{-90}` 代替（jlreq-trimmarks-pdftex.def:64–78）、導入前後でトンボ描画は画素一致、uplatex とのパリティは center/top-right スロットで位置正確一致（trimmarks-banner.tex、trimmarks-banner-log-assertions） |
| `\jlreqtrimmarkssetup`（trimmarks の設定命令） | `trimmarks_paper=…` / `show=…` / `bleed_margin=…` / `trimmarks_width=…` / `color=…` / `trimmarks_pattern=…` / `banner=…` | **implemented** | M6 | pdfTeX経路でも動作。`banner=…` も implemented（回転は `\rotatebox{-90}` 代替、`tate` プリミティブ不要）。検証: trimmarks-banner.tex（バナー文字列回転表示・トンボ画素一致） |
| `\jlreqcomplementssetup`（complements 単独使用時の設定命令） | thebibliography_*/theindex_*/theorem_* 系キー | **implemented** | M6 | pdflatexオプション経由で動作（jlreq-complements.sty:11–22, 74–91, 123–150, 197–217） |

## 5. 完全性レベルと到達目標

| レベル（PLAN.md §1.2） | 内容 | 現状 |
|---|---|---|
| **L1 API互換** | 公開オプション・命令・環境 | 横組みスコープの全項目を本表で追跡・検証済み（非対応項目は limitation agreed / blocked として明示） |
| **L2 規則互換** | JFM・禁則・約物・和欧文間空き | M3–M5 で実装・検証。G2/G3 の成否が前提 |
| **L3 出力互換** | 改行・座標・ページ分割の等価性 | 望遠目標。pdfTeX と参照エンジンで字体・TFM が異なる限り、バイト一致ではなく「正規化した比較」を採用（PLAN.md §6.2 の注意） |

## 6. 既知の制約（現時点で確定しているもの）

1. **縦組み（`tate` オプション・縦組見出し・縦中横・縦組 `\kansuji`・`\today` 縦組）**： pdfTeX に `\tate`/`\yoko`/`\iftdir`/`\adjustbaseline` が存在しないため、G4 判定は **structurally blocked**（判定記録: `docs/pdftex-tate-eval.md`、2026-10-23 再調査版）。bxcjkvert は **CTAN `language/japanese/BX/bxcjkjatype/` 配下に実在**（v0.5a、初回調査の「実在しない」は誤りで取得のうえ再評価済み）——baselinestretch/フォントリセットの副作用は解消されるものの、回転ベースでは約物の縦用配置が規格不適合（実測）、縦中横・縦 JFM・用紙モデル・方向感応ページ家具の全層が未到達であり、JLREQ 4.2.2 適合の縦組みにはならない。横組み先行のマージを優先し、`tate` 明示エラーゲートを維持する（PLAN.md §3.6、§7）。なお回転バナーは縦組み本体ではなく graphicx `\rotatebox{-90}` で実装済み（4.4参照）。
2. **~~`mag` オプション相当（`\mag` 可変運用）~~ → 解決（2026-10-23）**： jlreq.cls:1677–1690 の d 分岐で `\pdfhorigin`=`\pdfvorigin`=`1truein` を再代入し `\pdfpagewidth`/`\pdfpageheight` を 1000/`\mag` 倍に再スケールする相殺を実装。実測: `\mag=1200` の版面寸法が uplatex 参照とビット等価（94.152bp）、`\mag=1000` では出力が導入前後でバイト一致。**残存（トンボ描画自身のみ）**： `\mag=1200` 併用時にトンボの描画座標が uplatex とずれる（shipout フックの `\put` 座標モデル由来。`\mag=1000` では描画もバイト一致）。テキストブロックの +1truein 再センタリングは jlreq-trimmarks-pdftex.def:61–71 で実装済み（uplatex 比較で y 誤差 ≤0.065bp、x ビット一致）。
3. **~~`hanging_punctuation`（ぶら下げ）の完全再現~~ → 実装済み（2026-10-23）**： 先行の「pdfTeX は行末突出し機構を持たない」は誤りと判明。`\pdfprotrudechars=2`＋`\rpcode` で `-b`/`-bz` 変種の句読点突出しを実装（2.3表・poc/README-g3b.md 参照）。LuaTeX-ja の `ltjenableadjust[lineend=extended,priority=true]`（jlreq.cls:502）相当の**優先順位付き伸縮**の厳密な意味論は、引き続き近似（shrink 畳み込み、実害非計測——poc/README-m5-numeric.md）として残る。
4. **~~数式内和文（jfam）~~ → 実装済み（2026-10-23）**： enablejfam（既定）で `\mathmc`/`\mathgt` を `\mathchoice` ボックス経由で提供（jlreq.cls:1329–1335）。数式中の直接和文入力・行列セル内和文も動作（math-jfm.tex / math-matrix.tex）。`\eqref`＋hyperref の和文文脈は当初から非破壊（eqref-hyperref.tex）。残る制限は**和文 `\label` 名**のみ（アクティブバイトが `\csname r@…\endcsname` 内で展開される素因で、しおり機構の兼ね合いから修正不能と合意。ASCII ラベルの回避策を eqref-hyperref.tex コメントに記録）。

## 7. 依存関係・ライセンス・動作環境

`docs/pdftex-dependencies.md` を参照（ライセンス境界の記録＝GPL依存と
コード流用の区別，TeX Live 2025検証実績，最低版は上流協議事項）。

microtype・二段組（`twocolumn`）との共存は
`tests/fixtures/pdflatex-coexist/microtype-twocolumn.tex` で検証済み
（rc=0，二段組レイアウト実測，microtypeの欧文プロトラクション有効化で
和文グルーとの衝突なし）。

### 既知の制限詳細（M4禁則エンジンの改修 2026-10-23追記）

**修正された重大バグ**: 禁則クラス表（`\jlreqpdf@kin@pre@<n>`等）が
`\def\jlreqpdf@kin@pre@2{10000}` 形式で定義されていたため、数字が制御綴名に
使えず「`\jlreqpdf@kin@pre`＋引数区切り`2`のマクロ」化し、**全禁則ペナルティが
一つも出力されていなかった**（`\ifcsname`検索で常に未定義）。
全表を `\expandafter\def\csname …\endcsname` 形式に修正。
ペアグルーの出力順も改修: 行頭禁則文字の直前のglue（自然長0を含む）は
改行候補点を作るため出力を抑制（`\relax`）し、行末禁則文字の直後の
境界glueも同様に抑制する `\jlreqpdf@kernmode` 機構を追加。

**残る既知の違反（1種）** → **修正済み（2026-10-23 追記2）**: 欧文の直後に
閉じ括弧が来る配置（例: `（x）` の x が行末に達する狭い行）で、まれに
`）` が次行頭に落ちる場合があった。原因はCJKデコーダ由来の
「`\CJKglue` シグネチャを持つ自然長0の外部グルー」が prebreak クラスの
前に残り、そこが改行候補点になっていたこと。該当グルーを検出して
`\unskip` する処理を追加し解消（preclose-latin.tex で検証、
kinsoku-bbox-line-head-scan で 0 違反を継続監視）。
（以下は修正前の調査記録）pdfTeXのCJK出力経路（UTF8デコーダ→`\CJKsymbol`）の
内部に出力ノードが介在し、`\penalty10000` をグリフ直前に置いても
別の改行候補点から回避されていた。手動 `\penalty10000` 挿入では
解消するが、旧バックエンドのフック位置では到達できなかった。

# pdfTeX 対応状況・公開 API 互換マトリクス（pdftex-compatibility）

- **対象リポジトリ**： [abenori/jlreq](https://github.com/abenori/jlreq)（基準コミット `ac06fd0`、2025-07-17 版 + M1 エンジン検出パッチ適用後の作業ツリー）
- **作成日**： 2026-10-23
- **位置づけ**： `PLAN.md` §2.2 が定義する監査成果物のひとつ。公開機能・オプションごとの pdfTeX 対応状況を `implemented / pending / blocked` で追跡する（PLAN.md §6.3「文書API互換表：全項目を `pass / limitation agreed / blocked` で追跡」）。
- **現時点の状態（2026-10-23、M2–M6 実装完了）**： pdfTeX で `\documentclass{jlreq}` は横組文書として動作する（実験的サポート）。バックエンド `jlreq-pdftex.sty`（フォント・単位・メトリック）＋ `jlreq-pdftex-rules.sty`（JFMペアグルー・禁則・和欧文間隔・end_adjust近似）＋ 生成済みJFMデータ4変種（`jlreq-pdftex-jfm*.def`）。縦組み（`tate`）は明示エラー（G4判定: blocked）。既知の制限・残作業は本文のマトリクスと `docs/pdftex-audit.md` を参照。

## 1. ステータス定義

| ステータス | 意味 |
|---|---|
| **implemented** | pdfTeX で動作することをテストで示した機能（現時点ではエンジン検出系のみ） |
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
| `pdflatex` | jlreq.cls:109 | pdfTeX 明示指定 | **implemented** | M1 | 指定後は jlreq.cls:479–485 の未対応エラーで停止 |
| `article` / `report` / `book` / `article_type=…` | jlreq.cls:110–113 | 文書タイプ | **implemented** | M6 | `book`（\chapterが「第1章」出力）・`report` 実測 rc=0 |

### 2.2 紙・版面

| オプション | 定義行 | 役割 | pdfTeX ステータス | 対応工程 | 備考 |
|---|---|---|---|---|---|
| `paper=…`（a0–a10, b0–b10, b0j–b10j, c2–c8, a4var, b5var, letter, legal, executive, ansia–ansie, hagaki, または `幅,高さ`） | jlreq.cls:135–147, 194–276 | 用紙サイズ | **implemented** | M2/M6 | `paper=b5` 実測（options-sweep.tex）。`\pdfpagewidth`/`\pdfpageheight` は pdfTeX 互換で流用 |
| `a0paper`–`a10paper` 等（サイズ名キー一式） | jlreq.cls:206–276 | 用紙サイズショートカット | **implemented** | M2/M6 | `a4paper` 実測。上に同じ |
| `fontsize=…` / `10pt` / `11pt` / `12pt` | jlreq.cls:290–294 | 欧文フォントサイズ | **implemented**（pt系） | M2/M6 | `fontsize=12pt` 検証済み（options-sweep.tex）。Q/H単位は**blocked**（pdfTeXのdimexprが解釈せず、明示エラー——既知制限） |
| `jafontsize=…` | jlreq.cls:295 | 和文フォントサイズ | **implemented**（pt系） | M2 | `jafontsize=13pt` 実測: JAFS=13pt/FS=13pt/SCALE=1。load時測定は正常動作。Q/H単位はblocked（fontsizeと同様） |
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
| `hanging_punctuation` | jlreq.cls:347 | ぶら下げ組み（3.8.2） | **limitation agreed**（データ選択のみ） | M5 | オプションはエラーなく `-b` variant（end_adjust 6,7 に−0.5）を選択。行末突出し機構はpdfTeXに存在せず再現不能（G3判定済み・PLAN §3.5予期の「上限付き近似」の外）。確定した制限として合意事項 |
| `narrow_kanjiskip` | jlreq.cls:350 | jsarticle 互換の詰め字間 | **implemented** | M4 | 実測: `\jlreqkanjiskip` = `0pt plus .1zw minus .01zw` に変化。未定義ペアのフォールバックグルーとして実行時に適用 |
| `use_reverse_pagination` | jlreq.cls:362 | 逆ノンブル | **implemented** | M6 | 実測 rc=0（auxラベル機構はエンジン非依存） |
| `disablejfam` | jlreq.cls:402 | 数式内和文の無効化 | **implemented**（実質無操作） | M2 | 実測 rc=0。pdfTeXではjfamをロードしないため、このオプションは常に有効状態と同等 |
| `tate` | jlreq.cls:376 | 縦組み | **blocked** | M7 | **G4**。`\tate`/`\adjustbaseline`（jlreq.cls:532）は pdfTeX に存在しない。横組み先行でマージし、縦組みは独立ゲート |
| `landscape` | jlreq.cls:372 | 横置き | **implemented** | M2 | `landscape,a4paper` 実測: 841.89×595.28pt（縦横交換） |
| `tombo` / `tombow` / `mentuke` | jlreq.cls:373–375 | トンボ（jlreq-trimmarks.sty へ案内） | **implemented**（トンボのみ） | M6 | jlreq-trimmarks は pdfTeX でトンボ描画・TrimBox/BleedBox に対応（tests/fixtures/pdflatex-coexist/trimmarks.tex）。回転バナーは blocked（`\tate` 依存）。クラスオプション経由の案内は従来どおり警告で trimmarks.sty へ |
| `oneside` / `twoside` / `onecolumn` / `twocolumn` / `titlepage` / `notitlepage` | jlreq.cls:382–387 | ページ構成 | **implemented** | M6 | `twoside`+`titlepage`（book）実測 rc=0、`twocolumn` 実測（microtype-twocolumn）、`notitlepage`+`onecolumn`+`oneside`（report）実測 rc=0 |
| `draft` / `final` | jlreq.cls:388–389 | 下書きモード | **implemented** | M6 | `draft` 実測 rc=0 |
| `openright` / `openany` / `leqno` / `fleqn` | jlreq.cls:395–398 | 書籍構成・数式番号 | **implemented** | M6 | `openright`+`leqno`+`fleqn` 実測 rc=0 |
| `jlreq_notes` | jlreq.cls:405 | JLREQ 注記の表示 | **implemented** | M1 相当 | `\message` のみでエンジン非依存。ただし注記の「行長は52文字以下…」（jlreq.cls:1631 等）は版面計算成立後に意味を持つ |

## 3. `\jlreqsetup` キー

`jlreq.cls` 内の全 `\keys_define:nn { jlreqsetup }` ブロック（3393, 3481, 3490, 3524, 3735, 3828, 3852, 3922, 3995, 4032, 5343, 5430, 5638, 5816, 5844, 5980, 6175, 6248, 6283, 6320, 6516 行）から抽出した全キー。**現時点で pdfTeX から `\jlreqsetup` に到達することはない**（クラスが 479–485 行で停止するため）。全キーが pending であり、対応工程はバックエンドの進捗に従う。

| キー（代表例） | 定義行（代表） | 役割 | pdfTeX ステータス | 対応工程 | 備考 |
|---|---|---|---|---|---|
| `reference_mark=`（`inline`/`interlinear`） | jlreq.cls:3393–3427 | 合印（4.2.3） | **inline implemented / interlinear limitation agreed** | M6 | `inline` 実測 rc=0。`interlinear` は `\lastnodechar`（pdfTeXで-1固定）依存の位置計算が原理的に不能——確定制限（行間合印ではなくinline合印での代替を案内） |
| `footnote_indent=…` / `footnote_second_indent=…` | jlreq.cls:3481, 3490 | 脚注の字下げ（4.2.5） | **implemented** | M6 | `2\zw`/`1\zw` 形式で実測 rc=0（リテラル `2zw` は不可——既知制限） |
| `endnote_counter=…` / `endnote_second_indent=…` / `endnote_position=…` | jlreq.cls:3735, 3829, 3852 | 後注（4.2.4） | **implemented**（キー設定） | M6 | `endnote_second_indent=2\zw`+`endnote_position=headings` 実測 rc=0 |
| `sidenote_type=` / `sidenote_counter=…` / `sidenote_symbol=…` / `sidenote_keyword_font=…` | jlreq.cls:3922, 3995 | 傍注（4.2.7） | **blocked**（命令側と同根） | M6 | キー設定自体は動作するが、`\sidenote` 命令が現状pdfTeXで動かないため実質利用不可（上記参照） |
| `warichu_opening=…` / `warichu_closing=…` | jlreq.cls:4032–4045 | 割注（3.4）の括弧 | **implemented** | M6 | options-sweep.tex で検証、\warichu 自動2行折返し実測（footnotes-warichu.tex、3パスで安定） |
| `caption_font=…` / `caption_label_font=…` / `caption_label_format=…` / `caption_after_label_space=…` / `caption_align=…` | jlreq.cls:5343, 5430 | キャプション | **implemented** | M6 | caption_font/label_format 検証済み（options-sweep.tex）、caption を含む表・図は table-tabular/graphicx-xcolor で実測 |
| `abstract_with_maketitle=` | jlreq.cls:5638 | abstract の配置 | **implemented** | M6 | `abstract_with_maketitle=true`+\maketitle 実測 rc=0 |
| `itemization_beforeafter_space=…` / `itemization_itemsep=…` / `itemization_labelsep=…` / `itemization_label_length=…` | jlreq.cls:5816 | 箇条書き | **implemented** | M6 | itemization_* 検証済み（options-sweep.tex）、リスト実測（lists.tex） |
| `quote_indent=…` / `quote_end_indent=…` / `quote_fontsize=…` / `quote_beforeafter_space=…` | jlreq.cls:5844 | 引用 | **implemented** | M6 | quote_indent=2\zw 実測 rc=0。値は `2\zw` 形式（リテラル `2zw` はpdfTeXで不可——既知制限） |
| `tableofcontents_heading=…` / `tableofcontents_twocolumn=` | jlreq.cls:5980 | 目次 | **implemented** | M6 | `tableofcontents_heading` 実測 rc=0（2パス）。リーダーの\inhibitglueはno-opシムで無害化、headings-toc-aux.tex で目次・\ref 往復実測 |
| `frontmatter_*` / `mainmatter_*` / `backmatter_*`（pagebreak/pagestyle/counter/heading/precode/postcode/pagination 計 21 キー） | jlreq.cls:6176, 6249, 6284 | 前付・本体・後付 | **implemented**（既定動作） | M6 | \frontmatter/\mainmatter/\backmatter 実測 rc=0（book、ローマ数字→アラビア数字切替）。個別キー上書きは未網羅 |
| `appendix_counter=…` / `appendix_heading=…` / `appendix_precode=…` / `appendix_postcode=…` | jlreq.cls:6321 | 付録 | **implemented**（横組既定） | M6 | \appendix+\chapter 実測 rc=0（横組）。縦組時の `\tatechuyoko*` は M7 |
| `year_style=`（`seireki`/`wareki`） | jlreq.cls:6516–6519 | 西暦/和暦 | **implemented**（横組） | M6 | `wareki` 実測 rc=0。\todayは横組固定。`\kansuji`は使用時エラー（M7縦組と同様の代替でM5/M7で評価） |

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
| `\sidenote` / `\sidenotemark` / `\sidenotetext` | jlreq.cls:3929–3931, 3974–3976 | 傍注（4.2.7） | **blocked**（未統合） | M6 | `number`型は `Dimension too large`（\jlreq@tempdima代入、\marginpar内部のボックス調整で未解決）、`symbol`型は `\CJK@punctchar` 内部エラー。\marginpar単体と\footnote/\endnoteは代替として動作。縦組時の傍注は M7 |
| `\西暦` / `\和暦` / `\today` | jlreq.cls:6471–6473, 6496 | 日付表記 | **implemented**（横組） | M6 | year_style=wareki 実測。\todayは横組`\number`版固定。`\kansuji`代替はM7 |
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
| `jlreq-trimmarks.sty` | トンボ・裁ち落とし | **implemented**（トンボのみ） | M6 | `pdflatex` エンジンオプション追加。plcore相当の最小実装を分離ファイル `jlreq-trimmarks-pdftex.def` で提供（`\iftombow`/`\@tombowwidth`/`\@@paper*`/`\@tombowreset@@paper` + `build/page/reset`・`shipout/background` フック，lltjcoreと同一設計）。**分離の理由**: d分岐の中身にpTeXで実在する条件名（`\iftombow`等）が含まれるため，`\ifx`偽の条件スキップが対応を壊す（実証済み）。PDF属性（TrimBox/BleedBox）は `\pdfpageattr` 経由の専用ドライバ `d`。検証: 4エンジンでrc=0，トンボ描画・拡大紙面（642.9×852.7pt）・抽出正常（tests/fixtures/pdflatex-coexist/trimmarks.tex）。**制限**: 回転バナーは `\tate` 依存のためpdfTeXでは不可（既定 `tombowdatefalse` でトンボのみ） |
| `\jlreqtrimmarkssetup`（trimmarks の設定命令） | `trimmarks_paper=…` / `show=…` / `bleed_margin=…` / `trimmarks_width=…` / `color=…` / `trimmarks_pattern=…` | **implemented** | M6 | pdfTeX経路でも動作（バナー系キーはpdfTeXでは無効）。`banner=…` は **blocked**（回転に `\tate` 必須，pTeXプリミティブ） |
| `\jlreqcomplementssetup`（complements 単独使用時の設定命令） | thebibliography_*/theindex_*/theorem_* 系キー | **implemented** | M6 | pdflatexオプション経由で動作（jlreq-complements.sty:11–22, 74–91, 123–150, 197–217） |

## 5. 完全性レベルと到達目標

| レベル（PLAN.md §1.2） | 内容 | 現状 |
|---|---|---|
| **L1 API互換** | 公開オプション・命令・環境 | 表の全項目をテストで追跡する段階にすら未到達（クラスが停止するため）。M2 で最初の項目（紙・単位系）から開始 |
| **L2 規則互換** | JFM・禁則・約物・和欧文間空き | M3–M5 で実装・検証。G2/G3 の成否が前提 |
| **L3 出力互換** | 改行・座標・ページ分割の等価性 | 望遠目標。pdfTeX と参照エンジンで字体・TFM が異なる限り、バイト一致ではなく「正規化した比較」を採用（PLAN.md §6.2 の注意） |

## 6. 既知の制約（現時点で確定しているもの）

1. **縦組み（`tate` オプション・縦組見出し・縦中横・縦組バナー）**： pdfTeX に `\tate`/`\yoko`/`\iftdir`/`\adjustbaseline` が存在しないため、G4（M7）を通過しない限り「縦組み非対応」として明示する。横組み先行のマージを優先する（PLAN.md §3.6、§7）。
2. **`mag` オプション相当（`\mag` 可変運用）**： pdfTeX は `\mag=1000` 固定である。jlreq の `truein` 補正経路（jlreq.cls:1687, 1753、jlreq-trimmarks.sty:534–535）は pTeX 系 DVI 用であり、pdfTeX では `\mag` 可変をサポートしない。
3. **`hanging_punctuation`（ぶら下げ）の完全再現**： LuaTeX-ja の `ltjenableadjust[lineend=extended,priority=true]`（jlreq.cls:502）相当の行末調整は、pdfTeX 標準の行分割器と glue/penalty のみでどこまで再現できるかが G3 の判定事項である。上限付きの近似になる可能性を PLAN.md §3.5 は予期している。
4. **数式内和文（jfam）**： `\DeclareSymbolFont{mincho}`（jlreq.cls:1166–1173）の pdfTeX 版設計は M6 で必要。`disablejfam` オプションとの整合を保つ。

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

**残る既知の違反（1種）**: 欧文の直後に閉じ括弧が来る配置
（例: `（x）` の x が行末に達する狭い行）で、まれに `）` が次行頭に
落ちる場合がある。pdfTeXのCJK出力経路（UTF8デコーダ→`\CJKsymbol`）の
内部に出力ノードが介在し、`\penalty10000` をグリフ直前に置いても
別の改行候補点から回避されるため。手動 `\penalty10000` 挿入では
解消するが、バックエンドのフック位置では到達できない。
通常の和文主体の文書では発生しない（kinsoku.tex・本文テスト全て0違反）。
対応は後続工程でCJKデコーダ層への追加フックにより検討する。

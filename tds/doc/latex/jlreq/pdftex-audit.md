# pdfTeX バックエンド化に向けたエンジン依存箇所の監査（pdftex-audit）

- **対象リポジトリ**： [abenori/jlreq](https://github.com/abenori/jlreq)（基準コミット `ac06fd0`、2025-07-17 版 + M1 エンジン検出パッチ適用後の作業ツリー）
- **監査日**： 2026-10-23
- **目的**： `PLAN.md`（§2.2・§12）に基づき、pdfTeX に存在しないプリミティブ・エンジン依存分岐をすべて列挙し、pdfTeX バックエンド（`jlreq-pdftex.sty`、PLAN.md §3）実装の入力資料とする。
- **前提**： pdfTeX には pTeX 系・LuaTeX(-ja) 系の日本語組版プリミティブが**存在しない**。`\directlua`、`\epTeXinputencoding`、`\inhibitglue`、`\inhibitxspcode`、`\lastnodechar`、`\prebreakpenalty`、`\postbreakpenalty`、`\kanjiskip`、`\xkanjiskip`、`\autospacing`/`\autospc`、`\iftdir`、`\tate`/`\yoko`、`\adjustbaseline`、`\kansuji`、`\ucs` はいずれも pdfTeX では未定義である。本監査で列挙する各呼出箇所は、pdfTeX 実行時にこれらの未定義制御綴を踏む箇所そのものである。
- **行番号について**: 現行リポジトリの実ファイルから取得した実在行番号である。M1 パッチ（エンジン検出・`pdflatex` オプション・明示的エラーの追加）適用後の `jlreq.cls`（全 6848 行）・`jlreq-helpers.sty`（515 行）・`jlreq-complements.sty`（280 行）・`jlreq-trimmarks.sty`（1047 行）に基づく。

## 0. エンジン分岐の全体構造（`\jlreq@engine` の `l` / `p` / `u` / `d`）

クラスは単一の文字トークン `\jlreq@engine`（`l`=LuaLaTeX、`p`=pLaTeX、`u`=upLaTeX、`d`=pdfLaTeX〔M1 で追加〕）でエンジンを判別する。全 40 箇所の分岐が存在する。**`l` でなければ pTeX 系の分岐に入る**構造であり、pdfTeX は M1 の明示エラー（`jlreq.cls` 479–485 行）で停止しない限り、**pTeX 専用プリミティブを踏んで破綻する**。これが M1 で「黙って異常な PDF を出さず明確なエラーを出す」(PLAN.md §5 M1) 設計になっている理由である。

| 分岐 | 位置（jlreq.cls） | 内容 | pdfTeX での落入り先 |
|---|---|---|---|
| エンジンオプション | 104–109 | `uplatex`/`platex`/`lualatex`/`pdflatex` 各キーが `\jlreq@engine` に `u`/`p`/`l`/`d` を設定 | `pdflatex` キーは M1 で利用可能 |
| 自動判定 | 448–456 | 未指定時 `\jlreq@helper@guessengine` の結果を設定 | pdfTeX では `d` を返す（helpers 380–392 行） |
| 指定/実エンジン照合 | 458–477 | 明示指定と実エンジンの不一致を `\ClassError` | M1 で追加 |
| pdfTeX 明示エラー | 479–485 | `d` の場合はバックエンド未完成エラー | M1 で追加 |
| `l` 分岐（LuaTeX-ja 路線） | 488–507 | `luatexja`/`luatexja-adjust` ロード、ltj パラメータ設定 | pdfTeX は不进入 |
| 非 `l` 分岐（(u)pTeX 路線） | 508–517 | `everyhook` ロード、JFM 名組み立て | **pdfTeX はここに落ちる**（`\epTeXinputencoding` が未定義でエラー） |
| 非 `l` 分岐（和文使用可能化） | 522–527 | `\epTeXinputencoding utf8`、`\zw`/`\zh` 定義 | pdfTeX は 523 行で即エラー |

以降の `\ifx l\jlreq@engine` 分岐（全部で jlreq.cls 内 37 箇所、後述の個別監査表参照）は、`else` 側がすべて pTeX 専用プリミティブを含む。pdfTeX バックエンドでは、これらの `else` 側に相当する処理を `jlreq-pdftex.sty` 側の実装へ置き換える第三の分岐を設ける必要がある（PLAN.md §3.1「既存の複数箇所から必要な最小のフックだけを追加」）。

## 1. エンジン依存箇所の全一覧

分類は PLAN.md §5 M0 のとおり：**フォント / JFM / 組方向 / 文字ノード / PDFドライバ / エンコーディング**。

### 1.1 エンジン検出とクラスオプション（M1 対応済み）

| # | 位置 | シンボル/プリミティブ | 役割 | 提供エンジン | 分類 | pdfTeX での代替戦略 |
|---|---|---|---|---|---|---|
| A1 | jlreq-helpers.sty:377–394 | `\jlreq@helper@guessengine`（`\directlua`/`\pdftexversion`/`\ucs` のプリミティブ判定） | エンジン自動判定。`\directlua` があれば `l`、`\pdftexversion` があれば `d`、さらに `\ucs` の符号位置で `u` を判別 | 判定対象は各エンジン固有プリミティブ | エンコーディング | **M1 実装済み**（`\pdftexversion` で `d` を返す、helpers 380–392 行） |
| A2 | jlreq.cls:104–109 | `uplatex`/`platex`/`lualatex`/`pdflatex` オプション（`\DeclareKeys[jlreq]`） | 明示エンジン指定 | — | エンコーディング | **M1 実装済み**（109 行に `pdflatex` 追加） |
| A3 | jlreq.cls:458–477 | `\jlreq@helper@guessengine` 再呼出し | 明示指定と実エンジンの照合・エラー | — | エンコーディング | **M1 実装済み**（不一致時に `\ClassError`） |
| A4 | jlreq.cls:479–485 | `d` 判定 | バックエンド未完成の明示エラー | — | エンコーディング | **M1 実装済み**（`pdfTeX is not yet supported` エラー） |
| A5 | jlreq-complements.sty:11–21, 25–35 | `g__jlreq_complements_engine_str`、`uplatex`/`platex`/`lualatex` キー | complements 側のエンジン判別 | — | エンコーディング | **M1 対応**：31 行 `pdflatex` 判別追加、37–43 行で明示エラー。バックエンド実装時に `pdflatex` キーと非縦組み時方向判定を追加（PLAN.md §5 M6） |
| A6 | jlreq-trimmarks.sty:44–54, 504–517 | `\jlreq@trimmarks@engine`、`lualatex`/`uplatex`/`platex` キー | trimmarks 側のエンジン判別 | — | PDFドライバ | **M1 対応**：509–516 行で pdfTeX 明示エラー。バックエンド実装時に PDF 出力経路を追加（PLAN.md §5 M6） |

### 1.2 LuaTeX (-ja) 専用 API（`l` 分岐、`directlua` / ltj 系）

pdfTeX には `\directlua` も ltj コールバック API も存在しない。`l` 分岐は pdfTeX では到達不能にするほかない。

| # | 位置 | シンボル/プリミティブ | 役割 | 提供エンジン | 分類 | pdfTeX での代替戦略 |
|---|---|---|---|---|---|---|
| L1 | jlreq.cls:488–494 | `\directlua`（`jlreq` Lua テーブル、`jlreq.open_bracket_pos`、`jlreq.burasage`） | JFM へのパラメータ受け渡し（jfm-jlreq.lua が読む） | LuaTeX | JFM | `jlreq-pdftex-jfm.def` 生成時にこれらパラメータをビルド時 Lua で埋め込む（PLAN.md §3.3） |
| L2 | jlreq.cls:496–501 | `\RequirePackage{luatexja}` / `[disablejfam]{luatexja}` | 和文組版基盤のロード | LuaTeX | フォント | `bxcjkjatype`（CJKutf8）で代替（PLAN.md §3.2） |
| L3 | jlreq.cls:502 | `\ltjenableadjust[lineend=extended,priority=true]` | 行末調整（`end_adjust`）の有効化 | LuaTeX-ja | JFM | pdfTeX 標準の glue/penalty で表現できる規則を優先（PLAN.md §3.5、ゲート G3） |
| L4 | jlreq.cls:503–504 | `\ltjsetparameter{stretch_priority=…}` / `{shrink_priority=…}` | (x)kanjiskip の伸び縮み優先順位 | LuaTeX-ja | JFM | 優先度付き伸縮は pdfTeX 改行器に直接対応せず、規則を優先度順に展開した glue 列で近似（G3 で限界確定） |
| L5 | jlreq.cls:489–490 | `\ltj@stdyokojfm` / `\ltj@stdtatejfm` | LuaTeX-ja 標準 JFM 名の差し替え（`jlreq`/`jlreqv`） | LuaTeX-ja | JFM | 生成 JFM データを用いた独自ファミリ定義へ（M3） |
| L6 | jlreq.cls:581–584 | `\ltjgetparameter{direction}` / `{boxdir}` | 組方向・ボックス方向の取得（`\jlreq@ifydir` 等の定義） | LuaTeX-ja | 組方向 | pdfTeX では組方向は自前管理（クラス側で横/縦を明示追跡）するほかない（M7、G4） |
| L7 | jlreq.cls:605 | `\ltjgetparameter{postbreakpenalty}` | 改行後ペナルティの読み出し | LuaTeX-ja | 文字ノード | 文字クラステーブル参照の expl3 関数に置換（M3/M4） |
| L8 | jlreq.cls:623 | `\pdfvariable horigin` | 現在行残り幅計算での原点オフセット | LuaTeX | PDFドライバ | pdfTeX の `\pdfhorigin` 相当値（1in 基準）を直値で計算 |
| L9 | jlreq.cls:697 | `\directlua`（`luatexja.pltx_composite_last_node_char()`） | `\lastnodechar` の LuaTeX 実装（非公式 API） | LuaTeX-ja | 文字ノード | pdfTeX に直前文字を観測する API は存在しない。文字出力フック側で「直前文字」を自前追跡する状態機械が必要（M4、G2 の核心） |
| L10 | jlreq.cls:701–711 | `\directlua`（`tex.box["jlreq@tempboxb"].head` の glue 総和計算） | 2 文字間の JFM glue（伸縮込み）の実測 | LuaTeX | JFM | TeX 側の寸法計測（701–711 行の `\wd` 差分）だけを用い、伸縮量は生成 JFM データから計算（M3） |
| L11 | jlreq.cls:773 | `\directlua`（`tex.print` による除算） | `\jlreq@divide`（寸法の割り算） | LuaTeX | JFM | 既存の `\jlreq@helper@divide`（jlreq-helpers.sty:470–495 の整数反復版）を使用 |
| L12 | jlreq.cls:804–812 | `\directlua`（`Q`/`H`→`\dimexpr 0.25mm` の文字列置換） | `fontsize`/`jafontsize` オプションの Q・H 数値解釈 | LuaTeX | フォント | expl3 の `\tl_replace_all` 等で TeX 側処理に置換（M2） |
| L13 | jlreq.cls:1241–1249 | `\directlua`（`baselineskip` 文字列の Q/H/zw/zh 置換） | `baselineskip` オプション値の展開 | LuaTeX | フォント | 同上、TeX 側文字列処理（M2） |
| L14 | jlreq.cls:1469–1480 | `\directlua`（`zw`/`zh` → `\zw`/`\zh`） | `\jlreq@speciallength` の特殊単位展開 | LuaTeX | フォント | pdfTeX 用 `\zw`/`\zh` を実寸 dimen として定義済みなら同一の置換を TeX 側で実行（M2） |
| L15 | jlreq.cls:791–792 | `\ltjsetparameter{kanjiskip=…}` / `{xkanjiskip=…}` | 和文間・和欧文間グルーの設定 | LuaTeX-ja | JFM | pdfTeX には (x)kanjiskip なし。文字境界処理で明示的 glue 挿入へ（M4） |
| L16 | jlreq.cls:973–1011 | `\ltjsetparameter{postbreakpenalty=…}` / `{prebreakpenalty=…}` / `{jaxspmode=…}` | 禁則ペナルティ・和欧文間モードの設定 | LuaTeX-ja | 文字ノード | 文字クラステーブル＋penalty ノード生成へ変換（M4、PLAN.md §2.1 の表参照） |
| L17 | jlreq.cls:1270–1277 | `\ltjgetparameter{kanjiskip}` / `\ltjsetkanjiskip` / `\ltjsetxkanjiskip` / `\ltj@setpar@global` | フォントサイズ変更時の (x)kanjiskip 再設定 | LuaTeX-ja | JFM | サイズ変更フックで和文グルー規則を再計算（M4/M6） |
| L18 | jlreq.cls:6390–6403 | `\ltj@setpar@global` / `\ltjsetkanjiskip` / `\ltjsetxkanjiskip` | `\__jlreq_setkanjiskip:nn`（`\jidori`/`\akigumi` 用の一時的 (x)kanjiskip 設定） | LuaTeX-ja | JFM | `\jidori`/`\akigumi` は伸縮規則をローカル状態として自前管理（M4 以降、縦組み・割注で本格利用は M6） |

### 1.3 pTeX 系プリミティブ（非 `l` 分岐、**pdfTeX がそのまま踏む箇所**）

`\ifx l\jlreq@engine` の `else` 側に現れるプリミティブ。M1 の明示エラーを外した瞬間に pdfTeX が最初に踏むのは B1（`\epTeXinputencoding`）である。

| # | 位置 | シンボル/プリミティブ | 役割 | 提供エンジン | 分類 | pdfTeX での代替戦略 |
|---|---|---|---|---|---|---|
| B1 | jlreq.cls:523 | `\epTeXinputencoding utf8` | (u)pTeX での UTF-8 入力の確立（コメント 520–521 行「これ以前には和文は使えない」） | pTeX/upTeX (e-TeX 拡張) | エンコーディング | pdfTeX は当初から UTF-8 を扱わないバイト列処理。`CJKutf8` がバイト列を UTF-8 として解釈するため、この行は pdfTeX 分岐では不要（M2） |
| B2 | jlreq.cls:524 | `\zw`/`\zh` の定義（`zw`/`zh` というトークン） | pTeX の JFM 相対単位 | pTeX/upTeX/LuaTeX-ja | フォント | pdfTeX 用に `\jlreq@zw`/`\jlreq@zh` を実寸 dimen（JFM の zw/zh 値×和文フォントサイズ）として再定義（M2、G1） |
| B3 | jlreq.cls:532 | `\tate` / `\adjustbaseline` | 縦組モードの開始・和欧文ベースライン調整 | pTeX/upTeX（`\tate`）、pTeX 系（`\adjustbaseline`） | 組方向 | pdfTeX に縦方向は存在しない。M7（G4）まで `tate` オプションは明示エラーとする |
| B4 | jlreq.cls:586–587 | `\ifydir` / `\iftdir`（`\jlreq@ifydir` 等の定義内） | 組方向判定 | pTeX/upTeX | 組方向 | クラス側の組方向状態変数による判定に置換（M7、G4） |
| B5 | jlreq.cls:607 | `\postbreakpenalty`（読み出し） | 直前文字の改行後ペナルティ取得 | pTeX/upTeX | 文字ノード | 文字クラステーブルからの参照関数に置換（M3/M4） |
| B6 | jlreq.cls:644–648 | `\pdfpagewidth`/`\pdfpageheight`（寸法読み出し） | 残り行幅計算での用紙高さ参照 | pdfTeX 系（pTeX は DVI モードで 0pt 扱い） | PDFドライバ | pdfTeX では常に有効な値が返るためそのまま利用可（M2 以降） |
| B7 | jlreq.cls:675–690 | `\savepos` / `\lastxpos` / `\lastypos` | 現在位置の保存（`\jlreq@savepos@for@rest@linewidth` の DVI 側） | e-TeX (zref-savepos 由来) | PDFドライバ | pdfTeX は 678 行の `\pdfsavepos`/`\pdflastxpos`/`\pdflastypos` 分岐が使える。**エンジン非依存**に見えるが `zref-savepos` が DVI ドライバ前提のため、pdfTeX 分岐では 671 行の `\pdfsavepos` 判定が真になることを確認するだけでよい（M2） |
| B8 | jlreq.cls:701–711 | `\inhibitglue`（`\hbox` 内 4 回） | `\jlreq@calc@jfmglue`：2 文字間 JFM グルー実測用に自動挿入グルーを抑制 | pTeX/upTeX/LuaTeX(-ja) | 文字ノード | pdfTeX では自動グルー自体が存在しないので `\inhibitglue` 相当は no-op にできるが、グルー実測は生成 JFM データからの計算に置換（M3）。実測コード自体は M4 で文字クラス関数に置換 |
| B9 | jlreq.cls:755 | `\penalty`（`\jlreq@insertjfm` 内、`\jlreq@getpostbreakpenalty` の結果を発行） | JFM グルー挿入時の禁則ペナルティ発行 | TeX 共通 | 文字ノード | 動作は pdfTeX でも有効。ただし `\jlreq@getpostbreakpenalty` の情報源を B5 の代替に変更（M4） |
| B10 | jlreq.cls:764 | `\inhibitglue`（`\jlreq@insertjfm` が展開するグルー列の一部） | 挿入グルー後の自動グルー再抑制 | pTeX 系 | 文字ノード | 自前文字境界処理では状態リセットで代替（M4、G2） |
| B11 | jlreq.cls:796–797 | `\kanjiskip`/`\xkanjiskip`（代入） | 和文間・和欧文間グルーの設定 | pTeX/upTeX | JFM | 明示的 glue 挿入に置換（M4） |
| B12 | jlreq.cls:844–848 | `\ifx p` / `\ifx u` 分岐による JY1/JT1・JY2/JT2 エンコーディング選択 | 和文 NFSS エンコーディング名の決定 | pTeX/upTeX | フォント | pdfTeX では `bxcjkjatype` のフォントファミリ機構に載せ替え。`\DeclareFontShape` の対象エンコーディング自体を置換（M2） |
| B13 | jlreq.cls:860–867（`l` 側）/ 869–877（`else` 側） | `\DeclareFontShape`（`JY3`/`JT3` と `:jfm=…` 指定、または JY1/JT1・JY2/JT2 + TFM 名） | 和文ファミリ (mc/gt) の NFSS 定義。`else` 側は `\jlreq@jfmname`（prefix 付き jlreq TFM）を参照 | (u)pTeX（TFM+VF）/LuaTeX-ja | フォント | pdfTeX では CJK 系ファミリ定義と、生成した和文メトリック（`.def` のクラス幅データ）を用いた独自定義に全置換（M2/M3） |
| B14 | jlreq.cls:903–929 | `\ifx p\jlreq@engine\else …\fi`（文字クラスリストの差分） | pLaTeX (JIS) で使えない文字（`｟〘〖«〝`、`ゔ`、`ヷ` 等アウトオブJIS範囲）の除外制御 | pTeX の JIS エンコーディング制約 | エンコーディング | pdfTeX は Unicode 範囲を UTF-8 バイト列で扱うため、**p 以外の全文字リストを採用**（`else` 側のフルリスト）。文字クラス判定は M3 のコードポイント表へ |
| B15 | jlreq.cls:937（`l` 側 `\inhibitglue`）、946–965（`else` 側） | `\inhibitglue`、`\PushPostHook{par}`、`\everypar` | 行頭括弧調整（`\item` 直後・折り返し行頭の括弧位置、3.1.5） | pTeX 系 | 文字ノード | 行頭括弧フックは自前の `\everypar` 相当（`everypar` パッケージ or LaTeX フック）＋文字境界状態のリセットで再現（M4、G2） |
| B16 | jlreq.cls:1014–1015 | `\postbreakpenalty` / `\prebreakpenalty`（代入） | 禁則ペナルティ設定（`\__jlreq_set(post|pre)breakpenalty_aux:nn`） | pTeX/upTeX | 文字ノード | 文字クラステーブルの penalty エントリへの書き込みに置換（M4） |
| B17 | jlreq.cls:1017–1053 | `\inhibitxspcode`（読み書き、12 箇所） | 和欧文間グルー抑制モード（`\__jlreq_add/deljaxspmode_aux:nn`） | pTeX/upTeX | 文字ノード | xkanjiskip 相当の境界規則テーブル（和欧文間空きの on/off）を自前実装（M4） |
| B18 | jlreq.cls:1158–1164 | `\ttfamily` の和文ファミリ対応（`l` 側 jtt、`else` 側 gt） | 和文タイプライタ体ファミリの選択 | pTeX 系 NFSS | フォント | pdfTeX 側ファミリ表で `jtt` 相当を定義するか gt への ssub とする（M2） |
| B19 | jlreq.cls:1166–1173 | `\DeclareSymbolFont{mincho}` / `\DeclareSymbolFontAlphabet{\mathmc}` / `\jfam` / `\DeclareMathAlphabet{\mathgt}` | 数式内和文（jfam） | (u)pTeX | フォント | pdfTeX では数式用和文字体を `\Umath` 系ではなくテキスト字体のボックスで供給する設計が必要（M6、`disablejfam` との整合） |
| B20 | jlreq.cls:1187 | `\lastnodechar`（区切り約物判定の `\ifnum\lastnodechar=…` 構築） | 全角空白（`　`）の直前文字判定：区切り約物の後の全角空白の簡略化 | pTeX/upTeX/LuaTeX-ja | 文字ノード | 直前文字の自前追跡状態を参照（M4、G2） |
| B21 | jlreq.cls:1196–1202 | `\catcode`　`=\active`（`l` 側のみ） | 全角空白のアクティブ化（LuaTeX-ja が非アクティブ扱いのため） | — | 文字ノード | pdfTeX では全角空白出力を自前フックで管理するため、この分岐相当はバックエンド側で実装（M4） |
| B22 | jlreq.cls:1269–1285 | `\kanjiskip`/`\xkanjiskip`（フォントサイズフック内代入） | サイズ変更時の和文間グルー再設定 | pTeX/upTeX | JFM | サイズ変更フックで和文グルー規則を再計算（M4） |
| B23 | jlreq.cls:1333–1338 | `\setbox…\hbox{阿}`（`\mcfamily\selectfont\normalsize` の直後） | **load 時の和文メトリック測定**：`\Cht`/`\Cdp`/`\Cwd`/`\Cvs`/`\Chs` の確定 | — | フォント | **ゲート G1 の核心**。CJK 環境は通常文書開始時に有効になるため、ロード中に和文フォントで `\hbox{阿}` を測れるかを M2 で実証。詳細は §2 |
| B24 | jlreq.cls:1461–1466 | `\pagewidth`/`\pageheight`（`l` 側）と `\pdfpagewidth`/`\pdfpageheight`（`else` 側） | 用紙サイズの設定 | `else` 側は pdfTeX 互換プリミティブ | PDFドライバ | **pdfTeX では `\pdfpagewidth`/`\pdfpageheight` が使える**ため `else` 側を流用可。LuaTeX の `\pagewidth` との差に注意（M2） |
| B25 | jlreq.cls:1684–1689, 1749–1754 | `-1in`（`l` 側）と `-1truein`（`else` 側） | `\oddsidemargin`/`\evensidemargin`/`\topmargin` の原点補正。`truein` は `\mag` 補正後の実寸単位 | pTeX 系 DVI 出力の `\mag` 考慮 | PDFドライバ | pdfTeX は `\mag=1000` 固定（`\mag` 可変不可）なので `1truein`==`1in`。`else` 側の値をそのまま使用できる（M2）。ただし `\mag` 非対応ゆえ `mag` オプション使用時は非対応である旨を文書化 |
| B26 | jlreq.cls:2553 | `\inhibitglue\hbox{}`（`\jlreq@label@format@modified` 内） | 別行見出しラベル直後の自動グルー抑制 | pTeX 系 | 文字ノード | 見出しラベル後の状態リセットで代替（M6） |
| B27 | jlreq.cls:3067 | `\noexpand\inhibitglue`（見出しの `\everypar` 調整内） | `\@noskipsec` 時の目次出力直後のグルー抑制 | pTeX 系 | 文字ノード | 状態リセットで代替（M6） |
| B28 | jlreq.cls:3071–3073 | `\let\jlreq@hook@everypar\jlreq@openbracket@hook`（`else` 側） | 目次項目など特殊パラグラフの行頭括弧フック復帰 | — | 文字ノード | 自前パラグラーフックで代替（M6） |
| B29 | jlreq.cls:3435–3444 | `\lastnodechar` + `\inhibitglue`（`\jlreq@hook@prenote`、合印 interlinear 用） | 注記直前の文字判定によるグルー抑制。`l` 側と `else` 側で代入順序が異なる（3441 行のコメント「代入すると効かなくなる」は pTeX の `\inhibitglue` が展開タイミング依存であることへの回避） | pTeX/upTeX | 文字ノード | 直前文字の自前追跡に置換。この順序依存は pdfTeX では消滅する（M6） |
| B30 | jlreq.cls:3526–3529 | `\fnfixbottomtrue` / `stfloats`（`l` 側のみ） | LuaTeX-ja の脚注ボックス配置癖への対処 | LuaTeX-ja | フォント | pdfTeX では不要（標準 `\footins` 挙動）。ただし脚注の縦組み・二段組の配置検証は M6 で必要 |
| B31 | jlreq.cls:3722 | `\jlreq@ifydir` + `\jlreq@notemark` | 和文合印の形状切り替え（横/縦で上付き位置変更） | 判定は L6/B4 参照 | 組方向 | 組方向状態変数への置換（M6/M7） |
| B32 | jlreq.cls:3726–3728 | `\tatechuyoko*` + `\inhibitglue`（縦組時 `\thefootnote`） | 縦組の傍注番号（縦中横）出力 | pTeX 系 | 組方向 | 縦組みは M7（G4）までエラー。`else` 側（横組の `\thefootnote`、3728 行）は文字境界処理の完成後に利用可（M6） |
| B33 | jlreq.cls:3965–3969 | `\@makesidetext` の `l`/`else` 差分（`else` 側は全角空白 + `\kern-1\jlreq@zw`） | 傍注見出し直前の全角空白処理（pTeX では `\inhibitglue` が効かないための代替、3968 行コメント） | pTeX 系 | 文字ノード | 自前の境界処理では「直前文字との空き」を状態として持つため、この回避コードは不要になる（M6） |
| B34 | jlreq.cls:4054–4198（warichu/inlinenote 関連） | `\inhibitglue`（割注の括弧測定・出力、7 箇所：4054, 4058, 4113, 4160–4161, 4198, 4200） | 割注（`\warichu`/`\inlinenote`）の括弧幅測定・配置時の自動グルー抑制 | pTeX 系 | 文字ノード | 割注括弧の幅測定は自前メトリック（生成データ）から計算。出力時の境界状態は明示管理（M6）。G1 と同種の「測定に和文フォントが必要」箇所（4054–4058 行は load 時ではなく実行時） |
| B35 | jlreq.cls:5088–5092 | `\wd\@tempboxa=\headheight`（`l` 側）と `\ht…=\headheight\dp…=0pt`（`else` 側） | 縦組柱のボックス寸法制御（Underful 対策） | — | 組方向 | 縦組みは M7。横組時は `else` 側相当を使用 |
| B36 | jlreq.cls:5664–5670, 5724–5727 | `\PushPostHook{par}` + `\jlreq@openbracket@hook`（`else` 側、abstract 環境） | abstract 内パラグラフの行頭括弧フック | — | 文字ノード | 自前パラグラフフックで代替（M6） |
| B37 | jlreq.cls:6013 | `\inhibitglue・\inhibitglue`（`\@dottedtocline` のリーダー） | 目次リーダーの「・」周囲の自動グルー抑制 | pTeX 系 | 文字ノード | リーダー内の文字境界は固定コンテキストのため、明示的 kern 挿入に置換（M6） |
| B38 | jlreq.cls:6081 | `\tate`（theindex 環境の復帰） | 索引環境で一時的に横組にした後の縦組復帰 | pTeX 系 | 組方向 | M7（G4）。`theindex_yoko` 機能は complements 側（jlreq-complements.sty:159–198）にも同じ構造がある（M6） |
| B39 | jlreq.cls:6347–6352 | `\lastnodechar` + `\inhibitglue`（`\tatechuyoko` 前後、`\@tempa` 構築） | 縦中横直前の文字判定とグルー抑制（`l`/`else` で代入順序が逆） | pTeX/upTeX | 文字ノード | 直前文字追跡に置換。順序依存は消滅（M7） |
| B40 | jlreq.cls:6387–6457 | `\__jlreq_setkanjiskip:nn`（`else` 側は `\skip_set:Nn\kanjiskip` 等の代入） | `\jidori`（字取り）/`\akigumi`（空き組み）用の一時的和文グルー設定 | pTeX/upTeX | JFM | 字取り・空き組みは文字間グルー生成規則のパラメータ化で代替（M4/M6） |
| B41 | jlreq.cls:6456 | `\inhibitglue`（`else` 側 `\jidori` 本体） | 字取り内容の先頭自動グルー抑制 | pTeX 系 | 文字ノード | 状態リセットで代替（M6） |
| B42 | jlreq.cls:6499–6509 | `\kansuji`（`\today` の和暦/西暦縦組表記） | 数字の漢数字化 | pTeX/upTeX | フォント | 漢数字変換は TeX マクロで自前実装可能（`\kansuji` は変換規則のみ）。M2 で和文グリフ出力が成立すれば対応可 |
| B43 | jlreq.cls:1425 | `\kansuji`（`\jlreq@Kanji`、章番号等の漢数字） | カウンタの漢数字表記 | pTeX/upTeX | フォント | 同上（B42） |
| B44 | jlreq.cls:6831–6836 | `\RequirePackage[…]{jlreq-complements}` へのエンジン名渡し | complements へのエンジン通知 | — | エンコーディング | `d` の場合は `pdflatex` を渡す分岐の追加が必要（A5 とセット、M2） |

### 1.4 `jlreq-complements.sty` の依存箇所

| # | 位置 | シンボル/プリミティブ | 役割 | 提供エンジン | 分類 | pdfTeX での代替戦略 |
|---|---|---|---|---|---|---|
| C1 | jlreq-complements.sty:46–51 | `\__jlreq_complements_iftdir:`（`lualatex` 側は `\ltjgetparameter{direction}`、`else` 側は `\iftdir`） | theindex の縦横判定 | LuaTeX-ja / pTeX 系 | 組方向 | pdfTeX 分岐では横組前提の固定値（`\prg_return_false:`）を返す実装を追加（M6、PLAN.md §5 M6「非縦組み時の方向判定」） |
| C2 | jlreq-complements.sty:159–198 | `\yoko` / `\tate` / `\__jlreq_complements_iftdir:T`（theindex 開始 170 行・終了 198 行） | 索引の横組化・縦組復帰 | pTeX 系 | 組方向 | M7（G4）まで無効。横組時は B38 と同様に何もしない実装 |
| C3 | jlreq-complements.sty:248 | `\inhibitglue`（amsthm proof ラベルの後） | 証明ラベル直後の自動グルー抑制 | pTeX 系 | 文字ノード | 明示的 kern 挿入に置換（M6） |
| C4 | jlreq-complements.sty:54–57（`\jlreq@zw` 定義）、93, 154, 231, 238, 247 行（参照） | `\jlreq@zw`（jlreq クラス未ロード時に定義） | complements 単独使用時の全角幅 | クラス側の `\zw` 定義に依存 | フォント | pdfTeX 用 `\jlreq@zw`（実寸）参照に置換。クラスからロードされる場合は 55–57 行の `lualatex` 分岐に pdfTeX 用の値を追加（M2） |

### 1.5 `jlreq-trimmarks.sty` の依存箇所

| # | 位置 | シンボル/プリミティブ | 役割 | 提供エンジン | 分類 | pdfTeX での代替戦略 |
|---|---|---|---|---|---|---|
| D1 | jlreq-trimmarks.sty:7–9 | `\tombowdatetrue` の存在確認 | pLaTeX/upLaTeX/LuaTeX-ja 環境の検出（plcore 由来） | pTeX 系カーネル | PDFドライバ | pdfTeX ではこのエラーを pdfTeX 分岐で回避し、トンボ機構を shipout フックで自前実装（M6） |
| D2 | jlreq-trimmarks.sty:49–54 | `\let\jlreq@trimmarks@engine=\jlreq@engine` + `lualatex`/`uplatex`/`platex` オプション | トンボ計算のエンジン別調整値選択 | — | エンコーディング | `pdflatex` オプションと `d` 分岐の追加（A6 とセット、M6） |
| D3 | jlreq-trimmarks.sty:526–531 | `\pagewidth`/`\pageheight`（`l` 側）と `\pdfpagewidth`/`\pdfpageheight`（`else` 側） | トンボ付き用紙サイズの設定 | `else` 側は pdfTeX 互換 | PDFドライバ | pdfTeX は `else` 側（530–531 行）をそのまま使用可（B24 と同一構造、M6） |
| D4 | jlreq-trimmarks.sty:534–535 | `1in`（`l` 側）と `1truein`（`else` 側） | `\hoffset`/`\voffset` の原点補正 | pTeX 系 `\mag` 考慮 | PDFドライバ | pdfTeX は `\mag=1000` 固定のため `1truein`==`1in`。`else` 側を流用（B25 と同一構造、M6） |
| D5 | jlreq-trimmarks.sty:536–553 | `\@tombowreset@@paper` の差し替え（`1in`→`1truein`、546–547 行） | 新旧 pLaTeX のトンボ原点の違いへの追従 | pTeX 系カーネル内部構造 | PDFドライバ | pdfTeX では plcore のトンボ機構自体を使わないため、対応不要（M6） |
| D6 | jlreq-trimmarks.sty:558–561 | `\special{papersize=…}` + `\mag` によるスケーリング（`\jlreq@helper@divide{\the\mag pt}{1000pt}`、559 行） | DVI ドライバへの用紙サイズ通知 | DVI ドライバ（dvipdfmx 等） | PDFドライバ | pdfTeX では `\special` 経由の papersize 通知は不要（`\pdfpagewidth` が直接効く）。ドライバ分岐の追加（M6） |
| D7 | jlreq-trimmarks.sty:685–827（バナー出力部の `\ifx l\jlreq@trimmarks@engine` 分岐 18 箇所） | `\tate` + `\adjustbaseline`（バナー縦組用）、`l` と `else` でボックス寸法の取り方（`\ht` vs `\wd`）が異なる | トンボバナー（日付・用紙名）の縦組出力 | pTeX 系縦組 | 組方向 | 縦組バナーは M7 まで無効化。横組バナー（675–676 行の `\yoko\hss`）のみ対応。既定バナー（474–476 行、ジョブ名と日付）は和文を含みうるため M2 のフォント機構に依存（M6） |
| D8 | jlreq-trimmarks.sty:937–944 | `\jlreq@helper@divide{\the\mag pt}{1000pt}`（`l` 側は `1pt`、943 行） | pt→bp 換算（TrimBox 等の座標計算） | — | PDFドライバ | pdfTeX は `\mag=1000` 固定なので `1pt` を返す分岐を追加（M6） |
| D9 | jlreq-trimmarks.sty:998–1037 | `\pdfvariable pageattr`（998, 1016 行）/ `\special{pdf:~put~@thispage…}`（1003, 1023–1024 行、dvipdfmx）/ `\special{ps:SDict … pdfmark}`（1006, 1029 行、dvips） | TrimBox/BleedBox/ArtBox の PDF ページ属性出力 | LuaTeX / DVI ドライバ | PDFドライバ | pdfTeX では `\pdfpageattr` プリミティブで直接指定可。4 番目のドライバ分岐として実装（M6、PLAN.md §5 M6「pdfTeXのPDF出力経路を追加」） |

### 1.6 `jlreq-helpers.sty` の依存箇所

`jlreq-helpers.sty` は基本的にエンジン非依存（1 行目のコメント「エンジン非依存のマクロ集」）だが、エンジン検出（A1）と以下が関連する。

| # | 位置 | シンボル/プリミティブ | 役割 | 提供エンジン | 分類 | pdfTeX での代替戦略 |
|---|---|---|---|---|---|---|
| H1 | jlreq-helpers.sty:377–394 | `\jlreq@helper@guessengine` | エンジン自動判定 | — | エンコーディング | **M1 実装済み**（A1 参照） |
| H2 | jlreq-helpers.sty:382 | `\pdftexversion`（プリミティブ判定） | pdfTeX 判定。`\token_if_primitive:NTF` で `\meaning` 比較により判定（`\ifpdfprimitive` を避ける設計、367–376 行の `\jlreq@ifprimitive` とそのコメント） | pdfTeX | エンコーディング | pdfTeX 専用プリミティブであり pdfTeX のみが持つ（M1） |
| H3 | jlreq-helpers.sty:320–337 | `\jlreq@reference@label` / `\jlreq@reference@ref` / `\jlreq@setcurrentpage` | aux 経由の数値ラベル機構（`zref` 相当を自前実装） | エンジン非依存（TeX 共通） | PDFドライバ | pdfTeX でもそのまま動作。B7 の位置取得と組み合わせて利用（M6） |
| H4 | jlreq-helpers.sty:470–495 | `\jlreq@helper@divide` | `\loop` による寸法の整数除算（L11 の `else` 側、jlreq.cls:776 で `\jlreq@divide` に代入されて使用） | エンジン非依存 | JFM | pdfTeX でもそのまま動作（M2） |

## 2. load 時の和文メトリック測定箇所（ゲート G1）

PLAN.md §3.2「**重要な検証点**」：既存 `jlreq` はクラスロード中に `\hbox{阿}` 等を作って字幅・文字高さを測定するが、CJK 環境は通常文書開始時に有効になる。**ロード前後でフォント処理が実行できるか、実測値をどの時点で確定できるかが M2 の必達実証項目**（ゲート G1、PLAN.md §7）。該当する測定サイトは以下のとおり。

| # | 位置 | 測定内容 | 測定対象 | 実行時期 | pdfTeX での課題 |
|---|---|---|---|---|---|
| M1 | jlreq.cls:546 | `\jlreq@box@putcenter` 内の `\hbox{阿}`（高さ・深さの基準取得） | 和文 1 字の高さ/深さ | 実行時（割注・傍注の配置など随時） | 実行時であれば文書開始後であり CJK 環境有効。問題は 1333 行（load 時） |
| M2 | jlreq.cls:1331 | `\if@tate\tate\fi`（load 時の縦組モード発行） | 縦組パラメータの確定 | **load 時** | pdfTeX に `\tate` なし。縦組オプションは M7 までエラーにするため、この行は横組前提でスキップ可 |
| M3 | jlreq.cls:1332 | `\mcfamily\selectfont\normalsize`（load 時の和文フォント選択） | 和文明朝体のロード | **load 時** | **G1 の核心**。`\mcfamily` がクラスロード中に有効な和文フォントを選択できるか |
| M4 | jlreq.cls:1333–1338 | `\setbox\jlreq@tempboxa\hbox{阿}` → `\Cht`/`\Cdp`/`\Cwd`/`\Cvs`/`\Chs` | 和文 1 字の高さ・深さ・幅（全角寸法） | **load 時** | **G1 の核心**。CJK 環境未成立の状態で `\hbox{阿}` が正しい寸法を返すか。版面計算（1345 行以降の `\textwidth`/`\textheight` 決定）がこの値に直結するため、失敗すると**全レイアウトが崩れる** |
| M5 | jlreq.cls:2270 | `\jlreq@BlockHeading@start` 内の `\hbox{阿}`（行取り計算の基準） | 和文 1 字の寸法 | 見出し定義時（load 時に `\NewBlockHeading` が展開される場合を含む） | 行取り（何行分の空きか）の計算が load 時に走る。G1 と同根 |
| M6 | jlreq.cls:3431 | `reference_mark=interlinear` の `\hbox{阿}`（合印の天揃え計算） | 和文 1 字の高さ | `\jlreqsetup` 実行時（preamble 内） | preamble は文書開始前。G1 と同根 |
| M7 | jlreq.cls:4054, 4058 | `\jlreq@inlinenote@auto` 内の割注括弧 `\hbox{（}`（測定 2 回） | 割注括弧の幅 | 実行時（`\warichu`/`\inlinenote` 実行時） | 実行時であり CJK 有効。B34 参照 |
| M8 | jlreq.cls:6365 | `\jlreq@tatechuyoko@i` 内の `\hbox{阿}`（縦中横の高さ基準） | 和文 1 字の高さ/深さ | 実行時（縦組のみ） | 縦組みは M7 |
| M9 | jlreq.cls:6360, 6376 | `\jlreq@calc@jfmglue{…}{阿}`（縦中横前後の JFM グルー計算） | 阿と隣接文字間のグルー | 実行時（縦組のみ） | `\jlreq@calc@jfmglue` の pdfTeX 版（L10/B8 代替）が必要 |
| M10 | jlreq.cls:1428–1429 ほか、`\zh`/`\zw` を用いた版面パラメータ群（1428–1429 行の `\lineskip`、1524 行の `\topskip`、1558–1575 行の `\textwidth` 決定等） | 全角単位による版面設定 | **load 時** | `\zw`/`\zh` が load 時に正しい実寸を持つこと。B2 の代替実装が G1 の一部 |

**G1 対応方針**（PLAN.md §7）：M2 で「クラスロード中に CJK フォントで文字寸法を測定できるか」を最小 PoC で実証する。`bxcjkjatype` のロード時点と CJK 環境の自動設定を評価し（PLAN.md §5 M2）、解決不能ならメトリック初期化方式を変更（JFM 生成データから zw/zh を直接与える等）し、上流へ制約提示する。

## 3. カテゴリ別集計と PLAN.md 工程との対応

| カテゴリ | 箇所数（表番号） | 対応工程 | 主なゲート |
|---|---|---|---|
| エンコーディング | A1–A6, B1, B14, B44, D2（10） | M1 実装済み、残りは M2/M6 | — |
| フォント | B2, B3(一部), B12, B13, B18, B19, B23, B42, B43, C4, M3（11+） | M2（G1）, M3, M6 | **G1** |
| JFM | L1, L3–L5, L7, L10, L15–L18, B5, B8, B9, B11, B16, B22, B40（17） | M3, M4 | G2, G3 |
| 組方向 | B3, B4, L6, B31, B32, B35, B38, B39, C1, C2, D7（11） | M6（横組前提）, M7 | **G4** |
| 文字ノード | B9, B10, B15, B17, B20, B21, B26–B29, B33, B34, B37, B39, B41, C3（16） | M4（G2）, M5, M6 | **G2** |
| PDFドライバ | B6, B7, B24, B25, D1, D3–D6, D8, D9, H3（12） | M2, M6 | — |

## 4. 主要リスクと本監査との対応

PLAN.md §9 の主要リスクのうち、本監査で位置を特定したもの：

1. **CJK 初期化がクラスロード中の文字計測と衝突する（高）** → §2 の M2–M5（jlreq.cls:1332–1338, 2270, 3431）。G1 で早期実証。
2. **通常 LaTeX マクロの展開を跨ぐ文字境界を観測できない（最重要）** → B20（`\lastnodechar` 構築、jlreq.cls:1187）、B29（3435–3444）、B39（6347–6352）、L9（697）。pdfTeX には直前文字観測 API が存在しないため、`\lastnodechar` 相当の自前追跡が G2 の成否を分ける。
3. **行分割後のグルー調整を pdfTeX が公開していない（最重要）** → L3, L4（jlreq.cls:502–504 の `ltjenableadjust`/`stretch_priority`）。G3 で仕様の限界を確定。
4. **縦組みの複雑なグリフ・組方向制御（高）** → B3, B32, B35, B38, B39, C2, D7。M7 を独立ゲートに。
5. **`\mag` 依存の座標計算** → B25, D4, D6, D8。pdfTeX は `\mag=1000` 固定のため実質無害化されるが、`mag` オプションは非対応である旨の文書化が必要。

## 5. 補足：pdfTeX で「そのまま使える」プリミティブ

監査中に判明した、pdfTeX で即座に流用可能な箇所：

- `\pdfsavepos`/`\pdflastxpos`/`\pdflastypos`（jlreq.cls:671, 678–680）— 位置取得。B7 の DVI 側（`\savepos`）より pdfTeX 側が本来の使い方である。
- `\pdfpagewidth`/`\pdfpageheight`（jlreq.cls:1465–1466, jlreq-trimmarks.sty:530–531）— 用紙サイズ。`else` 側がそのまま pdfTeX 対応。
- `\pdftexversion`（jlreq-helpers.sty:380）— M1 のエンジン判定。
- `\jlreq@reference@*`（jlreq-helpers.sty:320–337）— aux 経由の数値ラベル機構。エンジン非依存。

ただし pTeX の `\mag` 可変運用（`\mag` オプション使用時の `truein` 補正、jlreq.cls:1687, 1753、jlreq-trimmarks.sty:534–535）は pdfTeX では成立しない。pdfTeX の `\mag` は 1000 固定であり、可変 `\mag` を前提とした文書はサポート対象外と明記する必要がある。

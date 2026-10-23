# G4/M7 評価: pdfTeX バックエンドの縦組み(tate)可否判定

## 結論(verdict)

**縦組みは構造的に実装不可能 (structurally blocked)。** エンジンの方向プリミティブ不在に加え、「縦組みグリフの供給源」「縦組み JFM の解釈系」「jlreq の用紙モデルとの整合」の 3 層すべてに代替手段が存在しない。クラスが `pdflatex,tate` を明示エラーにする現行ゲート(jlreq.cls:524、`tests/run-pdftex-tests.sh` T2 で回帰監視)を**維持するのが正しい**。

以下、調達試行 → フォールバック(CJKvert)での実証 → 構造的理由、の順に記す。

## 1. bxcjkvert 等の調達試行(全て失敗)

| 手段 | 結果 |
|---|---|
| `kpsewhich bxcjkvert.sty` | 空 (TeX Live 2025 nix store 内に存在しない) |
| `tlmgr install bxcjkvert` | nix store が read-only で拒否 (`.../tlpkg/ is not writable`) |
| `tlmgr init-usertree` + `tlmgr --usermode install bxcjkvert` | Local 2025 vs remote 2026 のクロスリリース更新拒否 |
| `curl https://mirrors.ctan.org/install/macros/latex/contrib/bxcjkvert.tds.zip` | HTTP 404 (TDS zip 非存在) |
| `https://ctan.org/pkg/bxcjkvert`, `.../tex-archive/macros/latex/contrib/bxcjkvert` | 両方 HTTP 404 — **CTAN にこのパッケージは存在しない** |
| GitHub API `search/repositories?q=bxcjkvert` | `total_count: 0` — GitHub にも存在しない |
| `zr-tex8r/{BXcjkvert,bxcjkvert,BXvert,BXtategaki}` 直打ち | 全て 404 |

**bxcjkvert は CTAN/GitHub のどこにも存在しない名前**である (設計書の記憶違いと思われる)。代替候補の調査結果:

- **bxcjkjatype (バックエンドが使用中)**: 縦組み機能は**抹消済み**。`vertical` オプション指定で `\PackageError{bxcjkjatype}{Option 'vertical' is abolished}` (bxcjkjatype.sty:139-142)。パッケージ内部に CJKvert 用の `\CJKsymbol` パッチ経路 (bxcjkjatype.sty:799-854) は残るが、これは太字処理の差し替えであり縦組み機能そのものではない。
- **CJK (基底レイヤ)**: 縦組みっぽい機能は **`CJKvert.sty`** (Werner Lemberg, v4.8.5 2021/10/16) のみ。TeX Live 2025 に収録 (`/tex/latex/cjk/texinput/CJKvert.sty`)。以降これをフォールバックとして M7 評価を行う。

## 2. CJKvert による実証 PoC(poc/ 配下、すべて現行バックエンド上で検証)

CJKvert の仕組み (CJKvert.sty 実読): `\CJKvert` で `\ifCJK@vertical@` を立て、`\CJKsymbol` を再定義して**各グリフを `\rotatebox{90}`(graphicx)で回転**する。組方向プリミティブは使わず、TeX の行組は横のまま。「縦書き」は各物理行(=段)を 90° 自転させたグリフ列として出し、**閲覧側でページを 90° 回転させて読む**方式である。縦グリフ別字形は要求しない (フォントの `.fdx` カスタマイズ `…/offset/v`, `…/fullheight/v`, `…/norotate/v` はデフォルト 0pt/未設定)。

PoC ファイル (すべて `pdflatex -interaction=nonstopmode -halt-on-error` で **rc=0**):

### M7-1 縦組みフォント代替 — poc/v1-tate-fonts.tex

- `V1-FONT-ENC: C70` / `V1-FONT-FAMILY: ipxm` / `V1-FONT-CURRENT: lmr/m/n`
  → 縦でも横と同じ ipaex Type1 (C70/ipxm) が供給される。**縦組み用フォント・縦グリフへの代替はどこにも発生しない。**
- TeX Live 2025 内に CJK 系の縦組みフォント定義 (`*.fdx` / `*vert*`) は **存在しない** (`find texmfdist/tex/latex/cjk -iname "*vert*" -o -iname "*.fdx"` → CJKvert.sty 自身のみ)。C70/ipxm 用の v メトリクスは未定義のまま全てデフォルト (offset/v=0pt) に落ちる。

### M7-2 行方向・段方向挙動 — poc/v1-tate-fonts.tex (\pdfsavepos で実測)

- 同一行内グリフ位置: posA(あの前)=(3640547,33256505)sp → posB(あの後)=(4295906,...) → posC=(4951265,...)。**各グリフ +655359sp ≒ +10.0pt = +1zw が +x 方向 (物理 LTR)**、y 座標変化なし。
- 段 (物理行) は **上から下へ積まれる** (物理的な下方進行)。CJKvert はページを立てたまま閲覧者が 90° 時計回りに回して読むモデルなので、閲覧面では段が右→左に進む — が、**直立ページ上で右→左に段を積む jlreq の縦組み用紙モデル (監査書 B3-B5, B35) とは根本的に非整合**。
- 段送りピッチ: CJKvert は `\baselinestretch` を強制 1.3 にし `\normalfont` を発行 (CJKvert.sty `\CJKvert` 本体)。実測:
  - バックエンドのみ (CJKvert なし): `\baselineskip=17.0pt` (stretch 既定=空)
  - CJKvert あり (VERT 状態): `V1-BASELINESTRETCH-AFTER-VERT: 1.3` / `V1-BASELINESKIP: 22.10005pt`
  → クラスが版面設計時に確定した行数・行送り (jlreq.cls:1333以降の `\Cvs` 系計算) と出荷時ピッチが機械的にずれる。\textheight=435.0001pt / \textwidth=310.0001pt (a5) は横組み形状のまま不変。

### M7-3 約物の回転 — poc/v1-tate-punct.tex / v1-tate-compare.tex / v1-tate-ink.tex

- 回転は**幾何学的に発生する**ことをノードレベルで確認: `\hbox{あ}` (縦モード) の `\showbox` 内容に `\pdfsave` → `\pdfsetmatrix{0 1 -1 0}` (90° CCW 回転行列) → グリフ → `\pdfrestore` が出現する (poc 側では `showbox.tex` プローブで確認)。
- しかし字形は横組み用のもの**そのまま** (M7-1 の通り代替なし):
  - `、。` (yoko では字字枠の左下): 全セル 1zw の物理ボックス (実測 box=9.99998pt×(8.40005+1.59995)pt、あいう等と同一)。回転にともなう原点オフセット (C70/ipxm の `/offset/v` 相当) は一切定義されず、縦組みが要求する「セル右上寄せの縦用約物字形 + ベースライン移動」(JLREQ 4.2.2、JIS X 4051 の縦組み約物配置) には到達しない。**コーナー位置の保証が構造上取れない**。
  - `「」` などの括弧類: 縦組みでは「別字形(縦用バリアント)に置き換える」のが組版規則 (Unicode の縦組み字形置換 / pTeX の JFM 縦用フォント)。Type1 IPAex に縦用グリフは存在せず回転は 90° 一律のため、括弧の**開き向きが規則通りにならない**。
  - カギ括弧・句読点のぶら下げ・二分詰め: pdfTeX バックエンドの H1/クラス幅機構は横軸に沿って kern を出す規則 (jlreq-pdftex-rules.sty:344-377)。回転グリフに対して物理横軸のアキ加工は**読み面では段間方向にずれる**だけで、縦組みの約物詰めの意味を持たない。
- 約物まわりのペア glue / 禁則ペナルティ (jlreq-pdftex-jfm.def 由来) は**横組み JFM データの値**を物理横軸に挿入し続ける。縦組み JFM (jlreq では `jfm-v` 系: 監査書 L5、フォント定義 664-674 行) の解釈系はバックエンドに存在しない。

### M7-4 縦横混在 — poc/v1-tate-mix.tex

- 文中の `\CJKhorz`↔`\CJKvert` 切り替えは rc=0 で通る。が、M7-2 の通り `\normalfont`+stretch 変更が混入し、行の物理ピッチが段落途中で変わる。jlreq の版面グリッド (行取り・行間計算) を破壊するため、実用上の「混在」として成立しない。

### M7-5 縦中横相当機能

- **存在しない。** CJKvert.sty に縦中横相当の命令は皆無 (grep `tatechu` 0 件)。
- jlreq.cls 側: `\jlreq@iftdir` は d 分岐で恒偽 (`jlreq.cls:657`)。`\tatechuyoko`(jlreq.cls:6589-6595)はスターなしで `ClassError{... not allowed in yoko mode}`、スター付きは `#2` をそのまま横のまま出すパススルー。**縦中横の本実装 (回転しない領域を段内に作る) は CJKvert の方式論では与えられない** (縦中横は「縦組み方向での長方形配置」が前提であり、方向プリミティブ抜きの回転絵付けでは隣接関係を作れない)。

### M7-6 ページスタイル/脚注の sanity — poc/v1-tate-mix.tex

- コンパイル rc=0 で通るが、柱・ノンブル・脚注は**直立ページ上の物理横要素のまま**。読み面に合わせてページを 90° 回転 (`\pdfpageattr{/Rotate 90}` 等) すると今度は柱と脚注が横向きになる。jlreq の縦組みでは柱配置は縦組み仕様 (B35: 柱のボックス寸法制御)、脚注は**傍注へ変換**される (監査書 B32、jlreq.cls:3726-3728) — どちらも方向プリミティブ前提であり CJKvert 方式では再現不能。

## 3. 構造的ブロッカー(互換表用に整理)

1. **方向プリミティブ不在**: pdfTeX に `\tate`/`\yoko`/`\iftdir`/`\ifmdfdir` は存在しない (監査書 §0 基本前提)。`\jlreq@iftdir` は d 分岐で恒偽直打ち (jlreq.cls:657)、組方向追跡のステート変数化 (L6/B4 の代替) すら存在しない。
2. **縦組みグリフの供給源がない**: bxcjkvert 不実在 (CTAN 404/GitHub 0 件)、bxcjkjatype 縦組みオプション抹消 (PackageError)、CJKvert は横フォントの幾何回転のみ (TeX Live 内に縦用 `.fdx` 0 件)。Type1 IPAex に縦グリフは存在しない。
3. **縦組み JFM の解釈系がない**: バックエンドのペア glue/禁則/ぶら下げは全て横組み JFM (jlreq-pdftex-jfm.def) を物理横軸に適用する固定設計。`jfm-v` 相当のデータ解釈と縦軸適用は不可能 (glue/kern の向きが物理軸に縛られる)。
4. **用紙モデルの非整合**: jlreq 縦組みは直立長辺縦の用紙に右→左の段組み。CJKvert は横向きグリフの直立ページであり、読み面でのみ 90° 回転 — ページ属性/基本版面 (\textheight/\textwidth の意味、柱・脚注の向き) が全ページで食い違う。/Rotate 強制も走り見出しを破壊する。
5. **縦中横・割注・傍注の縦組み変種が実装不能**: いずれも「縦組み領域での配置」が前提 (監査書 B32/B34/M8/M9) で、回転絵付けモデルには載らない。

**互換表記入案**: tate — `structurally blocked (方向プリミティブ不在 + 縦組みグリフ/JFM/用紙モデル全層。)。bxcjkvert 実在せず(調達不能)、bxcjkjatype の vertical は廃止済 PackageError、CJKvert は横フォント幾何回転で縦組み規格要件を満たさない。現行の tate オプション明示エラーを維持。`

## 証跡ファイル

- `poc/v1-tate-fonts.tex` (M7-1/M7-2: フォント・位置・ピッチ実測)
- `poc/v1-tate-punct.tex` (M7-3: 約物ボックス実測)
- `poc/v1-tate-mix.tex` (M7-4/M7-5/M7-6)
- `poc/v1-tate-compare.tex`, `poc/v1-tate-ink.tex` (M7-3: savepos+ラスタ比較)
- 全 PoC: `pdflatex -interaction=nonstopmode -halt-on-error` rc=0 (\showbox プローブのみ意図的停止で rc=1)
- 調達試行ログ: 本文 §1 表

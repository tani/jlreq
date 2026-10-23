# G4/M7 評価: pdfTeX バックエンドの縦組み(tate)可否判定

## 結論(verdict, 2026-10-23 再調査版)

**jlreq の `tate` を動かす方向での実装は依然として構造的にブロックされている。**
bxcjkvert (実在・取得済み) は生 CJKvert の副作用 2 点 (baselinestretch 強制変更・フォントリセット) を**正確に解消する**有用な薄層であり、回転レイヤとして検証した限りの動作は正しい。しかしパッケージの設計上の提供範囲は「グリフ回転 + 方向切替の副作用除去」までで、JLREQ の縦組みが要求する層 (縦用紙モデル・版面・約物の縦用配置・縦組み JFM・縦中横・方向感応のページ家具) には**仕様としても到達しない**(マニュアル自身がその意図を持たない)。

研究用 PoC として「回転ベースの疑似縦組み」を動かすことは可能 (後述のロード時互換問題の回避込みで rc=0)。ただしこれは jlreq の `tate` ではない。

## 1. bxcjkvert の調達(初回報告の誤りを訂正)

初回調査 (本ファイル旧版) では「bxcjkvert は CTAN/GitHub のどこにも存在しない」と判定したが、**それは誤り**。

| 調査 | 結果 |
|---|---|
| `kpsewhich bxcjkvert.sty` (TL2025 nix store) | 空 — TeX Live 2025 には未収録 (2026-03-31 公開のため) |
| `tlmgr install bxcjkvert` | nix store read-only + local2025/remote2026 クロスリリース拒否 (両方失敗) |
| CTAN 個別 pkg ページ `ctan.org/pkg/bxcjkvert` | 404 — **単独パッケージとしては登録されていない** (初回はこれを存在なしと誤読) |
| CTAN ディレクトリ直接 `mirrors.ctan.org/install/...bxcjkvert.tds.zip` | 404 (TDS zip なし) |
| **本当の所在**: CTAN `language/japanese/BX/bxcjkjatype/` ディレクトリ配下 | **同梱されている** (zr-tex8r 氏作、MIT、`v0.5a [2026/03/31]`)。manual: bxcjkvert.pdf、ソース: bxcjkvert.tex |
| GitHub search `bxcjkvert` | 0 件 (個別リポジトリなし; 作者: https://github.com/zr-tex8r) |

取得物 (Main 経由で入手・検証済み): `/tmp/bxcjkvert/{bxcjkvert.sty,bxcjkvert.tex,bxcjkvert.pdf}`。
PoC 用ローカル設置 (コミット禁止のインテグレータ指示準拠): `texlive/tex/latex/bxcjkvert/bxcjkvert.sty` に配置し、`TEXINPUTS="texlive//:" pdflatex` で解決。**texlive/ ディレクトリ自体はコミットしないこと。**

## 2. マニュアル能力抜粋 (bxcjkvert.tex 全読)

bxcjkvert.sty v0.5a は CJKvert (v4.8.5) を内部で `\RequirePackage` する薄層で、提供は正確に以下の 3 オプションのみ:

| オプション | 既定 | 効果 |
|---|---|---|
| `resetfont` | `false` | 既定で `\CJKvert`/`\CJKhorz` が `\normalfont` を発行しなくなる (CJKvert は発行する) |
| `usebaselinestretch` | `retain` | 既定で `\baselinestretch` を一切触らなくなる (CJKvert は縦時に ×1.3 強制) |
| `main` | `retain` | 文書開始時の方向を強制しない (CJKvert は縦開始固定) |

マニュアル abstract 引用: *"a tailored version of the CJKvert package, accommodated for Japanese typesetting, where MIXTURE of horizontal and vertical writings is common."* — **MIXTURE = 文書内での横/縦ブロック混在**の意味であり、縦中横・約物配置・縦用 JFM・ページ回転などの仕組みは**コマンドとしても hook としても存在しない**。制限の明示: なし (単に言及がない)。実装詳細: CJKvert の `\CJKvert` の自動起動を `\@begindocumenthook` から剥がし `\AfterEndPreamble` で `\bxjt@main` だけ実行するパッチ (bxcjkvert.sty:103-108)。

## 2.5 ロード時互換問題 (TeX Live 2025 で再現)

`\@begindocumenthook` は現行 LaTeX2e (TL2025) では **`undefined`** (計測: `HOOK-LEGACY: undefined`; CJKvert の `\AtBeginDocument` は新 hook システムに入り従来変数に残らない)。このため bxcjkvert.sty:104 のパッチ `\expandafter\bxjt@tmpa\@begindocumenthook\relax\bxjt@tmpa` が区切りマッチに失敗し、**素のロードで File-ended-while-scanning エラーになる**。

回避 (PoC で採用・検証済み): ロード前に従来変数へ種を入れる。

```tex
\makeatletter\def\@begindocumenthook{\CJKvert}\makeatother
\usepackage{bxcjkvert}   % パッチが `\CJKvert` を空回収して通る
```

(右上のものをそのままにしても自動縦開始は起きず、方向は作者が命令で決める — `main=retain` 既定の意図通り)。恒久対応は上流課題 (zr-tex8r 氏に報告する価値がある)。

## 3. PoC (poc/v3-*.tex; plain article + bxcjkjatype + bxcjkvert、jlreq 不使用)

いずれも repo ルートから `TEXINPUTS="texlive//:" pdflatex -interaction=nonstopmode -halt-on-error`。

### v3-basic.tex (縦組み本文・複数段落・副作用計測) — rc=0

- `V3-BLSTRETCH-BEFORE/AFTER: ` 両方空 (=1)：**baselinestretch 変更ゼロ** (生 CJKvert は 1.3 強制で实测されていた: 旧版 §M7-2 の 22.1pt 記録)。bxcjkvert の修正が実働。
- `V3-FONT-AFTER: cmr/m/n, 10pt`：**フォント保持** (`\normalfont` reset なし)。
- グリフ進行: `vposB→vposC = +655359sp = +10.0pt` 物理 LTR、y 不変 → 回転済みグリフが 1zw ピッチで物理横進行し、物理行 (=段) は下に積む。CJKvert 方式 (閲覧時にページを時計回り 90° 回転) のまま。**組方向プリミティブは一切登場しない**。
- 複数段落フロー: 2 段落縦組みで rc=0。行送りは文書既定値のまま (baselinestretch=1)。

### v3-punct.tex (約物コーナー実測 + リーディング枠変換) — rc=0

シート上の実測 (`\pdfsavepos` + 300dpi ラスタ解析):

```
、(セル内) sheet xrel=0.14..0.31  y_above_baseline=+3.18..+5.11pt
。          sheet xrel=0.10..0.29  y_above_baseline=+2.46..+4.63pt
「          sheet xrel=0.72..0.96  y_above_baseline=-3.08..+6.31pt
```

閲覧枠 (=シートを CW 90° 回転) への写像 `rel_y(reading) = 1 − sheet_xrel`、`rel_x(reading) ≈ (baseline 上の高さ)/1zw` で評価:

- **、**: 閲覧枠で **rel_y ≈ 0.69..0.86 (セル下部)・rel_x ≈ 左寄り** → **下左エリアに置かれる**。
- 真の縦組みでの正規位置 (JLREQ 4.2.2、JIS X 4051): **上右**である。upLaTeX 基準 (`poc/ref-tate-uplatex.tex`、ujarticle[tate]、36dpi 解析) でも「、」はセル上 3 分の 1 (`yrel=0.00..0.33`) に来る実測を得た。
- **よって幾何回転では 、。は対角で正反対のコーナーに落ちる** (横組み字形の左下配置が回転で下左に出るため)。縦用グリフ別字形の代替は (Type1 ipaex にも bxcjkvert にも) 供給されない。
- 「」の上下方向は (シート相対位置で) 概ね整合するが、字形は横組みのものを幾何回転したものであり、縦組み字形 (縦用バリアント) ではない。

### v3-mixture.tex (混在・縦中横候補・数式) — rc=0

- `\CJKhorz` を縦領域内に挟むと、**シート上では欧文が直立・横進行で入る** (実測: mixA→mixB→mixC = あ(+10.0pt)→ab(+10.55pt)→い)。しかし閲覧枠ではこの欧文は**文字が横向きに倒れて**見える (シートは読み面に対し CCW 90° されているため直立シート文字は読み面で 90° 回転する)。**縦中横 (読み面で直立の横書き挿入) ではない**。縦中横等価機能は CJKvert/bxcjkvert のいずれにも存在しない。
- 数式 `\(...\)` の接続: rc=0 で通るが、数式はシート上物理水平のまま (閲覧枠で倒れる)。
- 方向切替え自体は副作用なく往復する (`V3-DIR-AFTER-VERT: v`→`h`、約定通り)。

### 旧 PoC (poc/v1-*.tex; jlreq バックエンド + 生 CJKvert)

バックエンド共存下の参照証跡として残す。生 CJKvert でも rotation whatsit (`\pdfsetmatrix{0 1 -1 0}`) は発火する (v1-tate-showbox.tex) が、baselinestretch=1.3 強制・フォント reset などは旧版記録通り。bxcjkvert はこの 2 点を解消する。

## 4. jlreq `tate` への接続可否 — ブロッカー表

| # | ブロッカー | 判定 |
|---|---|---|
| 1 | bxcjkvert の存在・入手 | **gone** (bxcjkjatype CTAN dir 同梱; リリース配布では vendoring か上流 TL 取り込み待ちが必要) |
| 2 | TL2025 でのロード失敗 (@begindocumenthook 非互換) | **workaroundable** (種入れ回避 実証済み; 恒久的には上流修正案件) |
| 3 | CJKvert の副作用 (baselinestretch 強制・font reset) | **gone** (bxcjkvert 既定で解消、計測済み) |
| 4 | 方向プリミティブ (`\tate`/`\iftdir`) | **structural**: 引き続き存在しない。レイアウト判断は横固定状態のまま |
| 5 | 用紙モデル (jlreq の縦組み = 直立縦長用紙・左右域交換・版面計算) | **structural**: CJKvert 系は「直立用紙の物理横版面に倒れたグリフを並べ、閲覧回転する」モデル。jlreq の版面計算 (行送り・字詰め・柱・柱位置) と軸が整合しない。`/Rotate` 強制は柱・ノンブルを横倒しにする |
| 6 | 縦組み JFM (開閉括弧の縦用組法・(x)kanjiskip 相当の縦軸適用) | **structural**: バックエンドの表は横組み JFM (jlreq-pdftex-jfm*.def) のみ。縦用は別データ + 縦軸挿入器が必要 |
| 7 | 約物コーナー配置 (、。上右) | **structural**: 幾何回転では下左に落ちる (§3 实测)。救うには「縦用フォント/オフセット表」相当が必要で現状 Type1 供給なし |
| 8 | 縦中横 | **structural**: CJKhorz 混在は閲覧枠で横向きに倒れる挿入であり、読み面直立の縦中横ではない (§3 实测) |
| 9 | ページ家具 (柱・ノンブル・脚注→傍注転換 4.2.6・見出しの改丁) | **structural**: すべて方向感応の仕組みが未整備。回転絵付けでは整合しない |
| 10 | ぶら下げ・禁則軸 | **structural**: バックエンドのぶら下げ kern は物理横軸。縦組みでは段側への半角空けで軸が違う |

**判読**: jlreq クラスとしての `tate` (JLREQ 準拠の本実装) は引き続き **structurally blocked**。bxcjkvert は「回転レイヤを正しい副作用で供給する」点までは有用だが、JLREQ の縦組み仕様が要求する残りの層は、パッケージの設計範囲外の構造的事項である。

## 5. スケジュール可否の最終判定

**jlreq の `tate` を本仕様で pdfTeX に載せるスライスは依然として正当化されない。** 版面と用紙、約物字形と配置、縦用 JFM、家具、縦中横の全層で別実装が要求され、回転近似は JLREQ 準拠の検証 (4.2.2 の約物位置含む) を構造的に落とす。続けるなら低い目標に限定した別枠 (例: 「CJKvert 互換の縦組み近似を出す最小クラス」) であり、jlreq ブランドの tate としては出せない。

現行の `pdflatex,tate` 明示エラーゲート (jlreq.cls:524、runner T2) は正しい状態であり維持する。

## 証跡ファイル一覧

- `poc/v3-basic.tex` — 副作用計測・複数段落 (rc=0)
- `poc/v3-punct.tex` — 約物コーナー实测 (rc=0)
- `poc/v3-mixture.tex` — 混在・縦中横候補・数式 (rc=0)
- `poc/ref-tate-uplatex.tex` — upLaTeX 真の縦組み基準 (uplatex + dvipdfmx, rc=0)
- `poc/v1-*.tex` — jlreq バックエンド + 生 CJKvert の参照証跡 (旧版)
- ローカル設置: `texlive/tex/latex/bxcjkvert/bxcjkvert.sty` (コミット外、調達は §1)

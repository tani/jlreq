# pdfTeXバックエンド 依存関係・ライセンス・動作環境

## ライセンス構成（PLAN.md §5 M0「GPLコードをBSD-2ソースへ流用しない」の記録）

| 成分 | ライセンス | 本プロジェクトでの扱い |
|---|---|---|
| jlreq 本体（jlreq.cls 他） | 2-clause BSD | 変更対象。バックエンドコードはこれに従う |
| jlreq-pdftex.sty / jlreq-pdftex-rules.sty（新規） | 2-clause BSD（jlreq本体と同一） | 独自実装。依存パッケージのコードは含まない |
| make_pdftex_jfm.lua / check_jfm_pdftex.lua（新規） | 2-clause BSD | 既存luajfm2pl.luaのロード方式（kpse+dofile）のみ参照し，コード流用なし |
| bxcjkjatype | MIT | **依存**（`\RequirePackage` のみ。コード流用なし） |
| CJK / CJKutf8 / CJKspace | GPL-2.0 | **依存**（実行時にロードされるだけ。jlreq成果物へのGPL伝播は「依存関係」として区別し，コード流用は一切ない） |
| expl3 / LaTeX2e カーネル | LPPL | 依存 |
| IPAex Type 1 フォント（ipaex-type1） | IPA Font License | 依存（フォント資産） |

方针: BSD-2のjlreq本体に，GPLパッケージ（CJK系）を「依存」として使う
（他のTeXパッケージがGPLパッケージを依存に持つのと同じ形）。バックエンド
実装はCJKの内部マクロを参照するが（`\CJKsymbol` 内部・`\CJK@ignorespaces`
へのフック），それらは実行時のインターフェース利用でありコード複製ではない。
上流レビューでこの境界を明示する。

## 動作環境（検証実績）

| 項目 | 値 |
|---|---|
| TeX Live | 2025（nixpkgs環境, pdfTeX 3.141592653-2.6-1.40.27, kpathsea 6.4.1） |
| エンジン | pdflatex / platex / uplatex / lualatex（同一環境で回帰検証） |
| 必須パッケージ | bxcjkjatype >= 2023/07/23 v0.5，CJK（CJKutf8），lmodern（jlreq既存依存） |
| フォント | ipaex-type1（TeX Live標準収録） |
| ビルドツール | texlua（JFM生成のみ。実行時は不要） |

**最低TeX Live版**: 上流との協議事項（PLAN.md M8「版は上流と決定」）。
技術要件は `\DeclareKeys`/`\ProcessKeyOptions`（LaTeX2e 2020-10以降），
`\AddToHook{...}`（2020-06以降），`expl3`の`\sys_if_engine_pdftex:TF`。
検証実績は TeX Live 2025 のみ。**実装はフック・鍵処理をこの世代に固定する**。

## バージョン確認コマンド

```sh
kpsewhich -var-value=version        # kpathsea
pdflatex --version | head -1        # pdfTeX
kpsewhich bxcjkjatype.sty           # 依存の所在確認
kpsewhich ipxm-r-u30.pfb            # フォント資産確認
```

## フォント（P4: 縦字形・フォントプロファイル）

縦組みの実際の縦字形（vert/vrt2 GSUB）は補助縦フォントとして配布する
（PLAN §10.1 P4）。実行時とビルド時の依存は分離：

### 実行時（文書コンパイル; python/fontTools/ttf2tfm 不要）
- `fonts/pdftex/jlreq-pdftex-fonts-ipaex.def` / `-ipa.def`
  （フォントプロファイル。インストール先は `tex/latex/jlreq`）
- `fonts/pdftex/jlreqv-<fontset>-<mc|gt>-<NN>.ttf` / `.tfm` / `.enc`
  （補助縦フォント。インストール先は
  `fonts/truetype/jlreq-pdftex`, `fonts/tfm/jlreq-pdftex`,
  `fonts/enc/jlreq-pdftex`）
- クラスオプション `pdftex_fontset=ipa|custom` 利用時の横書きTTF経路:
  **zhmetrics** の動的TFM（`unisong@Unicode@` 等）と **`Unicode.sfd`**
  （`kpsewhich Unicode.sfd`）。欠損時は当該リソース名を添えて停止する。

### ビルド時（`make pdftex-fonts` / custom 生成; 通常の文書では実行しない）
- **python3 + fontTools**（cmap/GSUB vert・vrt2/hmtx/vmtx/VORG/輪郭bbox読取）
- **ttf2tfm**（TL2025検証済みの起動形式:
  `ttf2tfm <ttf> -N -u -p <enc> <outbase>`。この版のパーサは
  オプションを位置引数の後ろに置かないと「Need at most two non-option
  arguments」で失敗する——生成器のヘッダに実測値を文書化済み）
- ソースTTF: ipaex の `ipaexm.ttf`/`ipaexg.ttf`（既定）、
  ipa の `ipam.ttf`/`ipag.ttf`、custom は `--mincho/--gothic` のTTF

### 依存確認コマンド（P4）

```sh
kpsewhich ipaexm.ttf                    # ipaex-type1 の縦字形ソース
kpsewhich ipam.ttf                      # ipa プリセットTTF
kpsewhich Unicode.sfd                   # zhmetrics SFD（ipa プリセット横書き）
kpsewhich unisong30.tfm                 # zhmetrics 動的TFM確認
ls fonts/pdftex/jlreq-pdftex-fonts-ipaex.def   # プロファイル（repo）
ttf2tfm --version                       # 補助TFM生成器（ビルド時のみ）
python3 -c "import fontTools"           # ビルド時のみ
```

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

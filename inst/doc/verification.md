# 検証 / Verification

この版は、R 4.5.3 以上で使える可搬性のある source を対象とします。実際の native 検証は、Linux x86-64 の R 4.5.3 と R 4.6.1 で行っています。R 4.6.1 は、2026-10-04 に R の公式 release page で現行 stable と確認した版です。Windows、macOS、その他の architecture、32 bit R、4.5.3 未満の R、開発版 R は検証済みとは主張しません。

ローカルの interpreter は公式の CRAN Debian binary package です。この作業用の分離したディレクトリへインストールし、CRAN の SHA256 package metadata と照合しています。変更したのは launcher/configuration のパスだけで、system 全体へのインストールはしていません。検証記録には正確な出所と hash を添えています。CI は、固定した R の公式 source と、hash を検査した test tools を使います。

必要な検証:

1. native base R による単体検査。segments、Unicode/raw data、GF256/RS、全 160 version/ECC の組合せと 1,280 個の明示 mask の行列、optimizer の厳密性、GS1、PNG checksum、資源上限による拒否を対象にします。
2. 変更していない 10,186 件の言語非依存 corpus。公開 API の 5,610 件と内部の 4,576 件を含みます。全 mask、raw codeword の構築、255 RS 次数、65,536 GF 積、高水準の計画・符号化、Structured Append を対象にします。
3. 独立した ZXing-C++ と ZXing Java による実 PNG の decode、metadata と payload の検査、SVG の raster 化、RGBA の完全一致の比較。
4. FNC1 の literal percent/連続 GS、Digital Link の dot 値/厳格な authority、動的な ECC key、有限な印刷 geometry に関する共有回帰検査。
5. R CMD build/check、インストール済み library の consumer、source を直接使う consumer、examples、空白・制御 byte と Unicode path を扱うバイナリデータを保持する CLI。
6. 最終 source manifest、source が不変の検証記録、独立レビュー、正確な commit に対する公開後の CI。

R の character 値は NUL を表せないため、JSON-line の開発用 adapter は、NUL を含む JSON payload text を等価な UTF-8 raw bytes に対応付けます。該当する参照 case は全 8 件を残し、期待する bytes/codewords/matrices を変えずに比較します。これは adapter の境界での処理であり、R の文字列に NUL を含められるという主張ではありません。アプリケーションでは `raw` を明示的に使ってください。

参照 corpus と hash は `verification/fixtures/manifest.json` で固定しています。失敗・中断した試行は、後の修正済み実行とは別に保持します。部分的な実行、生成ファイルの存在、異なる source revision から成功を推定することはありません。開発用の decoder と rasterizer は、package の runtime 依存ではありません。この検証 workflow は、CRAN への提出、tag、release を作成しません。

`R CMD build --no-build-vignettes .` を実行し、続いて `R CMD check --no-manual --no-build-vignettes specqr_0.1.0.tar.gz` を実行します。no-manual option を明示して TeX への依存を避けますが、Rd 文書と examples は引き続き検査します。hosted CI は別の検証であり、同等のローカルテストに合格しただけで、CI にも合格したと報告することはできません。

## Request-bound GS1 URL compatibility

`python3 scripts/verify_gs1.py --rscript /path/to/Rscript --output /tmp/gs1` は、元の全 1,411 requests、現行 TypeScript による独立した全 80 正例、全 49 共有 operations、113 authority controls を実行します。fixture hash、request ごとの hash、正確な型付き契約、source hash、process status、stderr、件数の検査は必須です。`scripts/test_verify_gs1.py` は、異常時に拒否する harness の対照検査 10 件を実行します。既存の hosted R の両方の検証構成で、これらの検査を必須としています。
変更していない過去の corpus と TS/Nim の出所は、`verification/fixtures` と `verification/gs1` にあります。

元の render/GS1 単体 assertion 444 件は有効なまま維持し、厳密な credential 復号の拒否 4 件を追加して、合計 448 件にしています。従来の無害な host、空の delimiter/port、backslash に対する拒否は、現在は正確な肯定 assertion になっています。`verification/gs1/native-assertion-migrations.json` は元の入力との対応を記録しています。
全 102 FNC1 percent vectors、48 件の共有 PNG decode、28 件の data-preservation operations、21 件の legacy authority operations は引き続き必須です。既存の QR、CLI、offline package、独立した matrix/codeword、decoder の検査は変えていません。

## Additional URL serialization evidence

独立した 139 正例の拡張では、resolver-prefix の builder 入力を含め、path の raw caret を `%5E` として直列化することも検査します。caret の escape は URL の直列化の修正であり、復号後の GS1 payload bytes は変わりません。

元の 1,411 入力の対象外では、従来からの base-path 整理が重複した区切りをまとめます（`/a//b` は `/a/b` になります）。この動作は browser の URL 直列化と異なります。ASCII reg-name 対応は、ACE（`xn--`）label を完全には検証しません。ここで受理する名前の一部を、UTS46 対応の parser は拒否します。これは IDNA 検証が不完全であることを明示した契約であり、その名前が有効、または安全なリンク先であるという証拠ではありません。
部分的な IDNA decoder や新たなネットワーク依存は導入していません。

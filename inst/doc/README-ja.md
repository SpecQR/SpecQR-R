# SpecQR R

QR Code Model 2 をフルスクラッチで実装した、実行時の追加パッケージ依存がない R パッケージです。QR の符号化、誤り訂正、配置、マスク選択、SVG / PNG 出力をすべて R で処理します。外部 QR ライブラリ、C / C++ 拡張、FFI、Web API は使用しません。

## 対応範囲

- バージョン 1–40、誤り訂正 L / M / Q / H、全 8 マスク
- 数字・英数字・バイト・漢字モード、混在セグメントの最適化
- ECI、FNC1 第 1 / 第 2 位置、GS1、Structured Append
- 符号化前の容量見積もり、診断、コントラストと印刷寸法
- SVG、RGBA ピクセル、PNG、データ URL、コマンドライン
- R 4.5.3 以上。検証対象は Linux x86-64 の R 4.5.3 / 4.6.1

Windows、macOS、その他のアーキテクチャは現時点で実機検証済みとはしていません。ソースは可搬性を意図した標準 R のみで構成しています。詳しくは [検証方針](verification.md) を参照してください。インストール後のガイドは `system.file("doc", package = "specqr")` にあります。CRAN には公開していません。

## インストール

ソースを取得したディレクトリで実行します。R パッケージ名は小文字の `specqr` です。

```sh
R CMD build --no-build-vignettes SpecQR-R
R CMD INSTALL specqr_0.1.0.tar.gz
```

Git リポジトリのルートにいる場合は `R CMD INSTALL .` でもインストールできます。追加の R パッケージやネットワーク接続は不要です。

## 最初の QR

```r
library(specqr)
qr <- generate("こんにちは、SpecQR!", eci = TRUE)
print(qr)
writeLines(to_svg(qr), "hello.svg", useBytes = TRUE)
writeBin(to_png(qr), "hello.png")
```

ECI は自動挿入しません。`eci = TRUE` は UTF-8 の ECI 26 を指定します。受信機との互換性は用途に合わせて確認してください。漢字モードは同梱の固定 Shift_JIS 対応表を使用し、OS の文字変換に依存しません。

## 容量と診断

```r
p <- plan("12345678901234567890", version = 1, error_correction_level = "M")
p$ok
p$data_bit_length
p$remaining_bits
get_capacity(1, "M", mode = "byte")
qr <- generate("HELLO", margin = 4, scale = 8, print_dpi = 300)
diagnostics(qr)
```

`plan()` / `estimate()` は容量を計算し、行列や Reed–Solomon 符号を生成しません。収まらない場合は `ok = FALSE` を返します。`generate()` は容量不足を `specqr_data_too_long` として報告します。

## R の文字列とバイト

文字入力は、欠損値でない長さ 1 の Unicode 文字列です。ベクトル、因子、データフレーム、`NA` は暗黙変換しません。複数件は明示的に `lapply()` で処理してください。

```r
symbols <- lapply(c("one", "two"), generate)
binary <- generate(as.raw(c(0, 29, 127, 128, 255)))
```

R の文字列には NUL を格納できません。NUL や任意のバイナリは `raw` を使用してください。文字列の UTF-8 バイト列、結合文字、改行、空白を正規化・トリミングしません。整数ベクトルを暗黙にバイトへ変換しません。

## セグメントと制御ヘッダー

```r
qr <- generate_segments(list(
  eci(26),
  numeric_segment("1234567890"),
  byte_segment("hello"),
  kanji_segment("漢字")
))
```

`segment()` と専用コンストラクターが利用できます。手動セグメントではモードと制御ヘッダーの配置を検証します。FNC1、ECI、Structured Append の同時使用には対応しません。

高水準の `fnc1 = TRUE` は入力中の `%` とグループ区切り文字 U+001D をそのまま保持します。低水準の FNC1 + 英数字セグメントでは QR 規格の `%` / `%%` エスケープを呼び出し側が指定します。両者の意味は異なります。

## GS1 と Digital Link

```r
elements <- list(GS1Element("01", "09506000134352"), GS1Element("10", "LOT-7"))
payload <- create_gs1_element_string(elements)
qr <- generate(payload, gs1 = TRUE)
url <- create_gs1_digital_link(elements, base_url = "https://id.gs1.org")
parse_gs1_digital_link(url)
```

対応 AI は `get_supported_gs1_ais()` で確認できます。GS1 全 AI の網羅や、GS1 認証済み製品であることは意味しません。Digital Link は [厳格な ASCII authority プロファイル](gs1.md) を実装し、ネットワークにはアクセスしません。

## Structured Append

```r
set <- generate_structured_append(paste(rep("A", 80), collapse = ""), version = 1)
length(set$symbols)
parts <- lapply(set$symbols, function(q) list(
  index = q$segments[[1]]$index, total = set$total, parity = set$parity,
  data = do.call(c, lapply(q$segments[-1], function(s) s$logical_bytes))
))
merged <- merge_structured_append_parts(rev(parts))
merged$data
```

上の例では生成時のセグメントから結合用データを作っています。実運用ではデコーダーから得た各ペイロードと index / total / parity を渡してください。

2–16 シンボルを生成し、元の UTF-8 / raw バイトに対するパリティを使用します。文字入力は Unicode スカラー境界で分割します。受信機が Structured Append に対応している必要があります。

## CLI

リポジトリのルートから実行します。

```sh
Rscript --vanilla exec/specqr.R --text "HELLO" --format svg --output hello.svg
Rscript --vanilla exec/specqr.R --input payload.bin --format png --output payload.png
Rscript --vanilla exec/specqr.R --stdin --format png --output payload.png < payload.bin
Rscript --vanilla exec/specqr.R --text "12345" --plan
Rscript --vanilla exec/specqr.R --help
```

ファイルと標準入力は raw バイトとして読み、末尾の改行や NUL を除去しません。バイナリの標準入出力は Unix のデバイス経由で処理し、Linux で検証しています。その他の OS では `--input` / `--output` のファイル指定を利用してください。テキストのモード最適化が必要な場合は `--text` を使用します。インストール済み CLI の場所は `system.file("exec", "specqr.R", package = "specqr")` で取得できます。

## 検証と制限

[API](api.md) / [描画](rendering.md) / [GS1](gs1.md) / [検証](verification.md) を参照してください。基本テストは R の標準機能だけで実行します。開発用の独立デコーダー検証では Python、ZXing-C++、ZXing Java、SVG ラスタライザーを使用しますが、利用時の依存関係には含めません。

MIT ライセンス。仕様表・参照コーパス・検証ツールの出所は [NOTICE](NOTICE) に記載しています。

# GS1 and Digital Link

SpecQR は、50 種に限定した AI カタログ、チェックディジット、element string、オフラインの Digital Link adapter を実装しています。GS1 General Specifications 全体を検証するものではありません。日付は固定の 6 桁表現を検査し、実在する暦日かどうかは検査しません。用途固有の AI 間の関連付けや、現在の GS1 辞書全体は、このカタログの対象外です。

```r
library(specqr)
items <- parse_gs1_human_readable("(01)09506000134352(10)LOT%1(17)251231")
raw <- create_gs1_element_string(items)
link <- create_gs1_digital_link(items, base_url="https://id.gs1.org")
parsed <- parse_gs1_digital_link(link)
checked <- validate_gs1_digital_link(link)
```

要素は、list に含めた `GS1Element(ai,value)` または `list(ai="10",value="LOT")` オブジェクトです。両方の field は scalar 文字列である必要があります。AI/value の入力は数値へ変換しないため、先頭のゼロは失われません。data frame は拒否します。必要に応じて各行を明示的に要素の list へ変換してください。

## Catalog and validation

`get_supported_gs1_ais()` は、次の AI の metadata を返します。

* `00`, `01`, `02`, `10`, `11`, `12`, `13`, `15`, `16`, `17`, `20`, `21`, `22`
* `30`, `37`, `240`, `241`, `400`, `410`–`415`, `420`, `422`, `424`–`426`
* 個別の `3100`–`3105`、`3200`–`3205`、`91`–`99`

`get_gs1_ai_info(ai)` は、1 件の情報または `NULL` を返します。metadata には、固定長または可変長、数値または text の種別、チェックディジットの規則、区切りの規則、Digital Link での役割、primary key にできるかどうかを含みます。汎用 GS1、GTIN、SSCC のチェックディジット用ヘルパーは、modulo-10 digit の計算、適用できる場合の付加、検証を行います。
AI `01`/`02` は GTIN、`00` は SSCC のチェックディジットを検証します。この限定した profile では、AI `414` は 13 桁の primary key です。追加の GLN チェックディジット規則への対応は主張しません。

`parse_gs1_human_readable`、`parse_gs1_element_string`、`create_gs1_element_string` は、括弧付き表現と raw 表現を変換します。
`normalize_gs1_elements` は、どちらの入力表現も、要素オブジェクトも受け付けます。`gs1_to_human_readable` は括弧付き表現を生成します。

値は printable ASCII を使い、括弧と ASCII GS を含めないでください。文字としての percent 記号は、その文字のまま保持します。可変長 field には、後続の要素がある場合だけ ASCII GS を付けます。予期しない区切り、重複した区切り、末尾の区切りは失敗します。最後の可変長の値が、固定長の AI/value を連結したように見える並びで終わる場合は、区切りの欠落による曖昧さとして拒否します。これは、末尾だけを対象とする保守的で限定的な heuristic です。

`validate_gs1_elements` と `validate_gs1_element_string` は、構造化した list の結果を返します。`collect_all_errors=FALSE` は、要素の検証エラーを最初の失敗に限定します。`context="digital-link"` は、対応する primary AI を要求します。未対応の AI を `allow_unsupported_ai` で有効にすることはできません。
独自の iterator protocol には対応していません。

## Digital Link profile

`create_gs1_digital_link`、`parse_gs1_digital_link`、`validate_gs1_digital_link`、`normalize_gs1_digital_link` は、URL を取得しません。
厳密な payload の復号を行う、範囲を限定した HTTP(S) URL adapter を使います。WHATWG URL や IDNA/UTS46 に完全準拠するものではありません。

* HTTP(S) の slash 表記と authority/path の backslash を補正します。両端の ASCII C0/space を除去し、TAB/LF/CR を削除します。query の backslash はデータとして保持します。
* 空でない fragment は拒否します。空の `#` は受理し、生成時には保持し、正規化時には削除します。builder の空の `?` は置き換え、空でない query は拒否します。
* ASCII reg-name host は小文字にします。browser の URL 解析が受理する無害な句読記号や空の DNS label も対象です。ASCII の percent-encoded host は厳密に復号し、符号化された authority の区切りと空の host は拒否します。
* 数値 IPv4 は、短縮、八進、十六進、整数の別表記を受理します。累積計算と各 component の正確な範囲を検査し、正規の dotted-decimal 表現を出力します。
  `0x`、`0X`、`1.0x`、`0x.`、`1.0X`、`1.2.3.0x` は有効な別表記です。
  `example.0x`、不正な数値候補、overflow は拒否します。
* 括弧付き RFC IPv6 は、有効な dotted-decimal の末尾を含め、小文字の十六進 group と、最初に現れる最長のゼロの連続を使います。zone identifier は拒否します。
* credentials は escape し、URL text として保持します。取得や認証は行いません。診断に追加の credential data をそのまま出力することはありません。
* 空の port は省略します。十進 port は 0–65535 の範囲を検査し、先頭のゼロを許可し、HTTP/HTTPS の既定 port を省略します。
* host、credentials、path、query の percent escape と復号後の UTF-8 は、引き続き厳密に検査します。不正な UTF-8 と復号後の NUL は拒否します。R の文字列には NUL を含められません。
* Unicode/IDNA の hostname 変換は、この base R のみの adapter の対象外です。部分的な UTS46 や IDNA の実装は主張しません。アプリケーションが IDNA の方針を独立に解決したうえで、ASCII hostname を渡すことはできます。

adapter は、DNS の存在、到達性、URL の信頼性、SSRF に対する安全性を検証しません。解析ではネットワーク通信を行いません。

primary AI は `00`、`01`（builder の既定）、`414` です。qualifier の `10`、`21`、`22` を path に置けるのは、`01` の後だけです。その他の対応 AI は query data です。
Digital Link 内で AI を重複させることはできません。`path_ais=character()` は、すべての qualifier を query に保持します。dot だけの qualifier 値 `.` と `..` は、path 用に選択しても常に query に保持します。primary AI より後の実際の path dot segment は、AI/value の組を解釈する前に拒否します。percent-encoded dot もその位置では拒否します。文字列としての値 `%2e` は `%252e` と符号化して保持します。

builder は resolver-prefix の dot segment を正規化した後、残った prefix component のうち、1 回の復号で primary AI になるものを拒否します。`%30%31` も対象です。これにより、生成したリンクの payload の開始位置が曖昧になることを防ぎます。先行する dot 正規化で削除された、primary AI のように見える component は許可します。その他の prefix component は既存の escape を保持します。raw UTF-8 と path の文字は、復号後の値を変えずに percent encode します。

query の復号は form の意味論（`+` は空白）を使い、percent/UTF-8 を厳密に検証します。`unknown_query="preserve"` は、非 GS1 key、重複、順序、空の値、復号後の空白を保持します。`"reject"` はそれらを拒否します。数値の AI の形をした key には、引き続きカタログの対応が必要です。
正規化は `"specqr-deterministic"` mode を使い、対象となる qualifier を path に置き、GS1 query attribute を AI/value の辞書順に並べ、unknown query の組を元の順序で末尾に追加します。dot だけの query qualifier は query に残します。受理された正規化後の出力に対しては冪等です。

検証は、HTTP と保持した unknown query に関する警告を報告します。検証の `normalize=TRUE` option は未対応です。正規化用の関数を明示的に呼び出してください。
失敗時には `specqr_invalid_gs1` を投げます。安定した `error_code(error) == "INVALID_GS1"` と、より細かな `detail_code` を持ちます。検証の issue は、その詳細 code、message、reason、適用可能な context field を公開します。

## Bounds

text は有効な UTF-8 で、最大 1,000,000 UTF-16 code units です。その前に 4,000,000 bytes の上限も検査します。要素 list の AI/value 全体の処理量は 1,000,000 bytes に制限します。有効な AI/value の text は ASCII です。要素と query の組は最大 16,384 件、path component は最大 32,769 個です。上限のない反復、数値の解析、出力の大幅な増加の前に上限を検査します。

## URL 互換性の回復

従来の狭い URL 受理範囲を見直し、TypeScript の固定ソース
`16efc6c0a8e397c9df3d051d20fce6c1eebdfad7` が受理する 77 件と、IPv6 の
正規化 3 件を回復しました。通常の QR の符号化・行列・描画・FNC1 の意味や
実行時依存関係は変更していません。無害な URL 表記の受理範囲を広げる変更です。

元の 1,411 入力は変更せず、現在の TypeScript を実行して得た型付き期待値と
照合します。R で残る 168 差分は診断 132、不正 percent/UTF-8/NUL 20、
Unicode/IDNA host 12、raw Digital Link primary 検査 2、安全な dot query
生成 2 です。診断 5 件の順序変更は固定した旧 Nim による意味的 witness で
独立に確認しています。これらをすべて同じ「不正 URL」とは扱いません。

検証は 80 正例、既存 49 authority/Digital Link 操作、追加 113 authority
対照例と process の失敗・余分な出力・stderr・型不一致を明示的に検査します。
期待値を候補実装の出力から作っていません。

## Additional URL serialization evidence

独立した 139 正例の拡張では、resolver-prefix の builder 入力を含め、path の raw caret を `%5E` として直列化することも検査します。caret の escape は URL の直列化の修正であり、復号後の GS1 payload bytes は変わりません。

元の 1,411 入力の対象外では、従来からの base-path 整理が重複した区切りをまとめます（`/a//b` は `/a/b` になります）。この動作は browser の URL 直列化と異なります。ASCII reg-name 対応は、ACE（`xn--`）label を完全には検証しません。ここで受理する名前の一部を、UTS46 対応の parser は拒否します。これは IDNA 検証が不完全であることを明示した契約であり、その名前が有効、または安全なリンク先であるという証拠ではありません。
部分的な IDNA decoder や新たなネットワーク依存は導入していません。

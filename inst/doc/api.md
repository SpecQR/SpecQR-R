# R API

公開関数は snake_case を使い、クラスを持つリストを結果として返します。未知のオプションや重複したオプションはエラーになります。引数を暗黙にリサイクルせず、数値のフラグには有限のスカラー整数が必要です。論理値は数値オプションとして扱いません。文字列のペイロードには有効な Unicode 文字列 1 個が必要で、バイナリのペイロードは `raw` でなければなりません。因子、配列、データフレーム、欠損値、クラスを持つ数値オブジェクト、任意の整数ベクトルは拒否します。テキストのベクトルには `lapply(texts, generate)` を明示的に使ってください。

`specqr_options(...)` は検証済みのオプションを構築します。`generate(value, options = NULL, ...)` は character、raw、または `specqr_segment` オブジェクトのリストを受け付けます。`generate_segments(segments, ...)` は手動セグメントを明示的に選択します。オプションは `error_correction_level="M"`、`version=NULL`、`min_version=1`、`max_version=40`、`mask_pattern=NULL`、`mode="auto"`、`optimize_segments=TRUE`、`allow_kanji=TRUE`、`boost_error_correction=FALSE`、`eci=NULL`、`gs1=FALSE`、`fnc1=FALSE`、`fnc1_second=NULL`、`structured_append=NULL`、`margin=4`、`scale=8`、`foreground="#000000"`、`background="#ffffff"`、`print_dpi=NULL` です。

`version` はバージョンを固定します。指定しなければ、許可された最小のバージョンを選択します。ECC の強化は、そのバージョンに収まる場合に限って訂正強度を上げます。`eci=TRUE` は割当番号 26 を意味し、`FALSE`/`NULL` は ECI を使わないことを意味します。ECI/FNC1/SA の組み合わせは拒否します。Structured Append ヘッダーは 1 始まりの `index` と `total`、0–255 のパリティを使います。

`segment(mode,data=NULL,...)` は numeric/alphanumeric/byte/kanji と、制御モードの eci/fnc1/fnc1-second/structured-append に対応します。補助関数は `numeric_segment`、`alphanumeric_segment`、`byte_segment`、`kanji_segment`、`eci`、`fnc1`、`fnc1_second`、`structured_append_segment` です。コンストラクターは入力を所有し、検証します。クラスを持つリストを書き換えても、不正なフィールドが信頼されるようにはなりません。公開エンコード API の境界で再検証します。

`optimize_segments(text,version=1,allow_kanji=TRUE)` はデータセグメントのビットコストを最小化し、同点の場合も決定的に選択します。`plan`/`estimate` と `plan_segments`/`analyze_segments` は算術計算のみで容量を選択します。計画には `ok`、`version`、`capacity_version`、`data_bit_length`、`capacity_bits`、`remaining_bits`、segments、diagnostics を含みます。失敗した計画ではバージョンを選択しませんが、容量を確認したバージョンは保持します。`get_capacity(version,level,mode=NULL,control_bits=0)` は容量を報告します。

結果には `$matrix`（論理値、行/列）、`$size`、`$version`、`$mask_pattern`、`$error_correction_level`、`$data_codewords` と `$codewords`（raw）、`$segments`、`$diagnostics`、`$options` を含みます。`module_at(q,x,y)` は 1 始まりの R 座標を使い、x は列、y は行を表します。行列へ直接アクセスする場合は `[row,column]` を使います。

エラーは `specqr_error`、`error`、`condition` を継承します。個別のクラスは `specqr_invalid_input`、`specqr_invalid_version`、`specqr_invalid_mode`、`specqr_invalid_eci`、`specqr_invalid_gs1`、`specqr_invalid_color`、`specqr_invalid_output`、`specqr_invalid_ecc_level`、`specqr_data_too_long` です。`$code` は大文字の安定したコードで、`$detail_code` は任意の GS1 詳細情報を保持します。`tryCatch(..., specqr_error=function(e) error_code(e))` を使ってください。人が読むエラー文字列の全文には依存しないでください。

コストの高い処理の前にリソース上限を適用します。ペイロードは 100 万単位、手動セグメントは 16,384 個、SA シンボルは最大 16 個とし、単一シンボルの容量上限、寸法の上限、ラスターの上限も適用します。計画によって上限を超えるペイロードをエンコード可能にはできません。単一シンボルの生成は空の character/raw ペイロードに対応します。Structured Append には空でない複数シンボルの入力が必要です。

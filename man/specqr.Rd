\name{specqr}
\alias{specqr}
\alias{specqr-package}
\alias{error_code}
\alias{specqr_options}
\alias{segment}
\alias{numeric_segment}
\alias{alphanumeric_segment}
\alias{byte_segment}
\alias{kanji_segment}
\alias{eci}
\alias{fnc1}
\alias{fnc1_first}
\alias{fnc1_second}
\alias{structured_append_segment}
\alias{can_encode_kanji}
\alias{bit_length}
\alias{segment_bit_length}
\alias{segments_bit_length}
\alias{normalize_segments}
\alias{optimize_segments}
\alias{create_segments}
\alias{get_capacity}
\alias{estimate}
\alias{plan}
\alias{analyze_segments}
\alias{plan_segments}
\alias{generate}
\alias{generate_segments}
\alias{diagnostics}
\alias{module_at}
\alias{render_dimensions}
\alias{to_svg}
\alias{to_pixels}
\alias{render_rgba}
\alias{to_png}
\alias{parse_color}
\alias{contrast_ratio}
\alias{to_svg_data_url}
\alias{to_png_data_url}
\alias{to_data_url}
\alias{render}
\alias{GS1Element}
\alias{GS1_FNC1_SEPARATOR}
\alias{calculate_gs1_check_digit}
\alias{validate_gs1_check_digit}
\alias{calculate_gtin_check_digit}
\alias{append_gtin_check_digit}
\alias{validate_gtin_check_digit}
\alias{calculate_sscc_check_digit}
\alias{append_sscc_check_digit}
\alias{validate_sscc_check_digit}
\alias{get_supported_gs1_ais}
\alias{get_gs1_ai_info}
\alias{parse_gs1_human_readable}
\alias{parse_gs1_element_string}
\alias{create_gs1_element_string}
\alias{gs1_to_human_readable}
\alias{normalize_gs1_elements}
\alias{gs1_element_string_to_human_readable}
\alias{validate_gs1_elements}
\alias{validate_gs1_element_string}
\alias{create_gs1_digital_link}
\alias{parse_gs1_digital_link}
\alias{validate_gs1_digital_link}
\alias{normalize_gs1_digital_link}
\alias{gs1_normalize}
\alias{gs1_from_human_readable}
\alias{gs1_to_element_string}
\alias{gs1_build}
\alias{gs1_parse}
\alias{gs1_digital_link}
\alias{gs1_to_digital_link}
\alias{calculate_structured_append_parity}
\alias{calculate_structured_append_segments_parity}
\alias{generate_structured_append}
\alias{generate_segments_structured_append}
\alias{merge_structured_append_parts}
\alias{specqr_cli}
\docType{package}
\title{Dependency-Free QR Code Model 2 Encoding in R}
\description{QR Code Model 2 versions 1 through 40, all four correction levels and eight masks, segment optimization, GS1 helpers, Structured Append and image rendering. All runtime algorithms use base R.}
\usage{
generate(value, options = NULL, ...)
generate_segments(segments, options = NULL, ...)
specqr_options(...)
plan(value, options = NULL, ...)
estimate(value, options = NULL, ...)
get_capacity(version, error_correction_level = "M", mode = NULL,
             control_bits = 0, ...)
optimize_segments(text, version = 1, allow_kanji = TRUE, ...)
to_svg(x, margin = NULL, scale = NULL, foreground = NULL, background = NULL)
to_png(x, ...)
to_data_url(x, format = "png", ...)
parse_color(color, strict = FALSE)
generate_structured_append(input, options = NULL, ...)
merge_structured_append_parts(parts, ...)
}
\arguments{
  \item{value, input}{Unicode の文字列スカラー 1 個、raw ベクトル、または明示的に対応しているセグメントのリストです。NUL は raw バイト列でのみ使用できます。}
  \item{segments}{検証済みのセグメントオブジェクト、または明示的なセグメントのマッピングのリストです。}
  \item{options}{\code{specqr_options} オブジェクトです。\code{NULL} を指定すると既定値を使います。}
  \item{...}{以下で説明する、名前付きのエンコードまたは描画オプションです。未知の名前と重複した名前は拒否します。}
  \item{version}{QR のバージョンで、1 から 40 までの整数です。}
  \item{error_correction_level}{\code{"L"}、\code{"M"}、\code{"Q"}、\code{"H"} のいずれかです。}
  \item{mode}{対応するデータモードのいずれかです。一般的な容量には \code{NULL} を指定します。}
  \item{control_bits}{制御用に確保するビット数で、負でない正確な整数です。}
  \item{text}{最適化する Unicode 文字列 1 個です。欠損値は使えません。}
  \item{allow_kanji}{最適化で固定の QR Kanji マッピングを使えるかどうかを指定します。}
  \item{x}{描画する QR の結果、または正方形の論理モジュール行列です。}
  \item{margin, scale}{クワイエットゾーンのモジュール数と、1 モジュールあたりのピクセル数です。\code{NULL} は保存されたオプションか既定値を使います。}
  \item{foreground, background}{対応する色の文字列です。\code{NULL} は保存されたオプションか既定値を使います。}
  \item{format}{出力形式です。データ URL では \code{"png"} または \code{"svg"} を指定します。}
  \item{color}{16 進数の RGB/RGBA、または単純な ASCII の CSS 色名です。}
  \item{strict}{\code{TRUE} の場合、未対応のラスター色はエラーになります。それ以外の場合、認識できない安全な名前には \code{NULL} を返します。}
  \item{parts}{正確なフィールド \code{index}、\code{total}、\code{parity}、\code{data} を含む、復号済みのマッピングです。添字は 1 始まりです。}
}
\details{
\code{generate(value, ...)} は、文字列スカラー、raw バイト列、またはセグメントのリストに使います。再利用するオプションには \code{specqr_options(...)} を使います。オプションには \code{error_correction_level}、\code{version}、\code{min_version}、\code{max_version}、\code{mask_pattern}、\code{mode}、\code{optimize_segments}、\code{allow_kanji}、\code{boost_error_correction}、\code{eci}、\code{gs1}、\code{fnc1}、\code{fnc1_second}、\code{structured_append}、\code{margin}、\code{scale}、\code{foreground}、\code{background}、\code{print_dpi} があります。既定ではバージョンとマスクを自動で選択し、訂正レベル M、余白 4、スケール 8 を使います。未知のオプションや重複したオプションはエラーになります。

\code{plan} と \code{estimate} は算術計算による容量計画を返し、\code{generate} は \code{specqr_result} を返します。\code{generate_segments}、\code{plan_segments}、\code{analyze_segments} は手動で指定したセグメントを受け付けます。\code{segment(mode, data=NULL, ...)} は検証済みのセグメントを作成します。補助関数は numeric、alphanumeric、byte、kanji、ECI、FNC1、Structured Append のセグメントを構築します。ECI、FNC1、Structured Append の制御は組み合わせられません。

\code{to_svg} は文字列を返し、\code{to_png} は raw の PNG バイト列を返します。\code{to_pixels} は行優先の RGBA バイト列と寸法を返します。データ URL の補助関数は文字列を返します。描画には外部の画像パッケージやグラフィックスデバイスを使いません。\code{render_dimensions} は明示的な \code{dpi} に対応します。\code{module_at(result,x,y)} は 1 始まりの列・行の座標を使います。

\code{GS1Element(ai,value)} はリスト要素を 1 個作成します。GS1 の補助関数は要素のリスト、または対応する文字列表現を受け付け、50 種に限定した AI カタログを使います。Digital Link の補助関数はオフラインで動作し、互換性を拡張した ASCII URL profile を適用します。GS1 規格全体を検証するものではありません。

\code{generate_structured_append(input,...)} と \code{generate_segments_structured_append} は 2 から 16 個のシンボルを返します。\code{merge_structured_append_parts} は結合する前に順序、個数、パリティを検証します。パリティには元のペイロードのバイト列を使います。

ペイロードのテキストには、欠損値でないスカラー文字列が必要です。NUL を含むバイナリ入力には \code{raw} を使ってください。因子、ベクトル、データフレームを暗黙に変換することはありません。複数のペイロードには \code{lapply} を使ってください。不正な入力では \code{specqr_error} のサブクラスを発生させ、\code{error_code} は安定したコードを返します。リポジトリとソース ZIP、インストール済みの文書には、API、GS1、描画、検証の完全なガイドを含みます。
}
\value{エンコードは、論理行列、バージョン、訂正レベル、マスク、raw のコードワード、セグメント、オプション、診断を含む、クラスを持つリストを返します。計画は、\code{ok}、必要なビット数、容量を含む、クラスを持つリストを返します。補助関数は上記で説明したデータ型を返します。}
\examples{
q <- generate("HELLO WORLD")
stopifnot(q$size == 21, is.raw(to_png(q, scale=1)))
p <- plan("1234567890", version=1)
stopifnot(p$ok)
b <- generate(as.raw(c(0, 29, 255)))
stopifnot(is.logical(b$matrix))
g <- create_gs1_element_string(list(GS1Element("01", "09506000134352")))
stopifnot(validate_gs1_element_string(g)$ok)
}
\keyword{package}

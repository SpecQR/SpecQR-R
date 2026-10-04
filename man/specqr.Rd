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
\title{Dependency-Free QR Model 2 Encoding in R}
\description{QR Model 2 versions 1 through 40, all four correction levels and eight masks, segment optimization, GS1 helpers, structured append and image rendering. All runtime algorithms use base R.}
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
  \item{value, input}{One Unicode character scalar, a raw vector, or an explicitly supported list of segments. NUL is available only through raw bytes.}
  \item{segments}{A list of validated segment objects or explicit segment mappings.}
  \item{options}{A \code{specqr_options} object, or \code{NULL} to use defaults.}
  \item{...}{Named encoding or rendering options described below. Unknown and duplicate names are rejected.}
  \item{version}{QR version, an integer from 1 to 40.}
  \item{error_correction_level}{One of \code{"L"}, \code{"M"}, \code{"Q"}, or \code{"H"}.}
  \item{mode}{One supported data mode, or \code{NULL} for general capacity.}
  \item{control_bits}{Nonnegative exact integer bit budget reserved for controls.}
  \item{text}{One non-missing Unicode string to optimize.}
  \item{allow_kanji}{Whether the optimizer may use the fixed QR Kanji mapping.}
  \item{x}{A QR result or square logical module matrix for rendering.}
  \item{margin, scale}{Quiet-zone modules and pixels per module. \code{NULL} uses stored options or defaults.}
  \item{foreground, background}{Supported color strings; \code{NULL} uses stored options or defaults.}
  \item{format}{Output format, \code{"png"} or \code{"svg"} for data URLs.}
  \item{color}{Hexadecimal RGB/RGBA or a simple ASCII CSS color name.}
  \item{strict}{If \code{TRUE}, unsupported raster colors fail. Otherwise a safe unrecognized name returns \code{NULL}.}
  \item{parts}{Decoded mappings containing exact fields \code{index}, \code{total}, \code{parity}, and \code{data}. Index is one-based.}
}
\details{
Use \code{generate(value, ...)} for a character scalar, raw bytes, or a list of segments. Use \code{specqr_options(...)} for reusable options. Options include \code{error_correction_level}, \code{version}, \code{min_version}, \code{max_version}, \code{mask_pattern}, \code{mode}, \code{optimize_segments}, \code{allow_kanji}, \code{boost_error_correction}, \code{eci}, \code{gs1}, \code{fnc1}, \code{fnc1_second}, \code{structured_append}, \code{margin}, \code{scale}, \code{foreground}, \code{background}, and \code{print_dpi}. Defaults use automatic version/mask, correction level M, margin 4 and scale 8. Unknown or duplicate options fail.

\code{plan} and \code{estimate} return arithmetic capacity plans; \code{generate} returns a \code{specqr_result}. \code{generate_segments}, \code{plan_segments} and \code{analyze_segments} accept manually specified segments. \code{segment(mode, data=NULL, ...)} creates a validated segment. Convenience functions construct numeric, alphanumeric, byte, kanji, ECI, FNC1 and structured-append segments. ECI, FNC1 and structured-append controls cannot be combined.

\code{to_svg} returns a string; \code{to_png} returns raw PNG bytes. \code{to_pixels} returns row-major RGBA bytes and dimensions. Data URL helpers return strings. Rendering uses no external image package or graphics device. \code{render_dimensions} supports explicit \code{dpi}. \code{module_at(result,x,y)} uses one-based column and row coordinates.

\code{GS1Element(ai,value)} creates one list element. GS1 helpers accept a list of elements or supported string representations and use a bounded 50-AI catalog. Digital Link helpers are offline and apply a strict ASCII-authority profile. They are not a complete GS1 standards validator.

\code{generate_structured_append(input,...)} and \code{generate_segments_structured_append} return 2 to 16 symbols. \code{merge_structured_append_parts} validates order, count and parity before merging. Parity uses the original payload bytes.

Payload text must be a non-missing scalar string. For binary input including NUL, use \code{raw}. Factors, vectors and data frames are not silently converted. Use \code{lapply} for multiple payloads. Invalid inputs raise subclasses of \code{specqr_error}; \code{error_code} returns a stable code. The repository/source ZIP and installed documentation include the full API, GS1, rendering and verification guides.
}
\value{Encoding returns a classed list with a logical matrix, version, correction level, mask, raw codewords, segments, options and diagnostics. Planning returns a classed list including \code{ok}, required bits and capacity. Helpers return the data type described above.}
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

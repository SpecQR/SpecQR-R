# Arithmetic-only planning and checked, idiomatic S3 results.
.qr_option_defaults <- function() list(error_correction_level = "M", version = NULL,
  min_version = 1L, max_version = 40L, mask_pattern = NULL, mode = "auto",
  optimize_segments = TRUE, allow_kanji = TRUE, boost_error_correction = FALSE,
  eci = NULL, gs1 = FALSE, fnc1 = FALSE, fnc1_second = NULL,
  structured_append = NULL, margin = 4L, scale = 8L,
  foreground = "#000000", background = "#ffffff", print_dpi = NULL)
specqr_options <- function(...) {
  o <- .qr_option_defaults(); args <- .qr_dots(list(...), names(o)); o[names(args)] <- args
  validate_level(o$error_correction_level)
  o$min_version <- .qr_integer(o$min_version, "min_version", 1, 40, "invalid_version")
  o$max_version <- .qr_integer(o$max_version, "max_version", 1, 40, "invalid_version")
  if (o$min_version > o$max_version) .qr_fail("min_version must not exceed max_version", "invalid_version")
  if (!is.null(o$version)) o$version <- .qr_integer(o$version, "version", 1, 40, "invalid_version")
  if (!is.null(o$mask_pattern)) o$mask_pattern <- .qr_integer(o$mask_pattern, "mask_pattern", 0, 7)
  if (!is.character(o$mode) || is.object(o$mode) || !is.null(dim(o$mode)) || length(o$mode) != 1L || is.na(o$mode) || !o$mode %in% c("auto", .OPT_MODES))
    .qr_fail("Unsupported data mode", "invalid_mode")
  for (key in c("optimize_segments", "allow_kanji", "boost_error_correction", "gs1", "fnc1")) .qr_bool(o[[key]], key)
  o["eci"] <- list(if (is.null(o$eci) || identical(o$eci, FALSE)) NULL else if (identical(o$eci, TRUE)) 26L else .qr_integer(o$eci, "eci", 0, 999999, "invalid_eci"))
  if (!is.null(o$fnc1_second)) segment("fnc1-second", application_indicator = o$fnc1_second)
  if (!is.null(o$structured_append)) {
    sa <- o$structured_append
    if (!inherits(sa, "specqr_segment")) {
      sa <- .qr_mapping(sa, "structured_append")
      if (!setequal(names(sa), c("index", "total", "parity"))) .qr_fail("structured_append requires index, total and parity", "invalid_mode")
      sa <- segment("structured-append", index = sa$index, total = sa$total, parity = sa$parity)
    }
    sa <- normalize_segments(list(sa))[[1L]]
    if (sa$mode != "structured-append") .qr_fail("structured_append must be a Structured Append header", "invalid_mode")
    o$structured_append <- sa
  }
  if (sum(c(o$gs1 || o$fnc1, !is.null(o$fnc1_second), !is.null(o$eci), !is.null(o$structured_append))) > 1L)
    .qr_fail("FNC1, ECI, and Structured Append cannot be combined", "invalid_mode")
  o$margin <- .qr_integer(o$margin, "margin", 0, 1000000000)
  o$scale <- .qr_integer(o$scale, "scale", 1, 1000000000)
  for (key in c("foreground", "background")) {
    o[[key]] <- .qr_text(o[[key]], key)
    if (nchar(o[[key]], type = "bytes") > floor(8388608 / 12)) .qr_fail(paste0(key, " exceeds color resource limit"))
    parse_color(o[[key]], strict = FALSE)
  }
  if (!is.null(o$print_dpi)) {
    dpi <- o$print_dpi
    if (!(is.integer(dpi) || is.double(dpi)) || is.object(dpi) || !is.null(dim(dpi)) || length(dpi) != 1L || is.na(dpi) || !is.finite(dpi) || dpi <= 0 || !is.finite((177 + 2 * o$margin) * (o$scale / dpi * 25.4)))
      .qr_fail("print_dpi must produce finite positive print geometry")
  }
  structure(o, class = "specqr_options")
}
.qr_options <- function(options = NULL, args = list()) {
  args <- .qr_dots(args, names(.qr_option_defaults()))
  if (is.null(options)) return(do.call(specqr_options, args, quote = TRUE))
  if (!inherits(options, "specqr_options") || !is.list(options)) .qr_fail("options must be specqr_options or NULL")
  values <- unclass(options); .qr_mapping(values)
  if (!setequal(names(values), names(.qr_option_defaults()))) .qr_fail("Malformed options object")
  # Quote reconstructed values: stored language and symbols are untrusted data,
  # never expressions to evaluate. Revalidate the base before applying overrides.
  values <- unclass(do.call(specqr_options, values, quote = TRUE)); values[names(args)] <- args
  do.call(specqr_options, values, quote = TRUE)
}
get_capacity <- function(version, error_correction_level = "M", mode = NULL, control_bits = 0, ...) {
  .qr_dots(list(...), character()); v <- .qr_integer(version, "version", 1, 40, "invalid_version")
  validate_level(error_correction_level); control_bits <- .qr_integer(control_bits, "control_bits", 0, 2^53 - 1)
  data <- data_codeword_count(v, error_correction_level); width <- payload <- maximum <- NULL
  if (!is.null(mode)) {
    if (!is.character(mode) || is.object(mode) || !is.null(dim(mode)) || length(mode) != 1L || is.na(mode) || !mode %in% .OPT_MODES)
      .qr_fail("Capacity requires a data mode", "invalid_mode")
    width <- character_count_bits(v, mode); payload <- max(0, 8 * data - control_bits - 4L - width)
    maximum <- switch(mode, numeric = (payload %/% 10L) * 3L + if (payload %% 10L >= 7L) 2L else if (payload %% 10L >= 4L) 1L else 0L,
      alphanumeric = (payload %/% 11L) * 2L + as.integer(payload %% 11L >= 6L), byte = payload %/% 8L, kanji = payload %/% 13L)
    maximum <- min(maximum, 2^width - 1L)
  }
  structure(list(version = v, error_correction_level = error_correction_level, size = qr_size(v),
    data_codewords = data, total_codewords = raw_codeword_count(v), capacity_bits = 8 * data,
    mode = mode, character_count_bits = width, mode_indicator_bits = if (is.null(mode)) NULL else 4L,
    control_bits = control_bits, payload_bits = payload, max_characters = if (identical(mode, "byte")) NULL else maximum,
    max_bytes = if (identical(mode, "byte")) maximum else NULL, maximum = maximum), class = "specqr_capacity")
}
.qr_controls <- function(segments, o) {
  prefix <- if (!is.null(o$eci)) list(segment("eci", assignment_number = o$eci)) else if (o$gs1 || o$fnc1) list(segment("fnc1")) else if (!is.null(o$fnc1_second)) list(segment("fnc1-second", application_indicator = o$fnc1_second)) else if (!is.null(o$structured_append)) list(o$structured_append) else list()
  normalize_segments(c(prefix, segments))
}
.qr_segment_diagnostic <- function(s, v) list(mode = s$mode, character_count = s$character_count,
  byte_count = s$byte_count, count = s$count, bit_length = segment_bit_length(s, v))
.qr_diagnostics <- function(segments, v, level, required, o, planning = TRUE, ok = TRUE) {
  capacity <- 8 * data_codeword_count(v, level); controls <- Filter(function(s) s$is_control, segments)
  modes <- unique(vapply(Filter(function(s) !s$is_control, segments), function(s) s$mode, character(1)))
  mode <- if (!length(modes)) "byte" else if (length(modes) == 1L) modes else "mixed"
  warnings <- list()
  warn <- function(code, severity, message, ...) { warnings[[length(warnings) + 1L]] <<- list(code = code, severity = severity, message = message, details = list(...)) }
  if (o$margin < 4L) warn("QUIET_ZONE_TOO_SMALL", "warning", "QR readers expect at least four quiet-zone modules.", margin = o$margin)
  fg <- parse_color(o$foreground, strict = FALSE); bg <- parse_color(o$background, strict = FALSE)
  ratio <- if (is.null(fg) || is.null(bg)) NULL else contrast_ratio(fg, bg)
  if (is.null(ratio)) warn("COLOR_CONTRAST_UNKNOWN", "info", "These SVG colors cannot be checked for contrast.") else if (ratio < 4.5) warn("COLOR_CONTRAST_LOW", "warning", "Color contrast is below the recommended minimum.", ratio = ratio) else if (ratio < 7) warn("COLOR_CONTRAST_MODERATE", "info", "Stronger color contrast is recommended.", ratio = ratio)
  if (!is.null(fg) && !is.null(bg) && (fg[4L] < 255L || bg[4L] < 255L)) warn("COLOR_ALPHA_USED", "warning", "Transparent colors can reduce scan reliability.")
  if (capacity - required >= 0 && capacity - required < capacity * 0.05) warn("CAPACITY_NEAR_LIMIT", "info", "The selected version is close to full capacity.")
  mm <- if (is.null(o$print_dpi)) NULL else o$scale / o$print_dpi * 25.4
  if (!is.null(mm) && mm < 0.25) warn("PRINT_MODULE_TOO_SMALL", "warning", "Print modules are smaller than 0.25 mm.", module_size_mm = mm)
  blocking <- vapply(Filter(function(w) w$severity == "warning", warnings), function(w) w$code, character(1))
  if (length(blocking)) warn("SCAN_RISK", "warning", "One or more settings may reduce scan reliability.", blocking_warnings = blocking)
  find <- function(mode) { found <- Filter(function(s) s$mode == mode, controls); if (length(found)) found[[1L]] else NULL }
  sa <- find("structured-append"); second <- find("fnc1-second"); ec <- find("eci")
  fn <- if (!is.null(find("fnc1"))) "first-position" else if (!is.null(second)) "second-position" else NULL
  selection <- if (!is.null(o$version)) "fixed" else if (ok) "auto-minimum" else "auto-range"
  reason <- if (!is.null(o$version)) paste0("Version ", v, " was requested explicitly.") else if (ok) paste0("Version ", v, " is the smallest version in ", o$min_version, "..", o$max_version, " that fits.") else paste0("No version in ", o$min_version, "..", o$max_version, " fits; capacity is for version ", v, ".")
  list(phase = if (planning) "planning" else "generation", render_planned = FALSE, mask_evaluated = !planning,
    codewords_built = !planning, ok = ok, version = if (ok || !is.null(o$version)) v else NULL, capacity_version = v,
    size = if (ok || !is.null(o$version)) qr_size(v) else NULL, error_correction_level = level,
    requested_error_correction_level = o$error_correction_level, boosted_error_correction = level != o$error_correction_level,
    version_selection = selection, version_selection_reason = reason, mode = mode,
    control_segments = lapply(controls, .qr_segment_diagnostic, v = v), eci_assignment_number = ec$assignment_number,
    fnc1 = fn, gs1 = identical(fn, "first-position"),
    gs1_validation = list(enabled = FALSE, element_count = 0L, ais = character(), has_separators = FALSE),
    fnc1_second = list(enabled = !is.null(second), application_indicator = second$application_indicator, application_indicator_codeword = second$application_indicator_codeword),
    structured_append = list(enabled = !is.null(sa), index = sa$index, total = sa$total, parity = sa$parity,
      sequence_index = if (is.null(sa)) NULL else sa$index - 1L, sequence_total = if (is.null(sa)) NULL else sa$total - 1L,
      sequence_indicator = if (is.null(sa)) NULL else (sa$index - 1L) * 16L + sa$total - 1L),
    segments = lapply(segments, .qr_segment_diagnostic, v = v), data_bit_length = required,
    capacity_bits = capacity, remaining_bits = capacity - required, overflow_bits = max(0, required - capacity),
    capacity_utilization = required / capacity, input_bytes = sum(vapply(segments, function(s) length(s$logical_bytes), numeric(1))),
    quiet_zone = list(modules = o$margin, recommended_modules = 4L, is_sufficient = o$margin >= 4L),
    colors = list(ratio = ratio, is_inspectable = !is.null(ratio), foreground_alpha = if (is.null(fg)) NULL else fg[4L],
      background_alpha = if (is.null(bg)) NULL else bg[4L], is_strong = !is.null(ratio) && ratio >= 7,
      is_sufficient = !is.null(ratio) && ratio >= 4.5 && fg[4L] == 255L && bg[4L] == 255L),
    print = list(dpi = o$print_dpi, module_pixels = o$scale, module_size_mm = mm,
      symbol_size_mm = if (is.null(mm)) NULL else (qr_size(v) + 2 * o$margin) * mm,
      recommended_minimum_module_size_mm = 0.25, is_module_size_sufficient = if (is.null(mm)) NULL else mm >= 0.25), warnings = warnings)
}
.qr_select <- function(factory, o, gs1_validation = NULL) {
  versions <- if (is.null(o$version)) seq.int(o$min_version, o$max_version) else o$version
  cache <- vector("list", 3L); ok <- FALSE
  for (v in versions) {
    group <- if (v <= 9L) 1L else if (v <= 26L) 2L else 3L
    if (is.null(cache[[group]])) {
      segments <- factory(v)
      fit <- all(vapply(segments, function(s) s$is_control || s$count < 2^character_count_bits(v, s$mode), logical(1)))
      cache[[group]] <- list(segments = segments, required = segments_bit_length(segments, v), fit = fit)
    }
    found <- cache[[group]]; segments <- found$segments; required <- found$required
    ok <- found$fit && required <= 8 * data_codeword_count(v, o$error_correction_level)
    if (ok) break
  }
  level <- o$error_correction_level
  if (ok && o$boost_error_correction) {
    levels <- c("L", "M", "Q", "H")
    for (stronger in levels[seq.int(match(level, levels), 4L)]) if (required <= 8 * data_codeword_count(v, stronger)) level <- stronger
  }
  capacity <- 8 * data_codeword_count(v, level); d <- .qr_diagnostics(segments, v, level, required, o, ok = ok)
  if (!is.null(gs1_validation)) d$gs1_validation <- gs1_validation
  structure(list(ok = ok, version = if (ok || !is.null(o$version)) v else NULL, capacity_version = v,
    error_correction_level = level, requested_error_correction_level = o$error_correction_level,
    boosted_error_correction = level != o$error_correction_level, data_bit_length = required,
    capacity_bits = capacity, remaining_bits = capacity - required, segments = segments, diagnostics = d,
    selected_version = if (ok || !is.null(o$version)) v else NULL, overflow_bits = max(0, required - capacity),
    capacity_utilization = required / capacity, warnings = d$warnings, options = o), class = "specqr_plan")
}
.qr_input_plan <- function(value, o) {
  value <- .qr_input(value); validation <- NULL; mode <- o$mode
  if (o$gs1) {
    if (!is.character(value)) .qr_fail("High-level GS1 requires text", "invalid_gs1")
    parsed <- parse_gs1_element_string(value)
    validation <- list(enabled = TRUE, element_count = length(parsed$elements),
      ais = vapply(parsed$elements, function(e) e$ai, character(1)), has_separators = grepl("\035", value, fixed = TRUE))
  }
  if ((o$gs1 || o$fnc1 || !is.null(o$fnc1_second)) && is.character(value) && grepl("%", value, fixed = TRUE)) {
    if (mode == "alphanumeric") .qr_fail("Literal percent in high-level FNC1 requires byte mode; use escaped manual segments", "invalid_mode")
    if (mode == "auto") mode <- "byte"
  }
  factory <- function(v) .qr_controls(create_segments(value, mode = mode, version = v,
    optimize = o$optimize_segments && !(is.character(value) && nchar(value, type = "chars") > 7089L),
    allow_kanji = o$allow_kanji && is.null(o$eci)), o)
  .qr_select(factory, o, validation)
}
estimate <- function(value, options = NULL, ...) {
  o <- .qr_options(options, list(...))
  if (is.list(value)) return(analyze_segments(value, o))
  .qr_input_plan(value, o)
}
plan <- estimate
analyze_segments <- function(segments, options = NULL, ...) {
  o <- .qr_options(options, list(...))
  if (o$gs1) .qr_fail("Manual GS1 data requires an explicit FNC1 segment", "invalid_gs1")
  found <- .qr_controls(normalize_segments(segments), o)
  .qr_select(function(v) found, o)
}
plan_segments <- analyze_segments
.qr_build <- function(p, o) {
  if (!p$ok) .qr_fail(paste0("Input requires ", p$data_bit_length, " bits; version ", p$capacity_version, "-", p$error_correction_level, " holds ", p$capacity_bits), "data_too_long")
  v <- p$capacity_version; level <- p$error_correction_level
  payload <- unlist(lapply(p$segments, segment_bits, version = v), use.names = FALSE)
  if (is.null(payload)) payload <- integer()
  data <- pad_data_bits(payload, v, level); interleaved <- interleave_codewords(data, v, level)
  built <- build_matrix(interleaved$codewords, v, level, o$mask_pattern)
  d <- .qr_diagnostics(p$segments, v, level, p$data_bit_length, o, planning = FALSE)
  d$gs1_validation <- p$diagnostics$gs1_validation
  d <- c(d, list(mask_pattern = built$mask_pattern, mask_penalty = built$penalty, mask_penalties = built$mask_penalties,
    mask_selection_reason = if (is.null(o$mask_pattern)) "Lowest penalty; first mask wins ties." else "Explicit mask requested.",
    data_codewords = length(data), error_correction_codewords = length(interleaved$codewords) - length(data), total_codewords = length(interleaved$codewords)))
  structure(list(matrix = built$matrix, version = v, mask_pattern = built$mask_pattern,
    error_correction_level = level, data_codewords = data, codewords = interleaved$codewords,
    segments = p$segments, diagnostics = d, options = o, size = nrow(built$matrix),
    error_correction_codewords = interleaved$codewords[seq.int(length(data) + 1L, length(interleaved$codewords))]), class = "specqr_result")
}
generate <- function(value, options = NULL, ...) {
  o <- .qr_options(options, list(...))
  if (is.list(value)) return(generate_segments(value, o))
  .qr_build(.qr_input_plan(value, o), o)
}
generate_segments <- function(segments, options = NULL, ...) {
  o <- .qr_options(options, list(...)); .qr_build(analyze_segments(segments, o), o)
}
.qr_validate_diagnostics <- function(x) {
  # One shared budget bounds total traversal, including compact lists whose
  # branches refer to the same large subtree. Per-node depth/length limits alone
  # do not bound the expanded work on such caller-mutated diagnostic objects.
  remaining <- 1000000L
  visit <- function(value, depth) {
    units <- max(1L, length(value)); remaining <<- remaining - units
    if (remaining < 0L || depth > 24L || is.object(value) || !is.null(dim(value))) .qr_fail("Diagnostics exceed validation bounds or are malformed")
    if (is.null(value)) return(invisible(NULL))
    if (is.list(value)) {
      if (!is.null(names(value)) && (anyNA(names(value)) || anyDuplicated(names(value)))) .qr_fail("Malformed diagnostic names")
      for (item in value) visit(item, depth + 1L)
    } else if (is.numeric(value)) {
      if (anyNA(value) || any(!is.finite(value))) .qr_fail("Diagnostic numbers must be finite")
    } else if (is.character(value) || is.logical(value)) {
      if (anyNA(value)) .qr_fail("Diagnostic values must not be missing")
    } else .qr_fail("Malformed diagnostic values")
    invisible(NULL)
  }
  visit(x, 0L)
  invisible(NULL)
}
.qr_validate_result <- function(q) {
  if (!inherits(q, "specqr_result") || !is.list(q) || !is.null(dim(q))) .qr_fail("Expected a specqr_result")
  expected <- c("matrix", "version", "mask_pattern", "error_correction_level", "data_codewords", "codewords", "segments", "diagnostics", "options", "size", "error_correction_codewords")
  if (anyDuplicated(names(q)) || !setequal(names(q), expected)) .qr_fail("Malformed QR result")
  validate_version(q$version); validate_level(q$error_correction_level); .qr_integer(q$mask_pattern, "mask_pattern", 0, 7)
  n <- qr_size(q$version)
  if (!is.matrix(q$matrix) || !is.logical(q$matrix) || anyNA(q$matrix) || !identical(dim(q$matrix), c(as.integer(n), as.integer(n)))) .qr_fail("Malformed QR matrix")
  .qr_integer(q$size, "size", n, n)
  if (!inherits(q$options, "specqr_options")) .qr_fail("Malformed result options")
  .qr_options(q$options); ss <- normalize_segments(q$segments)
  required <- segments_bit_length(ss, q$version); capacity <- 8 * data_codeword_count(q$version, q$error_correction_level)
  if (required > capacity || !all(vapply(ss, function(s) s$is_control || s$count < 2^character_count_bits(q$version, s$mode), logical(1)))) .qr_fail("Result segments exceed capacity")
  if (!is.raw(q$data_codewords) || !is.null(dim(q$data_codewords)) || !is.raw(q$codewords) || !is.null(dim(q$codewords)) || length(q$data_codewords) != capacity / 8L || length(q$codewords) != raw_codeword_count(q$version)) .qr_fail("Malformed QR codewords")
  ecc <- q$codewords[seq.int(length(q$data_codewords) + 1L, length(q$codewords))]
  if (!identical(q$error_correction_codewords, ecc)) .qr_fail("Inconsistent correction codewords")
  if (!is.list(q$diagnostics)) .qr_fail("Malformed QR diagnostics")
  .qr_validate_diagnostics(q$diagnostics)
  .qr_integer(q$diagnostics[["data_bit_length"]], "data_bit_length", required, required)
  .qr_integer(q$diagnostics[["capacity_bits"]], "capacity_bits", capacity, capacity)
  invisible(q)
}
.qr_validate_plan <- function(p) {
  expected <- c("ok", "version", "capacity_version", "error_correction_level", "requested_error_correction_level", "boosted_error_correction", "data_bit_length", "capacity_bits", "remaining_bits", "segments", "diagnostics", "selected_version", "overflow_bits", "capacity_utilization", "warnings", "options")
  if (!inherits(p, "specqr_plan") || !is.list(p) || !is.null(dim(p)) || anyDuplicated(names(p)) || !setequal(names(p), expected)) .qr_fail("Expected a valid specqr_plan")
  if (!inherits(p$options, "specqr_options")) .qr_fail("Malformed plan options")
  o <- .qr_options(p$options); .qr_bool(p$ok, "ok"); validate_version(p$capacity_version)
  validate_level(p$error_correction_level); ss <- normalize_segments(p$segments)
  required <- segments_bit_length(ss, p$capacity_version); capacity <- 8 * data_codeword_count(p$capacity_version, p$error_correction_level)
  .qr_integer(p$data_bit_length, "data_bit_length", required, required)
  .qr_integer(p$capacity_bits, "capacity_bits", capacity, capacity)
  .qr_integer(p$remaining_bits, "remaining_bits", capacity - required, capacity - required)
  .qr_integer(p$overflow_bits, "overflow_bits", max(0, required - capacity), max(0, required - capacity))
  counts_fit <- all(vapply(ss, function(s) s$is_control || s$count < 2^character_count_bits(p$capacity_version, s$mode), logical(1)))
  if (!identical(p$ok, counts_fit && required <= capacity)) .qr_fail("Inconsistent plan feasibility")
  if (p$ok || !is.null(o$version)) .qr_integer(p$version, "version", p$capacity_version, p$capacity_version) else if (!is.null(p$version)) .qr_fail("Overflow plan must have no selected version")
  if (!identical(p$selected_version, p$version)) .qr_fail("Inconsistent selected version")
  if (!is.numeric(p$capacity_utilization) || length(p$capacity_utilization) != 1L || is.na(p$capacity_utilization) || p$capacity_utilization != required / capacity) .qr_fail("Inconsistent capacity utilization")
  if (!is.list(p$diagnostics)) .qr_fail("Malformed plan diagnostics")
  .qr_validate_diagnostics(p$diagnostics)
  .qr_integer(p$diagnostics[["data_bit_length"]], "data_bit_length", required, required)
  .qr_integer(p$diagnostics[["capacity_bits"]], "capacity_bits", capacity, capacity)
  invisible(p)
}
diagnostics <- function(result, ...) {
  .qr_dots(list(...), character())
  if (inherits(result, "specqr_result")) .qr_validate_result(result) else if (inherits(result, "specqr_plan")) .qr_validate_plan(result) else if (inherits(result, "specqr_sa_result") || inherits(result, "specqr_merge_result")) .qr_validate_sa_result(result) else .qr_fail("Expected a SpecQR result or plan")
  result$diagnostics
}
module_at <- function(result, x, y, ...) {
  .qr_dots(list(...), character()); .qr_validate_result(result)
  xx <- .qr_integer(x, "x", 1, ncol(result$matrix)); yy <- .qr_integer(y, "y", 1, nrow(result$matrix))
  result$matrix[yy, xx]
}
print.specqr_options <- function(x, ...) { .qr_options(x); cat("SpecQR options: ECC ", x$error_correction_level, ", versions ", x$min_version, "..", x$max_version, "\n", sep = ""); invisible(x) }
print.specqr_plan <- function(x, ...) { .qr_validate_plan(x); cat("SpecQR plan: ", if (x$ok) "fits" else "overflow", ", version ", x$capacity_version, "-", x$error_correction_level, ", ", x$data_bit_length, "/", x$capacity_bits, " bits\n", sep = ""); invisible(x) }
print.specqr_result <- function(x, ...) { .qr_validate_result(x); cat("SpecQR: version ", x$version, "-", x$error_correction_level, ", mask ", x$mask_pattern, ", ", x$size, " x ", x$size, " modules\n", sep = ""); invisible(x) }
print.specqr_capacity <- function(x, ...) {
  if (!inherits(x, "specqr_capacity") || !is.list(x) || !is.null(dim(x)) || anyDuplicated(names(x))) .qr_fail("Malformed capacity object")
  expected <- get_capacity(x[["version"]], x[["error_correction_level"]], x[["mode"]], x[["control_bits"]])
  if (!identical(x, expected)) .qr_fail("Inconsistent capacity object")
  cat("SpecQR capacity: version ", x$version, "-", x$error_correction_level, ", ", x$capacity_bits, " data bits\n", sep = ""); invisible(x) }

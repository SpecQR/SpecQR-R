# Canonical original UTF-8/raw-byte parity; deterministic 2..16 equal-version
# symbols. Text is split only at Unicode scalar boundaries. Manual non-byte
# segments remain indivisible, while byte segments may be split.
.qr_xor <- function(bytes) Reduce(bitwXor, as.integer(bytes), init = 0L)
calculate_structured_append_parity <- function(input, ...) {
  .qr_dots(list(...), character()); input <- .qr_input(input)
  .qr_xor(if (is.raw(input)) input else charToRaw(input))
}
.qr_sa_manual <- function(values, budget = 1000000) {
  ss <- normalize_segments(values)
  if (!length(ss)) .qr_fail("Structured Append needs nonempty manual segments")
  units <- 0
  for (s in ss) {
    if (s$mode == "fnc1") .qr_fail("Structured Append cannot be combined with FNC1", "invalid_gs1")
    if (s$is_control) .qr_fail("Structured Append cannot include manual control segments", "invalid_mode")
    n <- if (is.raw(s$data)) length(s$data) else nchar(s$data, type = "chars")
    if (!n) .qr_fail("Structured Append requires nonempty data segments")
    units <- units + n
    if (units > min(1000000, budget)) .qr_fail("Manual payload exceeds Structured Append capacity", "data_too_long")
  }
  ss
}
calculate_structured_append_segments_parity <- function(segments, ...) {
  args <- .qr_dots(list(...))
  if ("gs1" %in% names(args)) .qr_fail("Segment parity does not accept GS1 options", "invalid_gs1")
  if (length(args)) .qr_fail("Unsupported segment parity option", "invalid_mode")
  .qr_xor(vapply(.qr_sa_manual(segments), function(s) .qr_xor(s$logical_bytes), integer(1)))
}
.qr_sa_options <- function(options, args, manual) {
  args <- .qr_dots(args)
  forbidden <- c("parity", "error_correction", "mask", "encoding", if (manual) c("mode", "optimize_segments", "allow_kanji"))
  if (any(names(args) %in% forbidden)) .qr_fail(paste0("Unsupported Structured Append option: ", names(args)[which(names(args) %in% forbidden)[1L]]), "invalid_mode")
  maximum <- if ("max_symbols" %in% names(args)) .qr_integer(args$max_symbols, "max_symbols", 2, 16, "invalid_mode") else 16L
  diagnostic <- if ("diagnostics" %in% names(args)) args$diagnostics else FALSE
  args[c("max_symbols", "diagnostics")] <- NULL
  detail <- "summary"; symbol_results <- "output"
  if (is.logical(diagnostic) && length(diagnostic) == 1L && !is.na(diagnostic) && !is.object(diagnostic) && is.null(dim(diagnostic))) {
    if (diagnostic) symbol_results <- "diagnostics"
  } else if (manual && is.list(diagnostic)) {
    d <- .qr_mapping(diagnostic, "diagnostics"); .qr_dots(d, c("split_units", "symbol_results"))
    if ("split_units" %in% names(d)) detail <- d$split_units
    symbol_results <- if ("symbol_results" %in% names(d)) d$symbol_results else "diagnostics"
    if (!is.character(detail) || is.object(detail) || !is.null(dim(detail)) || length(detail) != 1L || is.na(detail) || !detail %in% c("summary", "full") || !is.character(symbol_results) || is.object(symbol_results) || !is.null(dim(symbol_results)) || length(symbol_results) != 1L || is.na(symbol_results) || !symbol_results %in% c("output", "diagnostics")) .qr_fail("Invalid Structured Append diagnostic detail")
  } else .qr_fail("diagnostics must be a scalar logical or a manual diagnostics mapping")
  for (key in c("structured_append", "fnc1_second")) if (identical(args[[key]], FALSE)) args[key] <- list(NULL)
  o <- .qr_options(options, args)
  if (o$gs1) .qr_fail("Structured Append cannot be combined with gs1", "invalid_gs1")
  if (o$fnc1 || !is.null(o$eci) || !is.null(o$fnc1_second) || !is.null(o$structured_append)) .qr_fail("Structured Append owns its header and cannot include other controls", "invalid_mode")
  if (o$boost_error_correction) .qr_fail("Structured Append does not support ECC boosting", "invalid_mode")
  if (manual && (o$mode != "auto" || !o$optimize_segments)) .qr_fail("Manual Structured Append preserves caller modes", "invalid_mode")
  list(options = o, maximum = maximum, detail = detail, symbol_results = symbol_results)
}
.qr_sa_capacity <- function(o, v) 8 * data_codeword_count(v, o$error_correction_level)
.qr_sa_max_version <- function(o) if (is.null(o$version)) o$max_version else o$version
.qr_sa_budget <- function(o, maximum) maximum * floor(max(0, .qr_sa_capacity(o, .qr_sa_max_version(o)) - 20) * 3 / 10)
.qr_sa_segment_bits <- function(mode, n, nb, v) {
  width <- character_count_bits(v, mode); count <- if (mode == "byte") nb else n
  if (count >= 2^width) return(Inf)
  4 + width + .qr_payload_bits(mode, n, nb)
}
.qr_offsets <- function(cp) c(0, cumsum(ifelse(cp < 128L, 1L, ifelse(cp < 2048L, 2L, ifelse(cp < 65536L, 3L, 4L)))))
.qr_sa_source <- function(value, o, maximum) {
  value <- .qr_input(value); binary <- is.raw(value); cp <- if (binary) integer() else utf8ToInt(value)
  n <- if (binary) length(value) else length(cp)
  if (!n) .qr_fail("Structured Append needs at least two nonempty symbols")
  if (n > .qr_sa_budget(o, maximum)) .qr_fail("Input exceeds Structured Append capacity", "data_too_long")
  nb <- if (binary) n else nchar(value, type = "bytes")
  if (binary && !o$mode %in% c("auto", "byte")) .qr_fail("Binary input requires byte mode", "invalid_mode")
  if (!binary && o$mode != "auto") segment(o$mode, value)
  mode <- if (binary) "byte" else o$mode; v <- .qr_sa_max_version(o)
  width <- if (mode == "auto") min(vapply(.OPT_MODES, function(m) character_count_bits(v, m), numeric(1))) else character_count_bits(v, mode)
  required <- if (mode == "auto") .qr_payload_bits("numeric", n) else .qr_payload_bits(mode, n, nb)
  if (required > maximum * max(0, .qr_sa_capacity(o, v) - 24 - width)) .qr_fail("Input exceeds Structured Append capacity", "data_too_long")
  list(manual = FALSE, data = value, cp = cp, offsets = if (binary) numeric() else .qr_offsets(cp), binary = binary,
       length = n, input_length = n, byte_length = nb, parity = calculate_structured_append_parity(value))
}
.qr_sa_segment_source <- function(values, o, maximum) {
  ss <- .qr_sa_manual(values, .qr_sa_budget(o, maximum)); descriptors <- vector("list", length(ss))
  n <- nb <- parity <- total_bits <- 0; v <- .qr_sa_max_version(o)
  for (i in seq_along(ss)) {
    s <- ss[[i]]; data <- s$data; binary <- is.raw(data); cp <- if (binary) integer() else utf8ToInt(data)
    len <- if (binary) length(data) else length(cp); size <- length(s$logical_bytes)
    split <- if (s$mode == "byte") len else 1L
    descriptors[[i]] <- list(segment = s, data = data, cp = cp, source_index = i - 1L, split_start = n,
      split_count = split, byte_start = nb, byte_length = size, offsets = if (!binary && s$mode == "byte") .qr_offsets(cp) else numeric())
    n <- n + split; nb <- nb + size; parity <- bitwXor(parity, .qr_xor(s$logical_bytes))
    total_bits <- total_bits + 4L + character_count_bits(v, s$mode) + .qr_payload_bits(s$mode, len, size)
  }
  if (total_bits > maximum * max(0, .qr_sa_capacity(o, v) - 20L)) .qr_fail("Segments exceed Structured Append capacity", "data_too_long")
  list(manual = TRUE, segments = ss, descriptors = descriptors, length = n, input_length = length(ss), byte_length = nb, parity = parity)
}
.qr_sa_slice <- function(s, start, n) {
  if (!n) return(if (s$binary) raw() else "")
  if (s$binary) s$data[seq.int(start + 1L, start + n)] else intToUtf8(s$cp[seq.int(start + 1L, start + n)])
}
.qr_sa_ranges <- function(s, start, n) {
  out <- list(); finish <- start + n
  for (d in s$descriptors) {
    if (d$split_start + d$split_count <= start) next
    if (d$split_start >= finish) break
    overlap <- max(start, d$split_start)
    out[[length(out) + 1L]] <- list(descriptor = d, start = overlap - d$split_start, n = min(finish, d$split_start + d$split_count) - overlap)
  }
  out
}
.qr_sa_range_bytes <- function(d, start, n) {
  if (d$segment$mode != "byte") return(c(d$byte_start, d$byte_length))
  if (is.character(d$data)) return(c(d$byte_start + d$offsets[start + 1L], d$offsets[start + n + 1L] - d$offsets[start + 1L]))
  c(d$byte_start + start, n)
}
.qr_sa_bits <- function(s, start, n, o, v) {
  capacity <- .qr_sa_capacity(o, v)
  if (s$manual) {
    result <- 20L
    for (range in .qr_sa_ranges(s, start, n)) {
      d <- range$descriptor; nb <- .qr_sa_range_bytes(d, range$start, range$n)[2L]
      len <- if (d$segment$mode == "byte") range$n else length(d$cp)
      result <- result + .qr_sa_segment_bits(d$segment$mode, len, nb, v)
      if (result > capacity) break
    }
    return(result)
  }
  if (.qr_payload_bits("numeric", n) > capacity - 20L) return(Inf)
  if (s$binary) return(20L + .qr_sa_segment_bits("byte", n, n, v))
  nb <- s$offsets[start + n + 1L] - s$offsets[start + 1L]
  if (o$mode != "auto") return(20L + .qr_sa_segment_bits(o$mode, n, nb, v))
  if (o$optimize_segments) {
    t <- .qr_optimize(s$cp[seq.int(start + 1L, start + n)], v, o$allow_kanji, capacity - 20L)
    return(20L + t$costs[t$processed + 1L])
  }
  ss <- create_segments(.qr_sa_slice(s, start, n), version = v, optimize = FALSE, allow_kanji = o$allow_kanji)
  if (!all(vapply(ss, function(x) x$count < 2^character_count_bits(v, x$mode), logical(1)))) return(Inf)
  20L + segments_bit_length(ss, v)
}
.qr_sa_chunk <- function(s, start, n) {
  if (!s$manual) return(list(data = .qr_sa_slice(s, start, n), offsets = list(input_start = start, input_length = n,
    byte_start = if (s$binary) start else s$offsets[start + 1L], byte_length = if (s$binary) n else s$offsets[start + n + 1L] - s$offsets[start + 1L])))
  out <- list(); first <- last <- byte_start <- NULL; byte_length <- 0
  for (range in .qr_sa_ranges(s, start, n)) {
    d <- range$descriptor; bytes <- .qr_sa_range_bytes(d, range$start, range$n)
    if (is.null(first)) { first <- d$source_index; byte_start <- bytes[1L] }
    last <- d$source_index + 1L; byte_length <- byte_length + bytes[2L]
    ss <- if (d$segment$mode == "byte") {
      ids <- seq.int(range$start + 1L, range$start + range$n)
      segment("byte", if (is.raw(d$data)) d$data[ids] else intToUtf8(d$cp[ids]))
    } else d$segment
    out[[length(out) + 1L]] <- ss
  }
  list(data = out, offsets = list(source_segment_start = first, source_segment_end = last,
    split_unit_start = start, split_unit_length = n, byte_start = byte_start, byte_length = byte_length))
}
.qr_sa_full_detail <- function(s) {
  result <- vector("list", s$length); at <- 0L
  for (d in s$descriptors) for (unit in seq_len(d$split_count) - 1L) {
    bytes <- .qr_sa_range_bytes(d, unit, 1L); at <- at + 1L
    result[[at]] <- list(source_segment_index = d$source_index, mode = d$segment$mode,
      unit_start = if (d$segment$mode == "byte") unit else 0L,
      unit_length = if (d$segment$mode == "byte") 1L else length(d$cp), byte_start = bytes[1L], byte_length = bytes[2L])
  }
  result
}
.qr_sa_largest <- function(s, start, maximum, o, v) {
  if (maximum <= 0L) return(0L)
  if (!s$manual && !s$binary && o$mode == "auto" && o$optimize_segments) {
    # Even all-numeric data cannot exceed this many scalars in one symbol.
    n <- min(maximum, floor((.qr_sa_capacity(o, v) - 20L) * 3L / 10L) + 3L)
    t <- .qr_optimize(s$cp[seq.int(start + 1L, start + n)], v, o$allow_kanji, .qr_sa_capacity(o, v) - 20L)
    return(if (t$costs[t$processed + 1L] > .qr_sa_capacity(o, v) - 20L) t$processed - 1L else n)
  }
  low <- 1L; high <- maximum; best <- 0L
  while (low <= high) {
    n <- floor((low + high) / 2L)
    if (.qr_sa_bits(s, start, n, o, v) <= .qr_sa_capacity(o, v)) { best <- n; low <- n + 1L } else high <- n - 1L
  }
  best
}
.qr_sa_attempt <- function(s, o, v, maximum) {
  if (.qr_sa_bits(s, 0L, s$length, o, v) <= .qr_sa_capacity(o, v)) return(list(status = "single"))
  ranges <- list(); start <- 0L
  while (start < s$length) {
    if (length(ranges) == maximum) return(list(status = "too_long"))
    n <- .qr_sa_largest(s, start, s$length - start - if (!length(ranges)) 1L else 0L, o, v)
    if (n <= 0L) return(list(status = "too_long"))
    ranges[[length(ranges) + 1L]] <- c(start, n); start <- start + n
  }
  list(status = if (length(ranges) >= 2L) "ok" else "single", ranges = ranges)
}
.qr_sa_generate <- function(s, settings) {
  o <- settings$options; maximum <- settings$maximum
  versions <- if (is.null(o$version)) seq.int(o$min_version, o$max_version) else o$version
  saw_too_long <- FALSE; found <- FALSE
  for (v in versions) {
    attempt <- .qr_sa_attempt(s, o, v, maximum)
    if (attempt$status == "ok") { found <- TRUE; break }
    saw_too_long <- saw_too_long || attempt$status == "too_long"
  }
  if (!found) {
    if (saw_too_long) .qr_fail(paste0("Input cannot be split into ", maximum, " or fewer symbols in the selected version range"), "data_too_long")
    .qr_fail("Input fits in one symbol; use generate or a low-level Structured Append header")
  }
  total <- length(attempt$ranges); symbols <- detail_symbols <- vector("list", total)
  for (index in seq_len(total)) {
    range <- attempt$ranges[[index]]; chunk <- .qr_sa_chunk(s, range[1L], range[2L])
    header <- segment("structured-append", index = index, total = total, parity = s$parity)
    selected <- .qr_options(o, list(version = v, min_version = v, max_version = v, structured_append = header))
    result <- if (s$manual) generate_segments(chunk$data, selected) else generate(chunk$data, selected)
    symbols[[index]] <- result; required <- result$diagnostics$data_bit_length
    detail_symbols[[index]] <- c(list(index = index, total = total, parity = s$parity,
      sequence_index = index - 1L, sequence_total = total - 1L, sequence_indicator = (index - 1L) * 16L + total - 1L,
      version = v, error_correction_level = result$error_correction_level, data_bit_length = required,
      capacity_bits = .qr_sa_capacity(o, v), remaining_bits = .qr_sa_capacity(o, v) - required, mask_pattern = result$mask_pattern), chunk$offsets)
  }
  warnings <- list()
  if (total == maximum) warnings[[length(warnings) + 1L]] <- list(code = "STRUCTURED_APPEND_MAX_SYMBOLS_NEAR_LIMIT", severity = "info", message = "The set uses the configured maximum number of symbols.", details = list(total = total, max_symbols = maximum))
  if (settings$symbol_results == "diagnostics") warnings[[length(warnings) + 1L]] <- list(code = "STRUCTURED_APPEND_DECODER_SUPPORT_VARIES", severity = "info", message = "Decoder APIs vary in how they expose Structured Append metadata.", details = list(total = total))
  selection <- if (is.null(o$version)) "auto-minimum" else "fixed"
  d <- list(version = v, error_correction_level = o$error_correction_level, version_selection = selection,
    version_selection_reason = if (selection == "fixed") paste0("Version ", v, " was requested explicitly.") else paste0("Version ", v, " is the smallest version in ", o$min_version, "..", o$max_version, " that can split the payload into ", total, " symbols."),
    total = total, parity = s$parity, byte_length = s$byte_length, input_length = s$input_length, max_symbols = maximum,
    split_strategy = if (s$manual) "segment-boundary-byte-chunk" else "greedy-largest-fitting", symbols = detail_symbols, warnings = warnings)
  if (s$manual) {
    d$segment_count <- length(s$segments); d$split_unit_count <- s$length; d$split_units_detail <- settings$detail
    if (settings$detail == "full") d$split_units <- .qr_sa_full_detail(s)
  }
  structure(list(symbols = symbols, total = total, parity = s$parity, input_length = s$input_length, byte_length = s$byte_length, diagnostics = d), class = "specqr_sa_result")
}
generate_structured_append <- function(input, options = NULL, ...) {
  if (is.list(input)) return(generate_segments_structured_append(input, options, ...))
  settings <- .qr_sa_options(options, list(...), FALSE)
  .qr_sa_generate(.qr_sa_source(input, settings$options, settings$maximum), settings)
}
generate_segments_structured_append <- function(segments, options = NULL, ...) {
  settings <- .qr_sa_options(options, list(...), TRUE)
  .qr_sa_generate(.qr_sa_segment_source(segments, settings$options, settings$maximum), settings)
}
merge_structured_append_parts <- function(parts, ...) {
  args <- .qr_dots(list(...)); if (length(args)) .qr_fail("Unsupported merge option", "invalid_mode")
  if (!is.list(parts) || is.object(parts) || !is.null(dim(parts)) || length(parts) < 1L || length(parts) > 16L) .qr_fail("parts must contain 1..16 decoded mappings")
  ordered <- vector("list", 16L); total <- parity <- kind <- NULL; nb <- actual <- units <- 0
  for (part in parts) {
    d <- .qr_mapping(part, "part")
    if (!all(c("index", "total", "parity", "data") %in% names(d))) .qr_fail("Part requires exact index, total, parity and data fields")
    index <- .qr_integer(d[["index"]], "index", 1, 16); t <- .qr_integer(d[["total"]], "total", 2, 16); p <- .qr_integer(d[["parity"]], "parity", 0, 255)
    if (index > t) .qr_fail("Index exceeds total")
    if (!is.null(total) && t != total) .qr_fail("Structured Append total mismatch")
    if (!is.null(parity) && p != parity) .qr_fail("Structured Append parity mismatch")
    if (!is.null(ordered[[index]])) .qr_fail(paste0("Duplicate Structured Append index ", index))
    data <- .qr_input(d[["data"]]); binary <- is.raw(data); typ <- if (binary) "binary" else "string"
    n <- if (binary) length(data) else nchar(data, type = "chars"); units <- units + n
    if (units > 1000000L) .qr_fail("Merged input exceeds the resource limit", "data_too_long")
    if (!is.null(kind) && kind != typ) .qr_fail("Parts must not mix text and binary data")
    size <- if (binary) n else nchar(data, type = "bytes"); checksum <- calculate_structured_append_parity(data)
    total <- t; parity <- p; kind <- typ; nb <- nb + size; actual <- bitwXor(actual, checksum)
    ordered[[index]] <- list(data = data, info = list(index = index, total = t, parity = p, data_type = typ, byte_length = size))
  }
  missing <- which(vapply(ordered[seq_len(total)], is.null, logical(1)))
  if (length(missing)) .qr_fail(paste0("Missing Structured Append indexes: ", paste(missing, collapse = ", ")))
  if (length(parts) != total) .qr_fail("Part count does not match total")
  if (actual != parity) .qr_fail("Structured Append parity check failed")
  ordered <- ordered[seq_len(total)]
  merged <- if (kind == "string") paste0(vapply(ordered, function(x) x$data, character(1)), collapse = "") else do.call(c, lapply(ordered, function(x) x$data), quote = TRUE)
  d <- list(part_count = total, total = total, parity = parity, data_type = kind, byte_length = nb,
    missing = integer(), duplicate = integer(), parity_check = list(expected = parity, actual = actual, matches = TRUE))
  structure(list(data = merged, total = total, parity = parity, parts = lapply(ordered, function(x) x$info), diagnostics = d), class = "specqr_merge_result")
}
.qr_validate_sa_result <- function(x) {
  if (!is.list(x) || !is.null(dim(x)) || anyDuplicated(names(x))) .qr_fail("Malformed Structured Append result")
  generated <- inherits(x, "specqr_sa_result"); merged <- inherits(x, "specqr_merge_result")
  if (!generated && !merged) .qr_fail("Expected a Structured Append result")
  fields <- if (generated) c("symbols", "total", "parity", "input_length", "byte_length", "diagnostics") else c("data", "total", "parity", "parts", "diagnostics")
  if (!setequal(names(x), fields)) .qr_fail("Malformed Structured Append result fields")
  d <- .qr_mapping(x[["diagnostics"]], "diagnostics"); .qr_validate_diagnostics(d)
  total <- .qr_integer(x[["total"]], "total", 2, 16); parity <- .qr_integer(x[["parity"]], "parity", 0, 255)
  if (generated) {
    symbols <- x[["symbols"]]
    if (!is.list(symbols) || is.object(symbols) || !is.null(dim(symbols)) || length(symbols) != total) .qr_fail("Malformed Structured Append symbols")
    actual <- nb <- 0L; version <- level <- NULL
    for (i in seq_len(total)) {
      q <- symbols[[i]]; .qr_validate_result(q); ss <- normalize_segments(q$segments)
      if (!length(ss) || ss[[1L]]$mode != "structured-append" || ss[[1L]]$index != i || ss[[1L]]$total != total || ss[[1L]]$parity != parity) .qr_fail("Inconsistent Structured Append header")
      if (is.null(version)) { version <- q$version; level <- q$error_correction_level }
      if (q$version != version || q$error_correction_level != level) .qr_fail("Structured Append symbols must share version and correction level")
      symbol_bytes <- 0L
      for (s in ss[-1L]) { actual <- bitwXor(actual, .qr_xor(s$logical_bytes)); symbol_bytes <- symbol_bytes + length(s$logical_bytes) }
      if (!symbol_bytes) .qr_fail("Structured Append symbols must have nonempty data")
      nb <- nb + symbol_bytes
    }
    if (actual != parity) .qr_fail("Inconsistent Structured Append payload parity")
    .qr_integer(x[["byte_length"]], "byte_length", nb, nb)
    .qr_integer(x[["input_length"]], "input_length", 1, 1000000)
    .qr_integer(d[["total"]], "total", total, total); .qr_integer(d[["parity"]], "parity", parity, parity)
    .qr_integer(d[["byte_length"]], "byte_length", nb, nb)
    .qr_integer(d[["input_length"]], "input_length", x[["input_length"]], x[["input_length"]])
  } else {
    data <- .qr_input(x[["data"]]); actual <- calculate_structured_append_parity(data)
    if (actual != parity) .qr_fail("Inconsistent merged parity")
    kind <- if (is.raw(data)) "binary" else "string"; nb <- if (is.raw(data)) length(data) else nchar(data, type = "bytes")
    parts <- x[["parts"]]
    if (!is.list(parts) || is.object(parts) || !is.null(dim(parts)) || length(parts) != total) .qr_fail("Malformed merged parts")
    lengths <- numeric(total)
    for (i in seq_len(total)) {
      info <- .qr_mapping(parts[[i]], "part metadata")
      if (!setequal(names(info), c("index", "total", "parity", "data_type", "byte_length"))) .qr_fail("Malformed merged part metadata")
      .qr_integer(info[["index"]], "index", i, i); .qr_integer(info[["total"]], "total", total, total)
      .qr_integer(info[["parity"]], "parity", parity, parity)
      scalar_text(info[["data_type"]], "data_type")
      if (info[["data_type"]] != kind) .qr_fail("Inconsistent merged part data type")
      lengths[i] <- .qr_integer(info[["byte_length"]], "byte_length", 0, nb)
    }
    if (sum(lengths) != nb) .qr_fail("Inconsistent merged part byte lengths")
    if (kind == "string" && !all(cumsum(lengths) %in% .qr_offsets(utf8ToInt(data)))) .qr_fail("Merged text part boundaries split a Unicode scalar")
    if (!setequal(names(d), c("part_count", "total", "parity", "data_type", "byte_length", "missing", "duplicate", "parity_check"))) .qr_fail("Malformed merge diagnostics")
    .qr_integer(d[["part_count"]], "part_count", total, total); .qr_integer(d[["total"]], "total", total, total)
    .qr_integer(d[["parity"]], "parity", parity, parity); .qr_integer(d[["byte_length"]], "byte_length", nb, nb)
    scalar_text(d[["data_type"]], "data_type")
    if (d[["data_type"]] != kind || !is.integer(d[["missing"]]) || length(d[["missing"]]) || !is.integer(d[["duplicate"]]) || length(d[["duplicate"]])) .qr_fail("Inconsistent merge diagnostics")
    check <- .qr_mapping(d[["parity_check"]], "parity_check")
    if (!setequal(names(check), c("expected", "actual", "matches"))) .qr_fail("Malformed parity diagnostics")
    .qr_integer(check[["expected"]], "expected", parity, parity); .qr_integer(check[["actual"]], "actual", actual, actual)
    if (!identical(check[["matches"]], TRUE)) .qr_fail("Inconsistent parity verification result")
  }
  invisible(x)
}
print.specqr_sa_result <- function(x, ...) { .qr_validate_sa_result(x); cat("SpecQR Structured Append: ", x$total, " symbols, parity ", x$parity, "\n", sep = ""); invisible(x) }
print.specqr_merge_result <- function(x, ...) { .qr_validate_sa_result(x); cat("SpecQR merged ", x$total, " parts, parity verified\n", sep = ""); invisible(x) }

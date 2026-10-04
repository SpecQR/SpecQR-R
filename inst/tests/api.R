# Base-R API, exact optimizer, and Structured Append regression tests.
if (!exists("generate", mode = "function")) {
  root <- if (dir.exists("R")) "." else if (dir.exists("../R")) ".." else "specqr-r-work/SpecQR-R"
  for (f in sort(list.files(file.path(root, "R"), pattern = "[.]R$", full.names = TRUE))) source(f)
}
.api_checks <- 0L
.api_check <- function(value) { .api_checks <<- .api_checks + 1L; if (!isTRUE(value)) stop("API check failed: ", .api_checks) }
.api_error <- function(expr, code = "INVALID_INPUT") {
  err <- tryCatch({ force(expr); NULL }, error = identity)
  .api_check(inherits(err, "specqr_error") && identical(err$code, code))
}
# Independent O(n^2) shortest-path oracle used only for small test strings.
.oracle <- function(text, version, allow_kanji) {
  chars <- strsplit(text, "", fixed = TRUE)[[1L]]; n <- length(chars)
  if (!n) return(4 + character_count_bits(version, "byte"))
  cost <- rep(Inf, n + 1L); cost[1L] <- 0
  for (end in seq_len(n)) for (start in seq_len(end)) {
    value <- paste0(chars[seq.int(start, end)], collapse = ""); cp <- utf8ToInt(value)
    for (m in c("numeric", "alphanumeric", if (allow_kanji) "kanji", "byte")) {
      eligible <- switch(m, numeric = all(cp >= 48L & cp <= 57L), alphanumeric = all(cp %in% utf8ToInt("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")),
                         kanji = all(vapply(chars[seq.int(start, end)], can_encode_kanji, logical(1))), byte = TRUE)
      if (!eligible) next
      nb <- nchar(value, type = "bytes"); count <- if (m == "byte") nb else end - start + 1L
      width <- character_count_bits(version, m)
      if (count >= 2^width) next
      bits <- switch(m, numeric = (count %/% 3L) * 10L + c(0L, 4L, 7L)[count %% 3L + 1L], alphanumeric = (count %/% 2L) * 11L + count %% 2L * 6L, kanji = count * 13L, byte = count * 8L)
      cost[end + 1L] <- min(cost[end + 1L], cost[start] + 4L + width + bits)
    }
  }
  cost[n + 1L]
}
set.seed(421L)
for (v in c(1L, 9L, 10L, 26L, 27L, 40L)) for (allow in c(FALSE, TRUE)) {
  samples <- c("", "1234567890ABCxyz", "漢字漢A12345😀é", "A%\035\035B", replicate(7L, paste0(sample(c("A", "5", "9", "z", "漢", "é", "😀", "%"), 15L, replace = TRUE), collapse = "")))
  for (text in samples) {
    ss <- optimize_segments(text, version = v, allow_kanji = allow)
    .api_check(segments_bit_length(ss, v) == .oracle(text, v, allow))
    .api_check(identical(paste0(vapply(ss, function(s) s$data, character(1)), collapse = ""), text))
  }
}
for (n in c(254L, 255L, 256L, 510L, 511L, 512L)) {
  ss <- optimize_segments(strrep("a", n), version = 1L)
  .api_check(all(vapply(ss, function(s) s$count <= 255L, logical(1))))
  .api_check(segments_bit_length(ss, 1) == 8L * n + ceiling(n / 255L) * 12L)
}
for (n in c(1023L, 1024L, 2047L)) {
  ss <- optimize_segments(strrep("1", n), version = 1L)
  .api_check(all(vapply(ss, function(s) s$count <= 1023L, logical(1))))
}
.api_error(optimize_segments(strrep("a", 7090)), "DATA_TOO_LONG")
.api_error(optimize_segments(c("a", "b")))
.api_error(optimize_segments("a", allow_kanji = NA))
.api_error(generate(1:3)); .api_error(generate(c("a", "b"))); .api_error(generate(NA_character_))
.api_error(generate(matrix("a", 1, 1))); .api_error(generate(factor("a")))
.api_error(generate(raw(1), mode = "numeric"), "INVALID_MODE")
.api_error(specqr_options(version = TRUE), "INVALID_VERSION")
.api_error(specqr_options(min_version = 10, max_version = 9), "INVALID_VERSION")
.api_error(specqr_options(mask_pattern = c(0, 1))); .api_error(specqr_options(scale = Inf))
.api_error(specqr_options(scale = matrix(1, 1, 1))); .api_error(specqr_options(allow_kanji = 1))
.api_error(specqr_options(eci = NA), "INVALID_ECI"); .api_error(specqr_options(eci = -1), "INVALID_ECI")
.api_error(specqr_options(unknown = TRUE)); .api_error(do.call(specqr_options, list(scale = 1, scale = 2)))
.api_error(specqr_options(print_dpi = 0)); .api_error(specqr_options(print_dpi = .Machine$double.xmin))
.api_error(specqr_options(fnc1 = TRUE, eci = 26), "INVALID_MODE")
opts <- specqr_options(); opts$scale <- NA_real_; .api_error(generate("a", opts))
opts <- specqr_options(); opts$extra <- 1L; .api_error(generate("a", opts))
opts <- specqr_options(); opts$version <- c(1, 2); .api_error(generate("a", opts), "INVALID_VERSION")
.api_check(get_capacity(1, "L", mode = "numeric")$maximum == 41L)
.api_check(get_capacity(1, "L", mode = "byte")$maximum == 17L)
.api_check(get_capacity(1, "L", mode = "alphanumeric")$maximum == 25L)
.api_check(get_capacity(1, "L", mode = "kanji")$maximum == 10L)
.api_check(get_capacity(40, "L", mode = "numeric")$maximum == 7089L)
.api_check(get_capacity(1, "L", mode = "byte", control_bits = 1000)$maximum == 0L)
.api_error(get_capacity(0), "INVALID_VERSION"); .api_error(get_capacity(1, mode = "auto"), "INVALID_MODE")
p <- plan("12345")
.api_check(p$ok && p$version == 1L && p$data_bit_length == 31L)
.api_check(!p$diagnostics$mask_evaluated && !p$diagnostics$codewords_built && !p$diagnostics$render_planned)
.api_check(plan("A", boost_error_correction = TRUE)$error_correction_level == "H")
p <- plan(strrep("a", 9000), max_version = 1)
.api_check(!p$ok && is.null(p$version) && p$overflow_bits > 0L)
.api_check(!plan(strrep("a", 9000), version = 1)$ok)
.api_error(generate(strrep("a", 9000), version = 1), "DATA_TOO_LONG")
p <- plan("a"); p$data_bit_length <- 0; .api_error(diagnostics(p))
q <- generate("HELLO WORLD", version = 1, mask_pattern = 0)
.api_check(inherits(q, "specqr_result") && is.logical(q$matrix) && identical(dim(q$matrix), c(21L, 21L)))
.api_check(identical(module_at(q, 1, 1), q$matrix[1L, 1L]))
.api_check(diagnostics(q)$mask_evaluated && diagnostics(q)$codewords_built)
.api_error(module_at(q, 0, 1)); .api_error(module_at(q, 1, TRUE))
qbad <- q; qbad$matrix[1, 1] <- NA; .api_error(module_at(qbad, 1, 1))
qbad <- q; qbad$options$scale <- Inf; .api_error(diagnostics(qbad))
# High-level FNC1 text has logical separators and literal percent; it is never
# blindly rewritten to QR alphanumeric escapes, which would collapse two GSs.
for (text in c("A%B", "A%%B", "A\035\035B", "123\035456", "A%\035\035B")) {
  q <- generate(text, fnc1 = TRUE, mask_pattern = 0)
  ss <- Filter(function(s) !s$is_control, q$segments)
  .api_check(identical(do.call(c, lapply(ss, function(s) s$logical_bytes)), charToRaw(text)))
  if (grepl("%", text, fixed = TRUE)) .api_check(length(ss) == 1L && ss[[1L]]$mode == "byte")
}
.api_error(generate("A%B", fnc1 = TRUE, mode = "alphanumeric"), "INVALID_MODE")
.api_check(plan_segments(list(fnc1(), alphanumeric_segment("A%%B")))$ok)
# Finite print diagnostics and warning aggregation.
p <- plan("a", margin = 0, scale = 1, print_dpi = 300)
.api_check(is.finite(p$diagnostics$print$symbol_size_mm))
.api_check(all(c("QUIET_ZONE_TOO_SMALL", "PRINT_MODULE_TOO_SMALL", "SCAN_RISK") %in% vapply(p$warnings, function(w) w$code, character(1))))
# Text/raw parity and reverse-order merging.
.api_check(calculate_structured_append_parity("ABC") == bitwXor(bitwXor(65L, 66L), 67L))
text <- paste0(strrep("漢", 8), strrep("é😀", 12), "ABC")
sa <- generate_structured_append(text, version = 1, mode = "byte", mask_pattern = 0)
.api_check(sa$total >= 2L && sa$total <= 16L)
parts <- lapply(sa$symbols, function(q) list(index = q$segments[[1L]]$index, total = sa$total, parity = sa$parity,
  data = paste0(vapply(q$segments[-1L], function(s) s$data, character(1)), collapse = "")))
merged <- merge_structured_append_parts(rev(parts))
.api_check(identical(merged$data, text)); .api_check(diagnostics(merged)$parity_check$matches)
.api_check(all(vapply(sa$symbols, function(q) q$version == 1L && q$segments[[1L]]$mode == "structured-append", logical(1))))
binary <- as.raw(rep(0:255, 1))
sa <- generate_structured_append(binary, version = 2, mask_pattern = 1)
parts <- lapply(sa$symbols, function(q) list(index = q$segments[[1L]]$index, total = sa$total, parity = sa$parity, data = q$segments[[2L]]$data))
.api_check(identical(merge_structured_append_parts(rev(parts))$data, binary))
.api_error(merge_structured_append_parts(parts[-1L])); .api_error(merge_structured_append_parts(c(parts[-1L], parts[2L])))
bad <- parts; bad[[1L]]$parity <- (bad[[1L]]$parity + 1L) %% 256L; .api_error(merge_structured_append_parts(bad))
bad <- parts; bad[[1L]]$data <- "a"; .api_error(merge_structured_append_parts(bad))
.api_error(generate_structured_append("a", version = 1))
.api_error(generate_structured_append("", version = 1))
.api_error(generate_structured_append(strrep("a", 1000), version = 1, max_symbols = 2), "DATA_TOO_LONG")
.api_error(generate_structured_append("ABC", eci = 0), "INVALID_MODE")
.api_error(generate_structured_append("ABC", gs1 = TRUE), "INVALID_GS1")
.api_error(generate_structured_append("ABC", boost_error_correction = TRUE), "INVALID_MODE")
.api_error(generate_structured_append("ABC", max_symbols = 1), "INVALID_MODE")
.api_error(generate_structured_append("ABC", diagnostics = NA))
.api_error(generate_structured_append("ABC", parity = 0), "INVALID_MODE")
manual <- list(numeric_segment(strrep("1", 20)), byte_segment(strrep("é", 12)), alphanumeric_segment(strrep("A", 12)))
sa <- generate_segments_structured_append(manual, version = 1, mask_pattern = 0, diagnostics = list(split_units = "full"))
.api_check(sa$diagnostics$segment_count == 3L && length(sa$diagnostics$split_units) == 14L)
.api_check(sa$parity == calculate_structured_append_segments_parity(manual))
.api_check(identical(do.call(c, lapply(sa$symbols, function(q) do.call(c, lapply(q$segments[-1L], function(s) s$logical_bytes)))), do.call(c, lapply(manual, function(s) s$logical_bytes))))
.api_error(generate_segments_structured_append(list(numeric_segment(strrep("1", 100))), version = 1), "DATA_TOO_LONG")
.api_error(generate_segments_structured_append(manual, mode = "byte"), "INVALID_MODE")
.api_error(calculate_structured_append_segments_parity(list(fnc1(), byte_segment("a"))), "INVALID_GS1")
.api_error(calculate_structured_append_segments_parity(list(byte_segment(""))))
.api_check(inherits(generate_segments(list(), mask_pattern = 0), "specqr_result"))
qbad <- q; qbad$diagnostics$print$symbol_size_mm <- Inf; .api_error(diagnostics(qbad))
pbad <- plan("a"); pbad$ok <- FALSE; .api_error(diagnostics(pbad))
pbad <- plan("a"); pbad$options <- NULL; .api_error(diagnostics(pbad))
capbad <- get_capacity(1); capbad$capacity_bits <- Inf; .api_error(print(capbad))
# Stored R language values are data, never code. Exercise the library's own
# reconstruction, rather than a caller-side do.call that evaluates first.
.api_language_ran <- FALSE
.api_language <- quote({ .api_language_ran <<- TRUE; 1 })
for (field in c("version", "scale", "print_dpi", "eci")) {
  bad_options <- specqr_options(); bad_options[field] <- list(.api_language)
  expected_code <- if (field == "version") "INVALID_VERSION" else if (field == "eci") "INVALID_ECI" else "INVALID_INPUT"
  .api_error(generate("A", bad_options), expected_code)
  .api_check(!.api_language_ran)
}
.api_error(generate("A", version = .api_language), "INVALID_VERSION")
.api_check(!.api_language_ran)
bad_options <- specqr_options(); bad_options$version <- quote(.api_language_symbol)
makeActiveBinding(".api_language_symbol", function() { .api_language_ran <<- TRUE; 1 }, .GlobalEnv)
.api_error(generate("A", bad_options), "INVALID_VERSION")
.api_check(!.api_language_ran)
.api_error(generate("A", version = quote(.api_language_symbol)), "INVALID_VERSION")
.api_check(!.api_language_ran)
rm(".api_language_symbol", envir = .GlobalEnv)
bad_options <- specqr_options(); bad_options$version <- .api_language
.api_error(generate_structured_append(strrep("a", 30), bad_options), "INVALID_VERSION")
.api_check(!.api_language_ran)
.api_error(generate_segments_structured_append(list(byte_segment(strrep("a", 30))), bad_options), "INVALID_VERSION")
.api_check(!.api_language_ran)
.api_error(generate_structured_append(strrep("a", 30), version = .api_language), "INVALID_VERSION")
.api_check(!.api_language_ran)
# Exact decoded mapping keys; decoder envelopes may retain harmless extras.
.api_pair <- list(list(index = 1, total = 2, parity = 3, data = "a"), list(index = 2, total = 2, parity = 3, data = "b"))
for (field in c("index", "total", "parity", "data")) {
  malformed <- .api_pair; names(malformed[[1L]])[names(malformed[[1L]]) == field] <- paste0(field, "suffix")
  .api_error(merge_structured_append_parts(malformed))
}
envelope <- .api_pair; envelope[[1L]]$decoder_note <- "kept outside merged payload"
.api_check(identical(merge_structured_append_parts(envelope)$data, "ab"))
shaped <- .api_pair; dim(shaped) <- c(1L, 2L); .api_error(merge_structured_append_parts(shaped))
shaped <- .api_pair; dim(shaped[[1L]]) <- c(2L, 2L); .api_error(merge_structured_append_parts(shaped))
shaped <- specqr_options(); dim(shaped) <- c(1L, length(shaped)); .api_error(generate("a", shaped))
merged <- merge_structured_append_parts(.api_pair)
for (field in c("index", "total", "parity", "byte_length")) {
  malformed <- merged; malformed$parts[[1L]][field] <- list(99L); .api_error(print(malformed))
}
malformed <- merged; malformed$parts[[1L]]$data_type <- "binary"; .api_error(diagnostics(malformed))
malformed <- merged; malformed$diagnostics$parity_check$matches <- FALSE; .api_error(print(malformed))
malformed <- merged; malformed$diagnostics$parity_check$actual <- 99L; .api_error(diagnostics(malformed))
malformed <- merged; malformed$diagnostics$total <- 3L; .api_error(diagnostics(malformed))
malformed <- merged; names(malformed)[names(malformed) == "total"] <- "totals"; .api_error(print(malformed))
malformed <- merged; names(malformed$parts[[1L]])[1L] <- "indexed"; .api_error(diagnostics(malformed))
empty_parts <- list(list(index = 1, total = 2, parity = 0, data = ""), list(index = 2, total = 2, parity = 0, data = ""))
.api_check(diagnostics(merge_structured_append_parts(empty_parts))$parity_check$matches)
malformed <- plan("a"); names(malformed$diagnostics)[names(malformed$diagnostics) == "data_bit_length"] <- "data_bit_lengths"; .api_error(diagnostics(malformed))
# Compact shared subtrees cannot cause exponential validation work.
shared <- 0L
for (i in seq_len(12L)) shared <- rep(list(shared), 8L)
malformed <- plan("a"); malformed$diagnostics$extra <- shared
.api_error(diagnostics(malformed))
malformed <- generate("a", mask_pattern = 0); malformed$diagnostics$extra <- shared
.api_error(print(malformed))
.api_error(to_svg(malformed))
cat("API, optimizer, and Structured Append checks:", .api_checks, "passed\n")

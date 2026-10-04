# Bounded offline GS1 helpers. This intentionally supports only the SpecQR AI catalog.
GS1_FNC1_SEPARATOR <- "\x1d"
GS1_MAX_INPUT_CHARACTERS <- 1000000L
GS1_MAX_ELEMENTS <- 16384L
.gs1_primary_ais <- c("00", "01", "414")
.gs1_fail <- function(message, code = "GS1_INVALID_INPUT") specqr_abort(message, "INVALID_GS1", code)
.gs1_text <- function(value, label = "GS1 text") {
  if (!is.character(value) || is.object(value) || length(value) != 1L || !is.null(dim(value)) || is.na(value)) .gs1_fail(paste(label, "must be one non-missing string"))
  if (Encoding(value) == "bytes") .gs1_fail(paste(label, "must be Unicode text, not a bytes-tagged string"))
  value <- enc2utf8(value)
  if (nchar(value, type = "bytes") > 4 * GS1_MAX_INPUT_CHARACTERS || !validUTF8(value)) .gs1_fail(paste(label, "must be valid UTF-8 within the input budget"))
  if (sum(1 + (utf8ToInt(enc2utf8(value)) > 65535L)) > GS1_MAX_INPUT_CHARACTERS) .gs1_fail(paste(label, "exceeds the character work budget"))
  enc2utf8(value)
}
.gs1_digits <- function(s) is.character(s) && length(s) == 1L && !is.na(s) && grepl("^[0-9]+$", s)
.gs1_is_ai <- function(s) .gs1_digits(s) && nchar(s, type = "bytes") %in% 2:4
.gs1_eligible <- function(ai, primary) primary == "01" && ai %in% c("10", "21", "22")
GS1Element <- function(ai, value) list(ai = .gs1_text(ai, "GS1 AI"), value = .gs1_text(value, "GS1 value"))
.gs1_numeric <- function(value, label) {
  s <- .gs1_text(value, label)
  if (!.gs1_digits(s)) .gs1_fail(paste(label, "must contain digits only"), "GS1_INVALID_CHARSET")
  s
}
calculate_gs1_check_digit <- function(value) {
  s <- .gs1_numeric(value, "GS1 check digit input"); digits <- rev(as.integer(charToRaw(s)) - 48L)
  as.character((-sum(digits * rep(c(3L, 1L), length.out = length(digits)))) %% 10)
}
validate_gs1_check_digit <- function(value) {
  s <- .gs1_numeric(value, "GS1 check digit value"); n <- nchar(s)
  if (n < 2L) .gs1_fail("GS1 check digit value must include body and check digit", "GS1_INVALID_LENGTH")
  calculate_gs1_check_digit(substr(s, 1L, n - 1L)) == substr(s, n, n)
}
calculate_gtin_check_digit <- function(value) {
  s <- .gs1_numeric(value, "GTIN body")
  if (!nchar(s) %in% c(7L, 11L, 12L, 13L)) .gs1_fail("GTIN body must be 7, 11, 12, or 13 digits", "GS1_INVALID_LENGTH")
  calculate_gs1_check_digit(s)
}
append_gtin_check_digit <- function(value) paste0(.gs1_text(value, "GTIN body"), calculate_gtin_check_digit(value))
validate_gtin_check_digit <- function(value) {
  s <- .gs1_numeric(value, "GTIN")
  if (!nchar(s) %in% c(8L, 12L, 13L, 14L)) .gs1_fail("GTIN must be 8, 12, 13, or 14 digits", "GS1_INVALID_LENGTH")
  validate_gs1_check_digit(s)
}
calculate_sscc_check_digit <- function(value) {
  s <- .gs1_numeric(value, "SSCC body")
  if (nchar(s) != 17L) .gs1_fail("SSCC body must be exactly 17 digits", "GS1_INVALID_LENGTH")
  calculate_gs1_check_digit(s)
}
append_sscc_check_digit <- function(value) paste0(.gs1_text(value, "SSCC body"), calculate_sscc_check_digit(value))
validate_sscc_check_digit <- function(value) {
  s <- .gs1_numeric(value, "SSCC")
  if (nchar(s) != 18L) .gs1_fail("SSCC must be exactly 18 digits", "GS1_INVALID_LENGTH")
  validate_gs1_check_digit(s)
}
.gs1_fields <- function(element) {
  if (!is.list(element) || is.data.frame(element) || anyDuplicated(names(element)) || is.null(element[["ai"]]) || is.null(element[["value"]])) .gs1_fail("GS1 elements must have string ai and value fields")
  list(element[["ai"]], element[["value"]])
}
.gs1_bounded <- function(values, path_ais = FALSE) {
  if (is.list(values) && !is.null(values[["elements"]])) values <- values[["elements"]]
  if ((!is.list(values) && !(path_ais && is.character(values))) || is.data.frame(values) || !is.null(dim(values))) .gs1_fail("GS1 elements must be a list of elements")
  if (length(values) > GS1_MAX_ELEMENTS) .gs1_fail("GS1 element count exceeds limit")
  work <- 0
  for (value in values) {
    fields <- if (path_ais) list(value) else if (is.list(value)) list(value[["ai"]], value[["value"]]) else list()
    for (field in fields) if (is.character(field)) {
      if (anyNA(field)) next
      work <- work + sum(nchar(field, type = "bytes"))
      if (work > GS1_MAX_INPUT_CHARACTERS) .gs1_fail("GS1 aggregate text exceeds input budget")
    }
  }
  values
}
.gs1_element <- function(raw, index = 0L) {
  fields <- .gs1_fields(raw); ai <- .gs1_text(fields[[1L]], paste("GS1 element", index, "AI")); value <- .gs1_text(fields[[2L]], paste("GS1 element", index, "value"))
  if (!.gs1_is_ai(ai)) .gs1_fail(paste("GS1 element", index, "AI must be a 2 to 4 digit string"))
  info <- get_gs1_ai_info(ai)
  if (is.null(info)) .gs1_fail(paste("Unsupported GS1 AI", ai), "GS1_UNSUPPORTED_AI")
  prefix <- paste("GS1 AI", ai, "value")
  if (!nzchar(value)) .gs1_fail(paste(prefix, "must not be empty"), "GS1_INVALID_LENGTH")
  if (grepl(GS1_FNC1_SEPARATOR, value, fixed = TRUE)) .gs1_fail(paste(prefix, "must not contain the FNC1 separator"), "GS1_UNEXPECTED_SEPARATOR")
  if (grepl("[()]", value)) .gs1_fail(paste(prefix, "must be raw data without human-readable parentheses"))
  if (any(as.integer(charToRaw(value)) < 32L | as.integer(charToRaw(value)) > 126L)) .gs1_fail(paste(prefix, "must use printable ASCII characters"), "GS1_INVALID_CHARSET")
  if (info$value_kind == "numeric" && !.gs1_digits(value)) .gs1_fail(paste(prefix, "must contain digits only"), "GS1_INVALID_CHARSET")
  if (info$length$is_variable) {
    if (nchar(value) > info$length$max) .gs1_fail(paste(prefix, "must be at most", info$length$max, "characters"), "GS1_INVALID_LENGTH")
  } else if (nchar(value) != info$length$exact) .gs1_fail(paste(prefix, "must be exactly", info$length$exact, "characters"), "GS1_INVALID_LENGTH")
  if (info$check_digit_rule == "gtin" && !validate_gtin_check_digit(value)) .gs1_fail(paste(prefix, "has an invalid GTIN check digit"), "GS1_INVALID_CHECK_DIGIT")
  if (info$check_digit_rule == "sscc" && !validate_sscc_check_digit(value)) .gs1_fail(paste(prefix, "has an invalid SSCC check digit"), "GS1_INVALID_CHECK_DIGIT")
  list(ai = ai, value = value)
}
.gs1_elements <- function(values) {
  values <- .gs1_bounded(values)
  if (!length(values)) .gs1_fail("GS1 elements must not be empty")
  lapply(seq_along(values), function(i) .gs1_element(values[[i]], i - 1L))
}
.gs1_ascii_input <- function(value, label) {
  s <- .gs1_text(value, label)
  if (any(as.integer(charToRaw(s)) > 127L)) .gs1_fail(paste(label, "must use ASCII characters"), "GS1_INVALID_CHARSET")
  if (!nzchar(s)) .gs1_fail(paste(label, "must not be empty"))
  s
}
parse_gs1_human_readable <- function(value) {
  s <- .gs1_ascii_input(value, "GS1 human-readable input"); out <- list(); p <- 1L; n <- nchar(s)
  while (p <= n) {
    if (length(out) >= GS1_MAX_ELEMENTS) .gs1_fail("GS1 element count exceeds limit")
    if (substr(s, p, p) != "(") .gs1_fail(paste("GS1 AI must be parenthesized at offset", p - 1L))
    q <- regexpr(")", substring(s, p + 1L), fixed = TRUE)[1L]
    if (q < 0L) .gs1_fail(paste("GS1 AI is missing closing parenthesis at offset", p - 1L))
    q <- q + p
    stop <- regexpr("(", substring(s, q + 1L), fixed = TRUE)[1L]; stop <- if (stop < 0L) n + 1L else stop + q
    out[[length(out) + 1L]] <- .gs1_element(list(ai = substr(s, p + 1L, q - 1L), value = substr(s, q + 1L, stop - 1L)), length(out))
    p <- stop
  }
  out
}
.gs1_read_ai <- function(s, p) {
  for (n in c(4L, 3L, 2L)) if (p + n - 1L <= nchar(s)) {
    info <- get_gs1_ai_info(substr(s, p, p + n - 1L))
    if (!is.null(info)) return(info)
  }
  NULL
}
parse_gs1_element_string <- function(value) {
  s <- .gs1_ascii_input(value, "GS1 element string")
  if (grepl("[()]", s)) .gs1_fail("GS1 element string must be raw data without parentheses")
  out <- list(); p <- 1L; n <- nchar(s)
  while (p <= n) {
    if (length(out) >= GS1_MAX_ELEMENTS) .gs1_fail("GS1 element count exceeds limit")
    if (substr(s, p, p) == GS1_FNC1_SEPARATOR) .gs1_fail(paste("Unexpected FNC1 separator at offset", p - 1L), "GS1_UNEXPECTED_SEPARATOR")
    info <- .gs1_read_ai(s, p)
    if (is.null(info)) .gs1_fail(paste("Unsupported GS1 AI at offset", p - 1L), "GS1_UNSUPPORTED_AI")
    start <- p + nchar(info$ai)
    if (info$length$is_variable) {
      stop <- regexpr(GS1_FNC1_SEPARATOR, substring(s, start), fixed = TRUE)[1L]
      stop <- if (stop < 0L) n + 1L else stop + start - 1L
    } else stop <- min(n + 1L, start + info$length$exact)
    if (info$length$is_variable && stop == n + 1L && start + 1L <= stop - 1L) {
      for (off in seq.int(max(start + 1L, stop - 22L), stop - 1L)) {
        tail <- .gs1_read_ai(s, off)
        if (!is.null(tail) && !tail$length$is_variable && off + nchar(tail$ai) + tail$length$exact == stop)
          .gs1_fail(paste("GS1 variable field is missing an FNC1 separator before offset", off - 1L), "GS1_MISSING_SEPARATOR")
      }
    }
    out[[length(out) + 1L]] <- .gs1_element(list(ai = info$ai, value = substr(s, start, stop - 1L)), length(out))
    p <- stop
    if (info$length$is_variable && p <= n) {
      p <- p + 1L
      if (p > n) .gs1_fail("GS1 element string must not end with an FNC1 separator", "GS1_UNEXPECTED_SEPARATOR")
    }
  }
  list(elements = out, has_separators = grepl(GS1_FNC1_SEPARATOR, s, fixed = TRUE))
}
create_gs1_element_string <- function(elements) {
  values <- .gs1_elements(elements)
  pieces <- vapply(seq_along(values), function(i) { e <- values[[i]]; paste0(e$ai, e$value, if (i < length(values) && get_gs1_ai_info(e$ai)$length$is_variable) GS1_FNC1_SEPARATOR else "") }, "")
  .gs1_text(paste0(pieces, collapse = ""), "GS1 output")
}
gs1_to_human_readable <- function(elements) {
  values <- .gs1_elements(elements)
  .gs1_text(paste0(vapply(values, function(e) paste0("(", e$ai, ")", e$value), ""), collapse = ""), "GS1 output")
}
normalize_gs1_elements <- function(value) {
  if (is.character(value)) { s <- .gs1_text(value); if (startsWith(s, "(")) parse_gs1_human_readable(s) else parse_gs1_element_string(s)$elements } else .gs1_elements(value)
}
gs1_element_string_to_human_readable <- function(value) gs1_to_human_readable(parse_gs1_element_string(value)$elements)
.gs1_issue <- function(error, element = NULL, element_index = NULL) {
  code <- error$detail_code
  reasons <- c(GS1_UNSUPPORTED_AI = "unsupported-ai", GS1_INVALID_LENGTH = "invalid-length", GS1_INVALID_CHARSET = "invalid-charset", GS1_MISSING_SEPARATOR = "missing-separator", GS1_UNEXPECTED_SEPARATOR = "unexpected-separator", GS1_INVALID_CHECK_DIGIT = "invalid-check-digit", GS1_INVALID_PERCENT_ENCODING = "invalid-percent-encoding", GS1_INVALID_DIGITAL_LINK_PLACEMENT = "invalid-digital-link-placement", GS1_DUPLICATE_AI = "duplicate-ai", GS1_DIGITAL_LINK_UNKNOWN_QUERY = "unknown-query", GS1_DIGITAL_LINK_UNSUPPORTED_HOST = "unsupported-host", GS1_DIGITAL_LINK_INVALID_URI = "invalid-uri", GS1_DIGITAL_LINK_FRAGMENT_NOT_ALLOWED = "fragment-not-allowed")
  reason <- if (code %in% names(reasons)) unname(reasons[[code]]) else "invalid-input"
  ai <- value <- NULL
  if (is.list(element)) {
    if (is.character(element$ai) && length(element$ai) == 1L && !is.na(element$ai) && nchar(element$ai, type = "bytes") <= 4L && validUTF8(element$ai)) ai <- element$ai
    if (is.character(element$value) && length(element$value) == 1L && !is.na(element$value) && nchar(element$value, type = "bytes") <= 90L && validUTF8(element$value)) value <- element$value
  }
  if (is.null(ai)) { m <- regmatches(error$message, regexec("GS1 AI ([0-9]{2,4})", error$message))[[1L]]; if (length(m)) ai <- m[2L] }
  m <- regmatches(error$message, regexec("offset ([0-9]+)", error$message))[[1L]]
  list(code = code, message = error$message, reason = reason, ai = ai, value = value, key = NULL, offset = if (length(m)) as.integer(m[2L]) else NULL, element_index = element_index,
       expected = if (code == "GS1_DIGITAL_LINK_UNSUPPORTED_HOST") "ASCII DNS name, canonical dotted IPv4, or RFC IPv6" else NULL, count = NULL)
}
.gs1_catch <- function(e, digital = FALSE) {
  if (!inherits(e, "specqr_invalid_gs1")) stop(e)
  if (digital) list(ok = FALSE, result = NULL, errors = list(.gs1_issue(e)), warnings = list()) else list(ok = FALSE, elements = NULL, has_separators = NULL, errors = list(.gs1_issue(e)), warnings = list())
}
.gs1_validation_options <- function(context, collect_all_errors, allow_unsupported_ai) {
  if (!is.character(context) || is.object(context) || !is.null(dim(context)) || length(context) != 1L || is.na(context) || !context %in% c("element-string", "digital-link")) .gs1_fail("GS1 validation context must be element-string or digital-link")
  if (!is.logical(collect_all_errors) || length(collect_all_errors) != 1L || is.na(collect_all_errors) || is.object(collect_all_errors) || !is.null(dim(collect_all_errors))) .gs1_fail("GS1 collect_all_errors must be a boolean")
  if (!identical(allow_unsupported_ai, FALSE)) .gs1_fail("GS1 allow_unsupported_ai must be FALSE")
}
validate_gs1_elements <- function(elements, context = "element-string", collect_all_errors = TRUE, allow_unsupported_ai = FALSE) {
  tryCatch({
    .gs1_validation_options(context, collect_all_errors, allow_unsupported_ai); values <- .gs1_bounded(elements)
    if (!length(values)) .gs1_fail("GS1 elements must not be empty")
    errors <- normalized <- list()
    for (i in seq_along(values)) {
      e <- tryCatch(.gs1_element(values[[i]], i - 1L), error = function(err) { if (!inherits(err, "specqr_invalid_gs1")) stop(err); err })
      if (inherits(e, "specqr_error")) { errors[[length(errors) + 1L]] <- .gs1_issue(e, values[[i]], i - 1L); if (!collect_all_errors) break } else normalized[[length(normalized) + 1L]] <- e
    }
    if (!length(errors) && context == "digital-link" && !any(vapply(normalized, function(e) e$ai %in% .gs1_primary_ais, FALSE))) .gs1_fail("GS1 Digital Link requires primary AI 00, 01, or 414", "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
    list(ok = !length(errors), elements = if (!length(errors)) normalized else NULL, has_separators = NULL, errors = errors, warnings = list())
  }, error = .gs1_catch)
}
validate_gs1_element_string <- function(value, context = "element-string", collect_all_errors = TRUE, allow_unsupported_ai = FALSE) {
  tryCatch({
    .gs1_validation_options(context, collect_all_errors, allow_unsupported_ai); parsed <- parse_gs1_element_string(value)
    result <- validate_gs1_elements(parsed$elements, context, collect_all_errors, allow_unsupported_ai); result$has_separators <- parsed$has_separators; result
  }, error = .gs1_catch)
}
# URI handling is a strict, bounded offline profile, not WHATWG URL parsing.
.gs1_percent_fail <- function() .gs1_fail("GS1 URI must use valid percent-encoding and UTF-8 without NUL", "GS1_INVALID_PERCENT_ENCODING")
.gs1_decode <- function(value, form = FALSE) {
  bytes <- as.integer(charToRaw(value)); n <- length(bytes); out <- raw(n); i <- 1L; p <- 0L
  while (i <= n) {
    b <- bytes[i]
    if (b == 37L) {
      if (i + 2L > n) .gs1_percent_fail()
      h <- rawToChar(as.raw(bytes[(i + 1L):(i + 2L)]))
      if (!grepl("^[0-9A-Fa-f]{2}$", h)) .gs1_percent_fail()
      b <- strtoi(h, 16L); i <- i + 3L
    } else { if (form && b == 43L) b <- 32L; i <- i + 1L }
    if (b == 0L) .gs1_percent_fail()
    p <- p + 1L; out[p] <- as.raw(b)
  }
  s <- rawToChar(out[seq_len(p)]); if (!validUTF8(s)) .gs1_percent_fail(); Encoding(s) <- "UTF-8"; s
}
.gs1_encode <- function(value, form = FALSE) {
  bytes <- as.integer(charToRaw(enc2utf8(value)))
  safe <- bytes %in% as.integer(charToRaw(paste0("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*-._", if (!form) "~!'()" else "")))
  out <- sprintf("%%%02X", bytes); out[safe] <- rawToChar(as.raw(bytes[safe]), multiple = TRUE)
  if (form) out[bytes == 32L] <- "+"
  paste0(out, collapse = "")
}
.gs1_split <- function(value, separator, limit) {
  parts <- strsplit(paste0(value, separator, "#"), separator, fixed = TRUE)[[1L]]
  parts <- parts[-length(parts)]
  if (length(parts) > limit) .gs1_fail("GS1 URL component count exceeds limit")
  parts
}
.gs1_query_pair <- function(value) {
  at <- regexpr("=", value, fixed = TRUE)[1L]
  if (at < 0L) list(key = .gs1_decode(value, TRUE), value = "") else list(key = .gs1_decode(substr(value, 1L, at - 1L), TRUE), value = .gs1_decode(substring(value, at + 1L), TRUE))
}
.gs1_ipv4 <- function(value) {
  parts <- .gs1_split(value, ".", 1025L)
  length(parts) == 4L && all(vapply(parts, function(p) grepl("^(0|[1-9][0-9]{0,2})$", p) && as.numeric(p) <= 255, FALSE))
}
.gs1_ipv6_side <- function(value, allow_ipv4 = FALSE) {
  if (!nzchar(value)) return(0L)
  parts <- .gs1_split(value, ":", 1025L); n <- 0L
  for (i in seq_along(parts)) {
    part <- parts[i]
    if (grepl(".", part, fixed = TRUE)) {
      if (!allow_ipv4 || i != length(parts) || !.gs1_ipv4(part)) return(NA_integer_)
      n <- n + 2L
    } else { if (!grepl("^[0-9a-fA-F]{1,4}$", part)) return(NA_integer_); n <- n + 1L }
  }
  n
}
.gs1_ipv6 <- function(value) {
  parts <- .gs1_split(value, "::", 1025L)
  if (length(parts) == 1L) return(isTRUE(.gs1_ipv6_side(parts[1L], TRUE) == 8L))
  if (length(parts) == 2L) return(isTRUE(.gs1_ipv6_side(parts[1L]) + .gs1_ipv6_side(parts[2L], TRUE) < 8L))
  FALSE
}
.gs1_host_fail <- function() .gs1_fail("Unsupported host profile; use ASCII DNS, canonical dotted IPv4, or RFC IPv6 without credentials", "GS1_DIGITAL_LINK_UNSUPPORTED_HOST")
.gs1_authority <- function(value, scheme) {
  if (!nzchar(value) || nchar(value, type = "bytes") > 1024L || any(as.integer(charToRaw(value)) > 127L) || grepl("[@%]", value)) .gs1_host_fail()
  port <- NULL
  if (startsWith(value, "[")) {
    close <- regexpr("]", value, fixed = TRUE)[1L]; if (close < 0L) .gs1_host_fail()
    address <- substr(value, 2L, close - 1L); if (!.gs1_ipv6(address)) .gs1_host_fail()
    host <- paste0("[", tolower(address), "]"); tail <- substring(value, close + 1L)
    if (nzchar(tail)) { if (!startsWith(tail, ":")) .gs1_host_fail(); port <- substring(tail, 2L) }
  } else {
    at <- regexpr(":", value, fixed = TRUE)[1L]
    host <- tolower(if (at < 0L) value else substr(value, 1L, at - 1L)); if (at >= 0L) port <- substring(value, at + 1L)
    dns <- sub("\\.$", "", host)
    if (!nzchar(dns) || nchar(dns) > 253L) .gs1_host_fail()
    labels <- .gs1_split(dns, ".", 1025L)
    for (label in labels) if (nchar(label) < 1L || nchar(label) > 63L || !grepl("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", label)) .gs1_host_fail()
    tail <- labels[length(labels)]
    if ((.gs1_digits(tail) || grepl("^0x[0-9a-f]*$", tail)) && !.gs1_ipv4(host)) .gs1_host_fail()
  }
  if (!is.null(port)) {
    if (!grepl("^[0-9]{1,5}$", port) || as.numeric(port) > 65535) .gs1_fail("GS1 port must contain decimal digits from 0 to 65535", "GS1_DIGITAL_LINK_INVALID_URI")
    number <- as.integer(port)
    if (!((scheme == "http" && number == 80L) || (scheme == "https" && number == 443L))) host <- paste0(host, ":", number)
  }
  host
}
.gs1_url <- function(value) {
  s <- .gs1_text(value, "GS1 Digital Link URI")
  if (grepl("#", s, fixed = TRUE)) .gs1_fail("GS1 Digital Link URI must not include a fragment", "GS1_DIGITAL_LINK_FRAGMENT_NOT_ALLOWED")
  b <- as.integer(charToRaw(s))
  if (any(b <= 32L | b == 127L | b == 92L)) .gs1_fail("GS1 URI must be absolute http or https without whitespace or backslashes", "GS1_DIGITAL_LINK_INVALID_URI")
  m <- regmatches(s, regexec("^(https?)://([^/?]*)(.*)$", s, ignore.case = TRUE))[[1L]]
  if (!length(m)) .gs1_fail("GS1 URI must be an absolute http or https URL", "GS1_DIGITAL_LINK_INVALID_URI")
  scheme <- tolower(m[2L]); authority <- .gs1_authority(m[3L], scheme); rest <- m[4L]
  at <- regexpr("?", rest, fixed = TRUE)[1L]
  path <- if (at < 0L) rest else substr(rest, 1L, at - 1L); query <- if (at < 0L) NULL else substring(rest, at + 1L)
  for (part in .gs1_split(path, "/", 2L * GS1_MAX_ELEMENTS + 1L)) .gs1_decode(part)
  if (!is.null(query)) for (pair in .gs1_split(query, "&", GS1_MAX_ELEMENTS)) .gs1_query_pair(pair)
  list(scheme = scheme, authority = authority, path = path, query = query)
}
.gs1_base <- function(url) paste0(url$scheme, "://", url$authority)
.gs1_primary <- function(ai) { if (!is.character(ai) || length(ai) != 1L || is.na(ai) || !ai %in% .gs1_primary_ais || is.object(ai) || !is.null(dim(ai))) .gs1_fail("GS1 primary_ai must be one of 00, 01, or 414"); ai }
.gs1_policy <- function(policy) { if (!is.character(policy) || length(policy) != 1L || is.na(policy) || !policy %in% c("preserve", "reject") || is.object(policy) || !is.null(dim(policy))) .gs1_fail("GS1 unknown_query must be preserve or reject"); policy }
.gs1_placement <- function(ai, primary) {
  if (is.null(get_gs1_ai_info(ai))) .gs1_fail(paste("Unsupported GS1 AI", ai), "GS1_UNSUPPORTED_AI")
  if (!.gs1_eligible(ai, primary)) .gs1_fail(paste("GS1 AI", ai, "cannot be placed in the Digital Link path after primary AI", primary), "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
}
.gs1_unique <- function(ais) { at <- anyDuplicated(ais); if (at) .gs1_fail(paste("GS1 Digital Link must not contain duplicate AI", ais[at]), "GS1_DUPLICATE_AI") }
.gs1_prefix <- function(parts) {
  stack <- character()
  for (part in parts) {
    decoded <- .gs1_decode(part)
    if (decoded %in% c("", ".")) next
    if (decoded == "..") { if (length(stack)) stack <- stack[-length(stack)] } else stack <- c(stack, part)
  }
  if (length(stack)) paste0("/", paste0(stack, collapse = "/")) else ""
}
.gs1_path_parts <- function(path) {
  value <- gsub("^/+|/+$", "", path)
  if (!nzchar(value)) .gs1_fail("GS1 Digital Link path must include primary AI 00, 01, or 414", "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
  parts <- .gs1_split(value, "/", 2L * GS1_MAX_ELEMENTS + 1L)
  if (any(!nzchar(parts))) .gs1_fail("GS1 Digital Link path must not contain empty segments")
  parts
}
.gs1_first_ai <- function(parts, primary_ai) {
  found <- which(if (is.null(primary_ai)) parts %in% .gs1_primary_ais else parts == primary_ai)
  if (!length(found)) .gs1_fail("GS1 Digital Link path must include primary AI 00, 01, or 414", "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
  found[1L]
}
create_gs1_digital_link <- function(elements, base_url = NULL, primary_ai = "01", path_ais = NULL) {
  primary <- .gs1_primary(primary_ai)
  if (is.null(base_url)) .gs1_fail("GS1 Digital Link base_url is required")
  base <- .gs1_url(base_url)
  if (!is.null(base$query)) .gs1_fail("GS1 Digital Link base_url must not include query components")
  paths <- NULL
  if (!is.null(path_ais)) {
    paths <- character()
    for (ai in .gs1_bounded(path_ais, TRUE)) {
      if (!.gs1_is_ai(ai)) .gs1_fail("GS1 path_ais entries must be 2 to 4 digit AI strings")
      if (ai != primary) { .gs1_placement(ai, primary); paths <- c(paths, ai) }
    }
  }
  normalized <- .gs1_elements(elements); ais <- vapply(normalized, `[[`, "", "ai"); .gs1_unique(ais)
  selected <- match(primary, ais)
  if (is.na(selected)) .gs1_fail(paste("GS1 input must include primary AI", primary), "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
  path <- list(normalized[[selected]]); query <- list()
  for (i in seq_along(normalized)) {
    if (i == selected) next
    e <- normalized[[i]]; inpath <- if (is.null(paths)) .gs1_eligible(e$ai, primary) else e$ai %in% paths
    if (inpath && !e$value %in% c(".", "..")) { .gs1_placement(e$ai, primary); path[[length(path) + 1L]] <- e } else query[[length(query) + 1L]] <- e
  }
  if (length(query)) query <- query[order(vapply(query, `[[`, "", "ai"), vapply(query, `[[`, "", "value"), method = "radix")]
  prefix <- .gs1_prefix(.gs1_split(base$path, "/", 2L * GS1_MAX_ELEMENTS + 1L))
  for (part in .gs1_split(prefix, "/", 2L * GS1_MAX_ELEMENTS + 1L)) if (.gs1_decode(part) %in% .gs1_primary_ais) .gs1_fail("GS1 base URL normalized path must not contain a primary AI component, including percent-encoded equivalents", "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
  out <- paste0(.gs1_base(base), prefix, paste0(vapply(path, function(e) paste0("/", .gs1_encode(e$ai), "/", .gs1_encode(e$value)), ""), collapse = ""))
  if (length(query)) out <- paste0(out, "?", paste0(vapply(query, function(e) paste0(.gs1_encode(e$ai, TRUE), "=", .gs1_encode(e$value, TRUE)), ""), collapse = "&"))
  .gs1_text(out, "GS1 Digital Link output")
}
.gs1_parse_link <- function(url, primary_ai, unknown_query) {
  if (!is.null(primary_ai)) .gs1_primary(primary_ai)
  .gs1_policy(unknown_query); parts <- .gs1_path_parts(url$path); start <- .gs1_first_ai(parts, primary_ai)
  for (i in seq.int(start, length(parts))) if (.gs1_decode(parts[i]) %in% c(".", "..")) .gs1_fail("GS1 Digital Link path values must not be dot segments; place these values in the query", "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
  if ((length(parts) - start + 1L) %% 2L) .gs1_fail("GS1 Digital Link path must contain AI/value pairs")
  path <- query <- unknown <- list(); seen <- character()
  for (i in seq.int(start, length(parts), by = 2L)) {
    ai <- parts[i]
    if (!.gs1_is_ai(ai)) .gs1_fail(paste("GS1 Digital Link path segment", i, "must be a GS1 AI"))
    e <- .gs1_element(list(ai = ai, value = .gs1_decode(parts[i + 1L])), length(path))
    if (length(path)) .gs1_placement(ai, path[[1L]]$ai)
    seen <- c(seen, ai); .gs1_unique(seen); path[[length(path) + 1L]] <- e
  }
  if (!is.null(url$query)) for (rawpair in .gs1_split(url$query, "&", GS1_MAX_ELEMENTS)) {
    if (!nzchar(rawpair)) next
    pair <- .gs1_query_pair(rawpair)
    if (.gs1_is_ai(pair$key)) {
      e <- .gs1_element(list(ai = pair$key, value = pair$value), length(path) + length(query)); seen <- c(seen, e$ai); .gs1_unique(seen); query[[length(query) + 1L]] <- e
    } else if (unknown_query == "preserve") unknown[[length(unknown) + 1L]] <- pair else .gs1_fail("GS1 Digital Link query parameter is not a GS1 AI", "GS1_DIGITAL_LINK_UNKNOWN_QUERY")
    if (length(path) + length(query) + length(unknown) > GS1_MAX_ELEMENTS) .gs1_fail("GS1 element and query pair count exceeds limit")
  }
  list(elements = c(path, query), primary = path[[1L]], path_elements = path, query_elements = query, unknown_query = unknown)
}
parse_gs1_digital_link <- function(uri, primary_ai = NULL, unknown_query = "preserve") .gs1_parse_link(.gs1_url(uri), primary_ai, unknown_query)
validate_gs1_digital_link <- function(uri, primary_ai = NULL, unknown_query = "preserve", normalize = FALSE) {
  tryCatch({
    if (!identical(normalize, FALSE)) .gs1_fail("GS1 validation normalize is unsupported; call normalize_gs1_digital_link")
    url <- .gs1_url(uri); parsed <- .gs1_parse_link(url, primary_ai, unknown_query); warnings <- list()
    if (url$scheme == "http") warnings[[length(warnings) + 1L]] <- list(code = "GS1_DIGITAL_LINK_HTTP", message = "URI uses HTTP; use HTTPS when transport security is required", reason = "http-uri")
    if (length(parsed$unknown_query)) warnings[[length(warnings) + 1L]] <- list(code = "GS1_DIGITAL_LINK_UNKNOWN_QUERY_PRESERVED", message = "Non-GS1 query parameters are preserved", reason = "unknown-query-preserved", count = length(parsed$unknown_query))
    list(ok = TRUE, result = parsed, errors = list(), warnings = warnings)
  }, error = function(e) .gs1_catch(e, TRUE))
}
normalize_gs1_digital_link <- function(uri, primary_ai = NULL, unknown_query = "preserve", mode = "specqr-deterministic") {
  if (!identical(mode, "specqr-deterministic")) .gs1_fail("GS1 normalization mode must be specqr-deterministic")
  url <- .gs1_url(uri); parsed <- .gs1_parse_link(url, primary_ai, unknown_query); parts <- .gs1_path_parts(url$path); start <- .gs1_first_ai(parts, primary_ai)
  stem <- paste0(.gs1_base(url), .gs1_prefix(if (start > 1L) parts[seq_len(start - 1L)] else character()))
  result <- create_gs1_digital_link(parsed$elements, base_url = stem, primary_ai = parsed$primary$ai)
  if (length(parsed$unknown_query)) {
    suffix <- paste0(vapply(parsed$unknown_query, function(p) paste0(.gs1_encode(p$key, TRUE), "=", .gs1_encode(p$value, TRUE)), ""), collapse = "&")
    result <- paste0(result, if (grepl("?", result, fixed = TRUE)) "&" else "?", suffix)
  }
  .gs1_text(result, "GS1 Digital Link output")
}
gs1_normalize <- normalize_gs1_elements
gs1_from_human_readable <- parse_gs1_human_readable
gs1_to_element_string <- create_gs1_element_string
gs1_build <- create_gs1_element_string
gs1_parse <- parse_gs1_element_string
gs1_digital_link <- create_gs1_digital_link
gs1_to_digital_link <- create_gs1_digital_link

# Strict owned Model 2 data and control segments. Binary input is never text.
ALPHANUMERIC_CHARSET <- "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
DATA_MODES <- c("numeric", "alphanumeric", "kanji", "byte")
CONTROL_MODES <- c("eci", "fnc1", "fnc1-second", "structured-append")
MAX_SINGLE_SYMBOL_CHARACTERS <- 7089L
MAX_SINGLE_SYMBOL_DATA_BITS <- 23648L
MAX_PAYLOAD_UNITS <- 1000000L
MAX_MANUAL_SEGMENTS <- 16384L
.ALPHA_CODES <- utf8ToInt(ALPHANUMERIC_CHARSET)

# Decode strictly instead of depending on the host locale or permissive codecs.
.utf8_scalars <- function(bytes) {
  b <- as.integer(bytes); n <- length(b)
  if (all(b < 128L)) {
    if (n > MAX_PAYLOAD_UNITS) specqr_abort("Text exceeds the payload resource limit", "DATA_TOO_LONG")
    return(b)
  }
  out <- integer(n); count <- 0L; i <- 1L
  fail <- function() specqr_abort("QR text must be well-formed UTF-8 without surrogate code points")
  while (i <= n) {
    first <- b[i]
    if (first < 128L) { value <- first; width <- 1L
    } else if (first >= 194L && first <= 223L) { value <- first - 192L; width <- 2L
    } else if (first >= 224L && first <= 239L) { value <- first - 224L; width <- 3L
    } else if (first >= 240L && first <= 244L) { value <- first - 240L; width <- 4L
    } else fail()
    if (i + width - 1L > n) fail()
    if (width > 1L) for (j in seq_len(width - 1L)) {
      next_byte <- b[i + j]
      if (next_byte < 128L || next_byte > 191L) fail()
      value <- value * 64L + next_byte - 128L
    }
    if ((width == 2L && value < 128L) || (width == 3L && value < 2048L) ||
        (width == 4L && value < 65536L) || value > 1114111L ||
        (value >= 55296L && value <= 57343L)) fail()
    count <- count + 1L
    if (count > MAX_PAYLOAD_UNITS) specqr_abort("Text exceeds the payload resource limit", "DATA_TOO_LONG")
    out[count] <- value; i <- i + width
  }
  out[seq_len(count)]
}
strict_utf8 <- function(text) {
  scalar_text(text, "QR text")
  if (Encoding(text) == "bytes") specqr_abort("QR text must be Unicode text, not a bytes-tagged R string")
  # Explicit Latin-1 R strings have a known encoding; other unmarked strings
  # are required to already contain UTF-8, independently of the process locale.
  source <- if (Encoding(text) == "latin1") enc2utf8(text) else text
  bytes <- charToRaw(source)
  if (length(bytes) > 4 * MAX_PAYLOAD_UNITS) specqr_abort("Text exceeds the payload resource limit", "DATA_TOO_LONG")
  .utf8_scalars(bytes)
  bytes
}
payload_units <- function(data) {
  if (is.character(data)) return(length(.utf8_scalars(strict_utf8(data))))
  n <- if (is.atomic(data) || is.list(data)) length(data) else 0L
  if (n > MAX_PAYLOAD_UNITS) specqr_abort("Payload exceeds the 1000000-unit resource limit", "DATA_TOO_LONG")
  n
}
.byte_sequence <- function(data, label = "Byte data", maximum = MAX_PAYLOAD_UNITS) {
  if ((!is.raw(data) && !is.integer(data) && !is.double(data)) ||
      is.object(data) || !is.null(dim(data)))
    specqr_abort(paste0(label, " must be a finite byte sequence"))
  if (length(data) > maximum) specqr_abort(paste0(label, " exceeds the resource limit"), "DATA_TOO_LONG")
  if (!is.raw(data) && (anyNA(data) || any(!is.finite(data)) || any(data != floor(data)) || any(data < 0 | data > 255)))
    specqr_abort(paste0(label, " requires integer bytes from 0 to 255"))
  as.raw(data)
}
kanji_code <- function(character) {
  if (!(is.character(character) && !is.object(character) && length(character) == 1L &&
        is.null(dim(character)) && !is.na(character))) return(-1L)
  values <- tryCatch(.utf8_scalars(strict_utf8(character)), specqr_error = function(e) integer())
  if (length(values) != 1L || values < 128L || values > 65535L) return(-1L)
  i <- findInterval(values, .KANJI_KEYS)
  if (i == 0L || .KANJI_KEYS[i] != values) -1L else .KANJI_CODES[i]
}
can_encode_kanji <- function(character) kanji_code(character) >= 0L
kanji_value <- function(character) {
  code <- kanji_code(character)
  if (code < 0L) specqr_abort("kanji mode cannot encode this character", "INVALID_MODE")
  adjusted <- code - if (code <= 0x9ffc) 0x8140 else 0xc140
  as.integer((adjusted %/% 256L) * 192L + adjusted %% 256L)
}
alpha_value <- function(character) {
  if (is.numeric(character) && !is.object(character) && length(character) == 1L && !is.na(character))
    return(match(character, .ALPHA_CODES, nomatch = 0L) - 1L)
  if (!is.character(character) || length(character) != 1L || is.na(character)) return(-1L)
  if (nchar(character, type = "bytes") != 1L) return(-1L)
  match(as.integer(charToRaw(character)), .ALPHA_CODES, nomatch = 0L) - 1L
}
.segment_mode <- function(mode) {
  scalar_text(mode, "Segment mode", "INVALID_MODE")
  if (!(mode %in% c(DATA_MODES, CONTROL_MODES))) specqr_abort("Unsupported segment mode", "INVALID_MODE")
  mode
}
segment <- function(mode, data = NULL, assignment_number = NULL,
                    application_indicator = NULL, index = NULL, total = NULL,
                    parity = NULL, ...) {
  if (length(list(...))) specqr_abort("Unknown segment field")
  m <- .segment_mode(mode)
  supplied <- list(data = data, assignment_number = assignment_number,
                   application_indicator = application_indicator, index = index, total = total, parity = parity)
  allowed <- if (m %in% DATA_MODES) "data" else switch(m, eci = "assignment_number",
    `fnc1-second` = "application_indicator", `structured-append` = c("index", "total", "parity"), character())
  for (name in names(supplied)) if (!is.null(supplied[[name]]) && !(name %in% allowed))
    specqr_abort(paste0(m, " segment does not accept ", name), if (m == "fnc1") "INVALID_GS1" else "INVALID_MODE")
  control <- m %in% CONTROL_MODES; text <- NULL; bytes <- raw(); characters <- 0L
  count <- 0L; byte_count <- 0L; indicator <- NULL
  if (m == "eci") {
    assignment_number <- scalar_integer(assignment_number, 0, 999999, "ECI assignment number", "INVALID_ECI")
  } else if (m == "fnc1-second") {
    scalar_text(application_indicator, "FNC1 second application_indicator", "INVALID_MODE")
    indicator_bytes <- as.integer(charToRaw(application_indicator))
    valid_indicator <- (length(indicator_bytes) == 2L && all(indicator_bytes >= 48L & indicator_bytes <= 57L)) ||
      (length(indicator_bytes) == 1L && ((indicator_bytes >= 65L && indicator_bytes <= 90L) ||
                                     (indicator_bytes >= 97L && indicator_bytes <= 122L)))
    if (!valid_indicator)
      specqr_abort("FNC1 second application_indicator must be two ASCII digits or one Latin letter", "INVALID_MODE")
    indicator <- if (length(indicator_bytes) == 2L)
      (indicator_bytes[1L] - 48L) * 10L + indicator_bytes[2L] - 48L else indicator_bytes + 100L
  } else if (m == "structured-append") {
    index <- scalar_integer(index, 1, 16, "Structured Append index", "INVALID_MODE")
    total <- scalar_integer(total, 2, 16, "Structured Append total", "INVALID_MODE")
    parity <- scalar_integer(parity, 0, 255, "Structured Append parity", "INVALID_MODE")
    if (index > total) specqr_abort("Structured Append index must not exceed total", "INVALID_MODE")
  } else if (!control) {
    if (m == "byte" && !is.character(data)) {
      if (!is.raw(data)) specqr_abort("Binary byte segment data must be a raw vector")
      bytes <- .byte_sequence(data); data <- bytes; count <- length(bytes); byte_count <- count
    } else {
      bytes <- strict_utf8(data); scalars <- .utf8_scalars(bytes)
      text <- rawToChar(bytes); Encoding(text) <- "UTF-8"; data <- text
      characters <- length(scalars); count <- if (m == "byte") length(bytes) else characters
      byte_count <- if (m == "kanji") characters * 2L else length(bytes)
      if (m == "numeric" && any(scalars < 48L | scalars > 57L))
        specqr_abort("numeric mode can only encode decimal digits 0-9", "INVALID_MODE")
      if (m == "alphanumeric" && any(!(scalars %in% .ALPHA_CODES)))
        specqr_abort(paste0("alphanumeric mode can only encode: ", ALPHANUMERIC_CHARSET), "INVALID_MODE")
      if (m == "kanji" && any(!(scalars %in% .KANJI_KEYS)))
        specqr_abort("kanji mode cannot encode one or more characters", "INVALID_MODE")
    }
  }
  structure(list(mode = m, data = data, assignment_number = assignment_number,
    application_indicator = application_indicator, index = index, total = total, parity = parity,
    count = count, character_count = characters, byte_count = byte_count, logical_bytes = bytes,
    text = text, is_control = control, application_indicator_codeword = indicator), class = "specqr_segment")
}

# Reconstruct at trust boundaries: R lists can be changed after construction.
.validate_segment <- function(value) {
  if (!inherits(value, "specqr_segment") || !is.list(value) || is.null(names(value)) || anyDuplicated(names(value)))
    specqr_abort("Expected a validated Segment value")
  fields <- c("mode", "data", "assignment_number", "application_indicator", "index", "total", "parity")
  if (!all(fields %in% names(value))) specqr_abort("Segment fields are incomplete")
  do.call(segment, unclass(value)[fields], quote = TRUE)
}
numeric_segment <- function(data) segment("numeric", data)
alphanumeric_segment <- function(data) segment("alphanumeric", data)
byte_segment <- function(data) segment("byte", data)
bytesegment <- byte_segment
kanji_segment <- function(data) segment("kanji", data)
eci <- function(assignment_number) segment("eci", assignment_number = assignment_number)
fnc1 <- function() segment("fnc1")
fnc1_first <- fnc1
fnc1_second <- function(application_indicator) segment("fnc1-second", application_indicator = application_indicator)
structured_append_segment <- function(index, total, parity) segment("structured-append", index = index, total = total, parity = parity)
is_control <- function(segment) .validate_segment(segment)$is_control
segment_text <- function(segment) .validate_segment(segment)$text
logical_bytes <- function(segment) .validate_segment(segment)$logical_bytes
character_count <- function(segment) .validate_segment(segment)$character_count
byte_count <- function(segment) .validate_segment(segment)$byte_count
application_indicator_codeword <- function(segment) .validate_segment(segment)$application_indicator_codeword

.bit_length <- function(segment, version) {
  m <- segment$mode
  if (m == "eci") return(if (segment$assignment_number < 128) 12L else if (segment$assignment_number < 16384) 20L else 28L)
  if (m == "fnc1") return(4L)
  if (m == "fnc1-second") return(12L)
  if (m == "structured-append") return(20L)
  n <- segment$count
  payload <- if (m == "numeric") n %/% 3L * 10L + c(0L, 4L, 7L)[n %% 3L + 1L] else
    if (m == "alphanumeric") n %/% 2L * 11L + n %% 2L * 6L else n * if (m == "kanji") 13L else 8L
  4L + character_count_bits(version, m) + payload
}
bit_length <- function(segment, version) { validate_version(version); .bit_length(.validate_segment(segment), version) }
segment_bit_length <- bit_length
.bits_of <- function(value, width) as.integer(bitwAnd(bitwShiftR(as.integer(value), (width - 1L):0L), 1L))
bits <- function(segment, version) {
  validate_version(version); s <- .validate_segment(segment); nbits <- .bit_length(s, version)
  if (!s$is_control && s$count >= 2^character_count_bits(version, s$mode))
    specqr_abort(paste0("Input has too many ", s$mode, " units for version ", version), "DATA_TOO_LONG")
  if (nbits > MAX_SINGLE_SYMBOL_DATA_BITS) specqr_abort("Segment exceeds the maximum single-symbol bit capacity", "DATA_TOO_LONG")
  result <- integer(nbits); offset <- 0L
  append_bits <- function(value, width) {
    if (width > 0L) result[seq.int(offset + 1L, offset + width)] <<- .bits_of(value, width)
    offset <<- offset + width
  }
  m <- s$mode
  indicator <- switch(m, numeric = 1L, alphanumeric = 2L, byte = 4L, kanji = 8L,
                      eci = 7L, fnc1 = 5L, `fnc1-second` = 9L, `structured-append` = 3L)
  append_bits(indicator, 4L)
  if (m == "eci") {
    value <- s$assignment_number
    if (value < 128L) append_bits(value, 8L) else if (value < 16384L) {
      append_bits(2L, 2L); append_bits(value, 14L)
    } else { append_bits(6L, 3L); append_bits(value, 21L) }
  } else if (m == "fnc1-second") append_bits(s$application_indicator_codeword, 8L) else
    if (m == "structured-append") {
      append_bits(s$index - 1L, 4L); append_bits(s$total - 1L, 4L); append_bits(s$parity, 8L)
    } else if (!s$is_control) {
      append_bits(s$count, character_count_bits(version, m)); data <- as.integer(s$logical_bytes)
      if (m == "byte") {
        for (value in data) append_bits(value, 8L)
      } else if (m == "numeric") {
        if (length(data)) for (start in seq.int(1L, length(data), by = 3L)) {
          width <- min(3L, length(data) - start + 1L)
          value <- sum((data[seq.int(start, length.out = width)] - 48L) * 10^((width - 1L):0L))
          append_bits(value, c(4L, 7L, 10L)[width])
        }
      } else if (m == "alphanumeric") {
        values <- match(data, .ALPHA_CODES) - 1L; n <- length(values)
        if (n >= 2L) for (start in seq.int(1L, n - 1L, by = 2L)) append_bits(values[start] * 45L + values[start + 1L], 11L)
        if (n %% 2L) append_bits(values[n], 6L)
      } else {
        codes <- .KANJI_CODES[match(.utf8_scalars(s$logical_bytes), .KANJI_KEYS)]
        for (code in codes) {
          value <- code - if (code <= 0x9ffc) 0x8140 else 0xc140
          append_bits((value %/% 256L) * 192L + value %% 256L, 13L)
        }
      }
    }
  if (offset != nbits) specqr_abort("Inconsistent QR segment bit length")
  result
}
segment_bits <- bits

.validate_control_list <- function(segments) {
  found <- structure(vector("list", length(CONTROL_MODES)), names = CONTROL_MODES); units <- 0L
  for (i in seq_along(segments)) {
    s <- segments[[i]]; units <- units + if (is.raw(s$data)) length(s$data) else s$character_count
    if (units > MAX_PAYLOAD_UNITS) specqr_abort("Manual payload exceeds the resource limit", "DATA_TOO_LONG")
    if (s$is_control) found[[s$mode]] <- c(found[[s$mode]], i)
  }
  for (mode in c("fnc1", "fnc1-second", "structured-append")) {
    positions <- found[[mode]]; code <- if (mode == "fnc1") "INVALID_GS1" else "INVALID_MODE"
    if (length(positions) > 1L) specqr_abort(paste0("Manual segments can include at most one ", mode, " segment"), code)
    if (length(positions) && positions[1L] != 1L) specqr_abort(paste0("Manual ", mode, " segment must be first"), code)
  }
  if (sum(lengths(found) > 0L) > 1L)
    specqr_abort("FNC1, FNC1 second, Structured Append, and ECI cannot be combined in this implementation",
                 if (length(found$fnc1)) "INVALID_GS1" else "INVALID_MODE")
  segments
}
normalize_segments <- function(segments) {
  if (!is.list(segments) || is.object(segments) || !is.null(dim(segments))) specqr_abort("Manual segments must be a finite list")
  if (length(segments) > MAX_MANUAL_SEGMENTS) specqr_abort("Manual segments exceed the resource limit", "DATA_TOO_LONG")
  result <- vector("list", length(segments)); units <- 0L
  allowed <- c("mode", "data", "assignment_number", "application_indicator", "index", "total", "parity", "text", "bytes")
  for (i in seq_along(segments)) {
    item <- segments[[i]]
    if (inherits(item, "specqr_segment")) result[[i]] <- .validate_segment(item) else {
      if (!is.list(item) || is.object(item) || is.null(names(item)) ||
          anyNA(names(item)) || anyDuplicated(names(item)) || any(!nzchar(names(item))) || any(!(names(item) %in% allowed)))
        specqr_abort(paste0("segments[", i, "] must be a Segment or mapping with supported fields"))
      payloads <- intersect(c("data", "text", "bytes"), names(item))
      if (length(payloads) > 1L) specqr_abort(paste0("segments[", i, "] has ambiguous payload fields"))
      if (!("mode" %in% names(item))) specqr_abort(paste0("segments[", i, "] requires mode"), "INVALID_MODE")
      m <- .segment_mode(item[["mode"]])
      if (m %in% CONTROL_MODES && length(payloads))
        specqr_abort("Control segment must not include a payload field", if (m == "fnc1") "INVALID_GS1" else "INVALID_MODE")
      if (length(payloads) && payloads != "data") names(item)[match(payloads, names(item))] <- "data"
      result[[i]] <- do.call(segment, item, quote = TRUE)
    }
    s <- result[[i]]; units <- units + if (is.raw(s$data)) length(s$data) else s$character_count
    if (units > MAX_PAYLOAD_UNITS) specqr_abort("Manual payload exceeds the resource limit", "DATA_TOO_LONG")
  }
  .validate_control_list(result)
}
validate_control_segments <- function(segments) {
  if (!is.list(segments) || is.object(segments) || !is.null(dim(segments))) specqr_abort("Manual segments must be a finite list")
  if (length(segments) > MAX_MANUAL_SEGMENTS) specqr_abort("Manual segments exceed the resource limit", "DATA_TOO_LONG")
  .validate_control_list(lapply(segments, .validate_segment))
}
segments_bit_length <- function(segments, version) {
  validate_version(version); ss <- normalize_segments(segments)
  sum(vapply(ss, .bit_length, numeric(1L), version = version))
}
segments_bits <- function(segments, version) {
  validate_version(version); ss <- normalize_segments(segments)
  total <- sum(vapply(ss, .bit_length, numeric(1L), version = version))
  if (total > MAX_SINGLE_SYMBOL_DATA_BITS) specqr_abort("Segments exceed the maximum single-symbol bit capacity", "DATA_TOO_LONG")
  as.integer(unlist(lapply(ss, bits, version = version), use.names = FALSE))
}

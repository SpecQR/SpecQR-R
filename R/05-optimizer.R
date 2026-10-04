# Exact linear-time segmentation with remainder-aware monotone queues.
.OPT_MODES <- c("numeric", "alphanumeric", "kanji", "byte")
.OPT_ALPHA <- utf8ToInt("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")
.qr_fail <- function(message, subclass = "invalid_input") specqr_abort(message, toupper(subclass))
.qr_integer <- function(x, name, low, high, subclass = "invalid_input") {
  if (!(is.integer(x) || is.double(x)) || is.object(x) || !is.null(dim(x)) || length(x) != 1L ||
      is.na(x) || !is.finite(x) || x != floor(x) || x < low || x > high)
    .qr_fail(paste0(name, " must be an integer from ", low, " to ", high), subclass)
  x
}
.qr_bool <- function(x, name) {
  if (!is.logical(x) || is.object(x) || !is.null(dim(x)) || length(x) != 1L || is.na(x))
    .qr_fail(paste0(name, " must be TRUE or FALSE"))
  x
}
.qr_text <- function(x, name = "text") {
  if (!is.character(x) || is.object(x) || !is.null(dim(x)) || length(x) != 1L || is.na(x) || Encoding(x) == "bytes")
    .qr_fail(paste0(name, " must be one valid Unicode string"))
  encoded <- strict_utf8(x)
  y <- rawToChar(encoded); Encoding(y) <- "UTF-8"
  y
}
.qr_input <- function(x) {
  if (is.raw(x) && !is.object(x) && is.null(dim(x))) {
    if (length(x) > 1000000L) .qr_fail("Payload exceeds the resource limit", "data_too_long")
    return(x)
  }
  .qr_text(x, "input")
}
.qr_mapping <- function(x, label = "options") {
  if (is.list(x) && !is.object(x) && is.null(dim(x)) && !length(x)) return(x)
  if (!is.list(x) || is.object(x) || !is.null(dim(x)) || is.null(names(x)) || anyNA(names(x)) ||
      any(!nzchar(names(x))) || anyDuplicated(names(x)))
    .qr_fail(paste0(label, " must be a uniquely named list"))
  x
}
.qr_dots <- function(x, allowed = NULL) {
  if (!length(x)) return(x)
  x <- .qr_mapping(x)
  if (!is.null(allowed) && any(!names(x) %in% allowed))
    .qr_fail(paste0("Unknown option: ", names(x)[which(!names(x) %in% allowed)[1L]]))
  x
}
.qr_payload_bits <- function(mode, n, nb = n) {
  switch(mode, numeric = (n %/% 3L) * 10L + c(0L, 4L, 7L)[n %% 3L + 1L],
         alphanumeric = (n %/% 2L) * 11L + (n %% 2L) * 6L,
         kanji = n * 13L, byte = nb * 8L)
}
# Each lane holds candidate starts in nondecreasing (adjusted cost, count)
# order. Starts are evicted at the mode count-field limit. Equal paths preserve
# numeric, alphanumeric, kanji, byte order and the earliest segment start.
.qr_optimize <- function(cp, version, allow_kanji, stop_bits = Inf) {
  n <- length(cp)
  offsets <- c(0, cumsum(ifelse(cp < 128L, 1L, ifelse(cp < 2048L, 2L, ifelse(cp < 65536L, 3L, 4L)))))
  costs <- rep(Inf, n + 1L); costs[1L] <- 0
  counts <- integer(n + 1L); previous <- integer(n + 1L); chosen <- integer(n + 1L)
  queues <- matrix(0L, n + 1L, 7L); heads <- rep(1L, 7L); tails <- integer(7L)
  keys <- matrix(0, n + 1L, 4L)
  widths <- vapply(.OPT_MODES, function(m) character_count_bits(version, m), numeric(1))
  limits <- 2^widths - 1L
  alpha <- cp %in% .OPT_ALPHA
  kj <- if (allow_kanji) vapply(cp, function(c) can_encode_kanji(intToUtf8(c)), logical(1)) else rep(FALSE, n)
  eligible <- cbind(cp >= 48L & cp <= 57L, alpha, kj, rep(TRUE, n))
  starts <- c(1L, 4L, 6L, 7L); lane_counts <- c(3L, 2L, 1L, 1L)
  processed <- 0L
  for (i in seq_len(n)) {
    start <- i - 1L; best <- Inf; best_count <- Inf
    for (m in 1:4) {
      lanes <- lane_counts[m]; lane_ids <- seq.int(starts[m], length.out = lanes)
      if (!eligible[i, m]) { heads[lane_ids] <- 1L; tails[lane_ids] <- 0L; next }
      base <- switch(m, 10L * (start %/% 3L), 11L * (start %/% 2L), 13L * start, 8L * offsets[start + 1L])
      key <- costs[start + 1L] - base; keys[start + 1L, m] <- key
      lane <- starts[m] + start %% lanes
      while (tails[lane] >= heads[lane]) {
        j <- queues[tails[lane], lane]
        if (keys[j + 1L, m] > key || (keys[j + 1L, m] == key && counts[j + 1L] > counts[start + 1L])) {
          tails[lane] <- tails[lane] - 1L
        } else break
      }
      tails[lane] <- tails[lane] + 1L; queues[tails[lane], lane] <- start
      for (lane in lane_ids) {
        while (heads[lane] <= tails[lane]) {
          j <- queues[heads[lane], lane]
          count <- if (m == 4L) offsets[i + 1L] - offsets[j + 1L] else i - j
          if (count <= limits[m]) break
          heads[lane] <- heads[lane] + 1L
        }
        if (heads[lane] > tails[lane]) next
        j <- queues[heads[lane], lane]
        cost <- costs[j + 1L] + 4L + widths[m] + .qr_payload_bits(.OPT_MODES[m], i - j, offsets[i + 1L] - offsets[j + 1L])
        count <- counts[j + 1L] + 1L
        if (cost < best || (cost == best && count < best_count)) {
          best <- cost; best_count <- count; chosen[i + 1L] <- m; previous[i + 1L] <- j
        }
      }
    }
    costs[i + 1L] <- best; counts[i + 1L] <- best_count; processed <- i
    if (best > stop_bits) break
  }
  list(costs = costs, previous = previous, chosen = chosen, offsets = offsets, processed = processed)
}
optimize_segments <- function(text, version = 1, allow_kanji = TRUE, ...) {
  .qr_dots(list(...), character()); validate_version(version); .qr_bool(allow_kanji, "allow_kanji")
  text <- .qr_text(text); cp <- utf8ToInt(text)
  if (length(cp) > 7089L) .qr_fail("Optimized input exceeds 7089 scalars", "data_too_long")
  if (!length(cp)) return(list(segment("byte", "")))
  t <- .qr_optimize(cp, version, allow_kanji); result <- list(); n <- length(cp)
  while (n > 0L) {
    j <- t$previous[n + 1L]; m <- t$chosen[n + 1L]
    result[[length(result) + 1L]] <- segment(.OPT_MODES[m], intToUtf8(cp[seq.int(j + 1L, n)]))
    n <- j
  }
  rev(result)
}
create_segments <- function(input, mode = "auto", version = 1, optimize = TRUE, eci = NULL, allow_kanji = TRUE, ...) {
  .qr_dots(list(...), character()); validate_version(version)
  .qr_bool(optimize, "optimize"); .qr_bool(allow_kanji, "allow_kanji")
  if (!is.character(mode) || is.object(mode) || !is.null(dim(mode)) || length(mode) != 1L || is.na(mode) || !mode %in% c("auto", .OPT_MODES))
    .qr_fail("Unsupported data mode", "invalid_mode")
  assignment <- if (is.null(eci) || identical(eci, FALSE)) NULL else if (identical(eci, TRUE)) 26L else .qr_integer(eci, "eci", 0, 999999, "invalid_eci")
  prefix <- if (is.null(assignment)) list() else list(segment("eci", assignment_number = assignment))
  input <- .qr_input(input)
  if (is.raw(input)) {
    if (!mode %in% c("auto", "byte")) .qr_fail("Binary input requires byte mode", "invalid_mode")
    return(c(prefix, list(segment("byte", input))))
  }
  if (mode != "auto") return(c(prefix, list(segment(mode, input))))
  if (optimize) return(c(prefix, optimize_segments(input, version, allow_kanji && is.null(assignment))))
  cp <- utf8ToInt(input)
  selected <- if (length(cp) && all(cp >= 48L & cp <= 57L)) "numeric" else if (length(cp) && all(cp %in% .OPT_ALPHA)) "alphanumeric" else if (length(cp) && allow_kanji && is.null(assignment) && all(vapply(cp, function(c) can_encode_kanji(intToUtf8(c)), logical(1)))) "kanji" else "byte"
  c(prefix, list(segment(selected, input)))
}

# Dependency-free SVG and PNG. PNG uses stored DEFLATE, CRC-32 and Adler-32.
RASTER_PIXEL_BUDGET <- 4 * 1024 * 1024
SVG_CHARACTER_BUDGET <- 8 * 1024 * 1024
DATA_URL_CHARACTER_BUDGET <- 32 * 1024 * 1024
.render_args <- function(x, margin, scale, foreground = NULL, background = NULL, dpi = NULL) {
  if (inherits(x, "specqr_result")) .qr_validate_result(x)
  wrapped <- is.list(x) && !is.null(x[["matrix"]])
  if (wrapped && anyDuplicated(names(x))) specqr_abort("render result contains duplicate fields")
  opts <- if (wrapped) x[["options"]] else NULL
  if (!is.null(opts) && (!is.list(opts) || anyDuplicated(names(opts)))) specqr_abort("render options must be a list with unique fields")
  mat <- if (wrapped) x[["matrix"]] else x
  choose <- function(value, key, default) if (!is.null(value)) value else if (!is.null(opts[[key]])) opts[[key]] else default
  list(matrix = mat, margin = choose(margin, "margin", 4L), scale = choose(scale, "scale", 8L),
       foreground = choose(foreground, "foreground", "black"), background = choose(background, "background", "white"), dpi = choose(dpi, "print_dpi", NULL))
}
.render_geometry <- function(x, margin, scale, raster = FALSE) {
  a <- .render_args(x, margin, scale); mat <- a$matrix
  if (!is.matrix(mat) || !is.logical(mat) || anyNA(mat) || nrow(mat) != ncol(mat) || nrow(mat) < 1L || nrow(mat) > 177L)
    specqr_abort("matrix must be a non-missing square logical matrix with dimension 1..177")
  m <- scalar_integer(a$margin, 0, 1e9, "margin"); s <- scalar_integer(a$scale, 1, 1e9, "scale")
  span <- nrow(mat) + 2 * as.double(m); d <- span * as.double(s)
  if (d > 1e9) specqr_abort("render dimension exceeds geometry bound")
  if (raster && d * d > RASTER_PIXEL_BUDGET) specqr_abort("raster exceeds the 4194304 pixel budget")
  list(matrix = mat, dimension = d, margin = m, scale = s)
}
.render_color_text <- function(color) {
  text <- scalar_text(color, "color", "INVALID_COLOR")
  if (nchar(text, type = "bytes") > 64L || !validUTF8(text)) specqr_abort("color must be valid UTF-8 with at most 64 bytes", "INVALID_COLOR")
  text <- trimws(text)
  if (!nzchar(text) || !grepl("^(#[0-9A-Fa-f]{3}|#[0-9A-Fa-f]{4}|#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{8}|[A-Za-z]+)$", text))
    specqr_abort("color must be hexadecimal RGB/RGBA or a simple ASCII CSS name", "INVALID_COLOR")
  text
}
parse_color <- function(color, strict = FALSE) {
  scalar_flag(strict, "strict"); text <- tolower(.render_color_text(color))
  named <- switch(text, black = c(0, 0, 0, 255), white = c(255, 255, 255, 255), transparent = c(0, 0, 0, 0), NULL)
  if (!is.null(named)) return(named)
  if (startsWith(text, "#")) {
    h <- substring(text, 2L); width <- if (nchar(h) <= 4L) 1L else 2L
    p <- seq.int(1L, nchar(h), by = width); result <- strtoi(substring(h, p, p + width - 1L), 16L)
    if (width == 1L) result <- result * 17L
    if (length(result) == 3L) result <- c(result, 255L)
    return(as.numeric(result))
  }
  if (strict) specqr_abort("raster colors must be hex RGB/RGBA, black, white, or transparent", "INVALID_COLOR")
  NULL
}
.render_channels <- function(x) {
  if (is.character(x)) return(parse_color(x, strict = TRUE))
  if (!(is.integer(x) || is.double(x)) || is.object(x) || !is.null(dim(x)) || length(x) != 4L || anyNA(x) || any(!is.finite(x) | x < 0 | x > 255 | x != floor(x)))
    specqr_abort("color channels must contain four integers from 0 to 255", "INVALID_COLOR")
  x
}
contrast_ratio <- function(foreground, background) {
  fg <- .render_channels(foreground); bg <- .render_channels(background)
  back <- bg[1:3] / 255 * bg[4] / 255 + 1 - bg[4] / 255
  front <- fg[1:3] / 255 * fg[4] / 255 + back * (1 - fg[4] / 255)
  linear <- function(v) ifelse(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055)^2.4)
  a <- sum(linear(front) * c(0.2126, 0.7152, 0.0722)); b <- sum(linear(back) * c(0.2126, 0.7152, 0.0722))
  (max(a, b) + 0.05) / (min(a, b) + 0.05)
}
render_dimensions <- function(x, margin = NULL, scale = NULL, dpi = NULL) {
  g <- .render_geometry(x, margin, scale); p <- .render_args(x, margin, scale, dpi = dpi)$dpi
  out <- list(width = g$dimension, height = g$dimension, module_pixels = g$scale, margin_modules = g$margin, dpi = NULL, module_size_mm = NULL, symbol_size_mm = NULL)
  if (!is.null(p)) {
    if (!(is.integer(p) || is.double(p)) || is.object(p) || length(p) != 1L || !is.null(dim(p)) || is.na(p) || !is.finite(p) || p <= 0)
      specqr_abort("print DPI must be finite and positive")
    module <- g$scale / p * 25.4; size <- g$dimension / p * 25.4
    if (!is.finite(module) || !is.finite(size) || module <= 0 || size <= 0) specqr_abort("physical dimensions must be finite and positive")
    out$dpi <- p; out$module_size_mm <- module; out$symbol_size_mm <- size
  }
  out
}
.render_xml <- function(s) {
  for (pair in list(c("&", "&amp;"), c("<", "&lt;"), c(">", "&gt;"), c('"', "&quot;"), c("'", "&apos;"))) s <- gsub(pair[1L], pair[2L], s, fixed = TRUE)
  s
}
to_svg <- function(x, margin = NULL, scale = NULL, foreground = NULL, background = NULL) {
  g <- .render_geometry(x, margin, scale); a <- .render_args(x, margin, scale, foreground, background)
  fg <- .render_xml(.render_color_text(a$foreground)); bg <- .render_xml(.render_color_text(a$background))
  black <- which(g$matrix, arr.ind = TRUE); d <- format(g$dimension, scientific = FALSE, trim = TRUE)
  if (nrow(black) * (7 + 2 * nchar(d) + 3 * nchar(as.character(g$scale))) + 512 > SVG_CHARACTER_BUDGET) specqr_abort("SVG exceeds character budget")
  if (nrow(black)) black <- black[order(black[, 1L], black[, 2L]), , drop = FALSE]
  f <- function(v) format(v, scientific = FALSE, trim = TRUE)
  path <- paste0("M", f((black[, 2L] - 1 + g$margin) * g$scale), ",", f((black[, 1L] - 1 + g$margin) * g$scale), "h", g$scale, "v", g$scale, "h-", g$scale, "z", collapse = "")
  if (!nrow(black)) path <- ""
  paste0('<svg xmlns="http://www.w3.org/2000/svg" width="', d, '" height="', d, '" viewBox="0 0 ', d, ' ', d, '" role="img"><rect width="100%" height="100%" fill="', bg, '"/><path fill="', fg, '" d="', path, '"/></svg>')
}
to_pixels <- function(x, margin = NULL, scale = NULL, foreground = NULL, background = NULL) {
  g <- .render_geometry(x, margin, scale, TRUE); a <- .render_args(x, margin, scale, foreground, background)
  fg <- as.raw(parse_color(a$foreground, TRUE)); bg <- as.raw(parse_color(a$background, TRUE)); d <- as.integer(g$dimension)
  module <- (seq_len(d) - 1L) %/% g$scale - g$margin + 1L; inside <- module >= 1L & module <= nrow(g$matrix)
  padded <- matrix(FALSE, d, d); padded[inside, inside] <- g$matrix[module[inside], module[inside], drop = FALSE]
  indices <- which(as.vector(t(padded))) - 1L; data <- rep(bg, d * d)
  for (channel in 1:4) data[4L * indices + channel] <- fg[channel]
  structure(list(width = d, height = d, pixels = data), class = "specqr_pixels")
}
render_rgba <- function(x, ...) { p <- to_pixels(x, ...); list(width = p$width, height = p$height, data = p$pixels) }
# Split unsigned CRC into 16-bit halves: R's signed INT_MIN is reserved for NA.
.png_crc_table <- local({
  hi <- lo <- integer(256L)
  for (index in 0:255) {
    h <- 0L; l <- index
    for (k in 1:8) {
      odd <- bitwAnd(l, 1L) != 0L
      l <- bitwOr(bitwShiftR(l, 1L), bitwShiftL(bitwAnd(h, 1L), 15L)); h <- bitwShiftR(h, 1L)
      if (odd) { h <- bitwXor(h, 60856L); l <- bitwXor(l, 33568L) }
    }
    hi[index + 1L] <- h; lo[index + 1L] <- l
  }
  list(hi = hi, lo = lo)
})
.png_crc <- function(bytes) {
  h <- 65535L; l <- 65535L; th <- .png_crc_table$hi; tl <- .png_crc_table$lo
  for (b in as.integer(bytes)) {
    i <- bitwAnd(bitwXor(l, b), 255L) + 1L
    l <- bitwXor(bitwOr(bitwShiftR(l, 8L), bitwShiftL(bitwAnd(h, 255L), 8L)), tl[i]); h <- bitwXor(bitwShiftR(h, 8L), th[i])
  }
  as.double(bitwXor(h, 65535L)) * 65536 + bitwXor(l, 65535L)
}
.png_adler <- function(bytes) {
  a <- 1; b <- 0; n <- length(bytes)
  if (n) for (start in seq.int(1L, n, by = 5552L)) {
    v <- as.integer(bytes[seq.int(start, min(n, start + 5551L))]); count <- length(v)
    b <- (b + count * a + sum(v * rev(seq_len(count)))) %% 65521
    a <- (a + sum(v)) %% 65521
  }
  b * 65536 + a
}
.png_be32 <- function(n) as.raw(floor(n / c(16777216, 65536, 256, 1)) %% 256)
.png_chunk <- function(kind, data) { content <- c(charToRaw(kind), data); c(.png_be32(length(data)), content, .png_be32(.png_crc(content))) }
to_png <- function(x, ...) {
  p <- to_pixels(x, ...); stride <- 4L * p$width
  scan <- as.raw(rbind(0L, matrix(as.integer(p$pixels), nrow = stride)))
  n <- length(scan); blocks <- vector("list", ceiling(n / 65535L))
  for (i in seq_along(blocks)) {
    start <- (i - 1L) * 65535L + 1L; count <- min(65535L, n - start + 1L); inv <- 65535L - count
    blocks[[i]] <- c(as.raw(c(as.integer(i == length(blocks)), count %% 256L, count %/% 256L, inv %% 256L, inv %/% 256L)), scan[seq.int(start, start + count - 1L)])
  }
  z <- c(as.raw(c(120L, 1L)), do.call(c, blocks), .png_be32(.png_adler(scan)))
  header <- c(.png_be32(p$width), .png_be32(p$height), as.raw(c(8, 6, 0, 0, 0)))
  c(as.raw(c(137, 80, 78, 71, 13, 10, 26, 10)), .png_chunk("IHDR", header), .png_chunk("IDAT", z), .png_chunk("IEND", raw()))
}
.base64_encode <- function(bytes) {
  n <- length(bytes); if (!n) return("")
  alphabet <- strsplit("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", "", fixed = TRUE)[[1L]]
  pad <- (3L - n %% 3L) %% 3L; v <- matrix(c(as.integer(bytes), rep.int(0L, pad)), nrow = 3L)
  out <- rbind(v[1L, ] %/% 4L, (v[1L, ] %% 4L) * 16L + v[2L, ] %/% 16L, (v[2L, ] %% 16L) * 4L + v[3L, ] %/% 64L, v[3L, ] %% 64L)
  chars <- alphabet[as.vector(out) + 1L]; if (pad) chars[seq.int(length(chars) - pad + 1L, length(chars))] <- "="
  paste0(chars, collapse = "")
}
to_svg_data_url <- function(x, ...) {
  s <- to_svg(x, ...); bytes <- as.integer(charToRaw(s))
  if (3 * length(bytes) + 31 > DATA_URL_CHARACTER_BUDGET) specqr_abort("SVG data URL exceeds character budget")
  safe <- bytes %in% as.integer(charToRaw("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789~!*'()-._"))
  pieces <- sprintf("%%%02X", bytes); pieces[safe] <- rawToChar(as.raw(bytes[safe]), multiple = TRUE)
  paste0("data:image/svg+xml;charset=utf-8,", paste0(pieces, collapse = ""))
}
to_png_data_url <- function(x, ...) {
  p <- to_png(x, ...)
  if (4 * ceiling(length(p) / 3) + 22 > DATA_URL_CHARACTER_BUDGET) specqr_abort("PNG data URL exceeds character budget")
  paste0("data:image/png;base64,", .base64_encode(p))
}
to_data_url <- function(x, format = "png", ...) {
  f <- scalar_text(format, "data URL format", "INVALID_OUTPUT")
  if (f == "png") return(to_png_data_url(x, ...))
  if (f == "svg") return(to_svg_data_url(x, ...))
  specqr_abort("data URL format must be png or svg", "INVALID_OUTPUT")
}
render <- function(x, format = "svg", ...) {
  f <- scalar_text(format, "render format", "INVALID_OUTPUT")
  switch(f, svg = to_svg(x, ...), png = to_png(x, ...), pixels = to_pixels(x, ...), rgba = render_rgba(x, ...),
         `data-url` = to_data_url(x, ...), `svg-data-url` = to_svg_data_url(x, ...), `png-data-url` = to_png_data_url(x, ...),
         specqr_abort("render format must be svg, png, pixels, rgba, or a data URL format", "INVALID_OUTPUT"))
}

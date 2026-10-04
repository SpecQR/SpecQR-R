# Native R finite-field coding, Model 2 placement, and SpecQR mask scoring.
.MAX_CODEWORDS <- 3706L
.core_bytes <- function(data, label) {
  if ((!is.raw(data) && !is.integer(data) && !is.double(data)) || is.object(data) || !is.null(dim(data)))
    specqr_abort(paste0(label, " must be a finite byte sequence"))
  if (length(data) > .MAX_CODEWORDS) specqr_abort(paste0(label, " exceeds the maximum QR codeword count"))
  .byte_sequence(data, label, .MAX_CODEWORDS)
}
pad_data_bits <- function(bits, version, level) {
  capacity <- data_codeword_count(version, level)
  if ((!is.integer(bits) && !is.double(bits)) || is.object(bits) || !is.null(dim(bits)))
    specqr_abort("Bits must be a finite sequence of integer 0/1 values")
  n <- length(bits)
  if (n > capacity * 8L) specqr_abort(paste0("Input requires ", n, " bits, but version ", version, "-", level,
                                          " has ", capacity * 8L, " data bits"), "DATA_TOO_LONG")
  if (anyNA(bits) || any(!is.finite(bits)) || any(!(bits %in% c(0L, 1L)))) specqr_abort("Bits must contain only integer 0/1 values")
  result <- integer(capacity)
  if (n) {
    padded <- c(as.integer(bits), integer((8L - n %% 8L) %% 8L))
    packed <- as.integer(colSums(matrix(padded, nrow = 8L) * 2^(7L:0L)))
    result[seq_along(packed)] <- packed
  }
  terminated <- n + min(4L, capacity * 8L - n)
  padded_bytes <- (terminated + 7L) %/% 8L
  if (padded_bytes < capacity) result[seq.int(padded_bytes + 1L, capacity)] <- rep(c(0xecL, 0x11L), length.out = capacity - padded_bytes)
  as.raw(result)
}
encode_data <- function(segments, version, level) pad_data_bits(segments_bits(segments, version), version, level)

# Tables are derived with the QR reduction polynomial, not a platform codec.
.GF_TABLES <- local({
  exponents <- integer(510L); logarithms <- integer(256L); value <- 1L
  for (i in 0L:254L) {
    exponents[i + 1L] <- value; logarithms[value + 1L] <- i
    value <- bitwShiftL(value, 1L)
    if (value >= 256L) value <- bitwXor(value, 0x11dL)
  }
  exponents[256L:510L] <- exponents[1L:255L]
  list(exp = exponents, log = logarithms)
})
.gf_multiply <- function(left, right) {
  result <- .GF_TABLES$exp[.GF_TABLES$log[left + 1L] + .GF_TABLES$log[right + 1L] + 1L]
  result[left == 0L | right == 0L] <- 0L
  result
}
gf_multiply <- function(left, right) {
  a <- scalar_integer(left, 0, 255, "Left operand"); b <- scalar_integer(right, 0, 255, "Right operand")
  .gf_multiply(a, b)
}
.divisor <- function(degree) {
  coefficients <- integer(degree + 1L); coefficients[1L] <- 1L; root <- 1L
  for (factor in 0L:(degree - 1L)) {
    indices <- seq_len(factor + 1L)
    coefficients[indices + 1L] <- bitwXor(coefficients[indices + 1L], .gf_multiply(coefficients[indices], root))
    root <- .gf_multiply(root, 2L)
  }
  coefficients
}
reed_solomon_divisor <- function(degree) as.raw(.divisor(scalar_integer(degree, 1, 255, "Reed-Solomon degree")))
.remainder <- function(data, divisor) {
  degree <- length(divisor) - 1L; result <- integer(degree)
  tail <- divisor[-1L]
  for (value in as.integer(data)) {
    factor <- bitwXor(value, result[1L])
    result <- bitwXor(c(result[-1L], 0L), .gf_multiply(tail, factor))
  }
  as.raw(result)
}
reed_solomon_remainder <- function(data, degree) .remainder(.core_bytes(data, "Data"), as.integer(reed_solomon_divisor(degree)))
interleave_codewords <- function(data, version, level) {
  info <- block_info(version, level); bytes <- .core_bytes(data, "Data codewords")
  if (length(bytes) != info$data_codewords) specqr_abort(paste0("Expected ", info$data_codewords, " data codewords; got ", length(bytes)))
  short_count <- info$blocks - info$raw_codewords %% info$blocks
  short_length <- info$raw_codewords %/% info$blocks - info$ecc_per_block
  divisor <- .divisor(info$ecc_per_block); blocks <- vector("list", info$blocks); offset <- 0L
  for (i in seq_len(info$blocks)) {
    n <- short_length + as.integer(i > short_count)
    block_data <- bytes[seq.int(offset + 1L, length.out = n)]
    blocks[[i]] <- list(data = block_data, ecc = .remainder(block_data, divisor)); offset <- offset + n
  }
  result <- raw(info$raw_codewords); at <- 0L
  for (column in seq_len(short_length + 1L)) for (block in blocks) if (column <= length(block$data)) {
    at <- at + 1L; result[at] <- block$data[column]
  }
  for (column in seq_len(info$ecc_per_block)) for (block in blocks) {
    at <- at + 1L; result[at] <- block$ecc[column]
  }
  if (offset != length(bytes) || at != length(result)) specqr_abort("Inconsistent QR block interleaving length")
  list(codewords = result, blocks = blocks, data_codewords = info$data_codewords,
       error_correction_codewords = info$raw_codewords - info$data_codewords, total_codewords = info$raw_codewords)
}
add_error_correction <- interleave_codewords
.mask_condition <- function(mask, x, y) {
  switch(as.character(mask), `0` = (x + y) %% 2L == 0L, `1` = y %% 2L == 0L,
    `2` = x %% 3L == 0L, `3` = (x + y) %% 3L == 0L, `4` = (y %/% 2L + x %/% 3L) %% 2L == 0L,
    `5` = (x * y) %% 2L + (x * y) %% 3L == 0L, `6` = ((x * y) %% 2L + (x * y) %% 3L) %% 2L == 0L,
    `7` = ((x + y) %% 2L + (x * y) %% 3L) %% 2L == 0L)
}
mask_condition <- function(mask, x, y) {
  .mask_condition(scalar_integer(mask, 0, 7, "Mask pattern"), scalar_integer(x, 0, 176, "Column"), scalar_integer(y, 0, 176, "Row"))
}
.line_penalty <- function(line) {
  runs <- rle(line)$lengths; penalty <- sum(runs[runs >= 5L] - 2L)
  n <- length(line)
  if (n >= 11L) {
    starts <- seq_len(n - 10L); first <- rep(TRUE, length(starts)); second <- first
    a <- c(TRUE, FALSE, TRUE, TRUE, TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE)
    b <- rev(a)
    for (i in 1L:11L) { first <- first & (line[starts + i - 1L] == a[i]); second <- second & (line[starts + i - 1L] == b[i]) }
    penalty <- penalty + 40L * (sum(first) + sum(second))
  }
  penalty
}
.penalty_score <- function(matrix) {
  side <- nrow(matrix); score <- 0L
  for (i in seq_len(side)) score <- score + .line_penalty(matrix[i, ]) + .line_penalty(matrix[, i])
  if (side > 1L) {
    i <- seq_len(side - 1L); j <- i + 1L
    score <- score + 3L * sum(matrix[i, i, drop = FALSE] == matrix[i, j, drop = FALSE] &
      matrix[i, i, drop = FALSE] == matrix[j, i, drop = FALSE] & matrix[i, i, drop = FALSE] == matrix[j, j, drop = FALSE])
  }
  total <- side * side; dark <- sum(matrix)
  as.integer(score + (abs(dark * 20L - total * 10L) %/% total) * 10L)
}
penalty_score <- function(matrix) {
  if (!is.matrix(matrix) || !is.logical(matrix) || is.object(matrix) || anyNA(matrix) ||
      nrow(matrix) < 1L || nrow(matrix) > 177L || nrow(matrix) != ncol(matrix))
    specqr_abort("Matrix must be a square 1 to 177 matrix of non-missing logical modules")
  .penalty_score(matrix)
}
.new_grid <- function(side) {
  grid <- new.env(parent = emptyenv()); grid$side <- side
  grid$modules <- matrix(FALSE, side, side); grid$functions <- matrix(FALSE, side, side); grid
}
.function_module <- function(grid, x, y, dark) {
  if (x >= 0L && x < grid$side && y >= 0L && y < grid$side) {
    grid$modules[y + 1L, x + 1L] <- dark != 0L; grid$functions[y + 1L, x + 1L] <- TRUE
  }
  invisible(NULL)
}
.finder <- function(grid, left, top) {
  for (dy in -1L:7L) for (dx in -1L:7L) {
    inside <- dx >= 0L && dx <= 6L && dy >= 0L && dy <= 6L
    dark <- inside && (dx %in% c(0L, 6L) || dy %in% c(0L, 6L) || (dx >= 2L && dx <= 4L && dy >= 2L && dy <= 4L))
    .function_module(grid, left + dx, top + dy, dark)
  }
}
.draw_format <- function(grid, level, mask) {
  data <- bitwOr(bitwShiftL(format_bits(level), 3L), mask); remainder <- data
  for (i in 1L:10L) remainder <- bitwXor(bitwShiftL(remainder, 1L), bitwAnd(bitwShiftR(remainder, 9L), 1L) * 0x537L)
  bits <- bitwXor(bitwOr(bitwShiftL(data, 10L), remainder), 0x5412L)
  bit <- function(i) bitwAnd(bitwShiftR(bits, i), 1L)
  for (i in 0L:5L) .function_module(grid, 8L, i, bit(i))
  .function_module(grid, 8L, 7L, bit(6L)); .function_module(grid, 8L, 8L, bit(7L)); .function_module(grid, 7L, 8L, bit(8L))
  for (i in 9L:14L) .function_module(grid, 14L - i, 8L, bit(i))
  for (i in 0L:7L) .function_module(grid, grid$side - 1L - i, 8L, bit(i))
  for (i in 8L:14L) .function_module(grid, 8L, grid$side - 15L + i, bit(i))
}
.draw_functions <- function(grid, version, level) {
  .finder(grid, 0L, 0L); .finder(grid, grid$side - 7L, 0L); .finder(grid, 0L, grid$side - 7L)
  for (i in 8L:(grid$side - 9L)) { .function_module(grid, i, 6L, i %% 2L == 0L); .function_module(grid, 6L, i, i %% 2L == 0L) }
  positions <- alignment_positions(version); last <- length(positions)
  for (yi in seq_along(positions)) for (xi in seq_along(positions)) {
    if ((xi == 1L && yi == 1L) || (xi == last && yi == 1L) || (xi == 1L && yi == last)) next
    for (dy in -2L:2L) for (dx in -2L:2L) .function_module(grid, positions[xi] + dx, positions[yi] + dy, max(abs(dx), abs(dy)) != 1L)
  }
  .draw_format(grid, level, 0L); .function_module(grid, 8L, grid$side - 8L, TRUE)
  if (version >= 7L) {
    remainder <- as.integer(version)
    for (i in 1L:12L) remainder <- bitwXor(bitwShiftL(remainder, 1L), bitwAnd(bitwShiftR(remainder, 11L), 1L) * 0x1f25L)
    bits <- bitwOr(bitwShiftL(as.integer(version), 12L), remainder)
    for (i in 0L:17L) {
      a <- grid$side - 11L + i %% 3L; b <- i %/% 3L; dark <- bitwAnd(bitwShiftR(bits, i), 1L)
      .function_module(grid, a, b, dark); .function_module(grid, b, a, dark)
    }
  }
}
.draw_codewords <- function(grid, codewords) {
  bytes <- as.integer(codewords); bit_index <- 0L; right <- grid$side - 1L; nbits <- length(bytes) * 8L
  while (right >= 1L) {
    if (right == 6L) right <- 5L
    for (vertical in 0L:(grid$side - 1L)) {
      y <- if (bitwAnd(right + 1L, 2L) == 0L) grid$side - 1L - vertical else vertical
      for (x in c(right, right - 1L)) if (!grid$functions[y + 1L, x + 1L]) {
        if (bit_index < nbits) grid$modules[y + 1L, x + 1L] <- bitwAnd(bitwShiftR(bytes[bit_index %/% 8L + 1L], 7L - bit_index %% 8L), 1L) != 0L
        bit_index <- bit_index + 1L
      }
    }
    right <- right - 2L
  }
  if (bit_index - nbits < 0L || bit_index - nbits > 7L) specqr_abort("Inconsistent QR data-module count")
}
.masked <- function(grid, level, mask) {
  candidate <- .new_grid(grid$side); candidate$functions <- grid$functions
  flip <- !grid$functions & .mask_condition(mask, col(grid$modules) - 1L, row(grid$modules) - 1L)
  candidate$modules <- xor(grid$modules, flip)
  .draw_format(candidate, level, mask); candidate$modules
}
build_matrix <- function(codewords, version, level, mask = NULL, mask_pattern = NULL) {
  if (!is.null(mask_pattern)) {
    if (!is.null(mask)) specqr_abort("Specify mask only once")
    mask <- mask_pattern
  }
  side <- qr_size(version); validate_level(level)
  if (!is.null(mask)) mask <- scalar_integer(mask, 0, 7, "Mask pattern")
  bytes <- .core_bytes(codewords, "Interleaved codewords"); expected <- raw_codeword_count(version)
  if (length(bytes) != expected) specqr_abort(paste0("Expected ", expected, " interleaved codewords; got ", length(bytes)))
  base <- .new_grid(side); .draw_functions(base, as.integer(version), level); .draw_codewords(base, bytes)
  candidates <- if (is.null(mask)) 0L:7L else mask
  best <- NULL; best_mask <- 0L; best_penalty <- Inf; penalties <- vector("list", length(candidates))
  for (i in seq_along(candidates)) {
    m <- candidates[i]; candidate <- .masked(base, level, m); penalty <- .penalty_score(candidate)
    penalties[[i]] <- list(mask_pattern = m, penalty = penalty)
    if (is.null(best) || penalty < best_penalty) { best <- candidate; best_mask <- m; best_penalty <- penalty }
  }
  list(matrix = best, mask_pattern = best_mask, penalty = best_penalty, mask_penalties = penalties)
}
create_matrix <- build_matrix
select_best_mask <- build_matrix

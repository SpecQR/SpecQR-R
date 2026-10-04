# ISO/IEC 18004 Model 2 block tables; pinned SpecQR reference.
ERROR_CORRECTION_LEVEL_ORDER <- c("L", "M", "Q", "H")
.FORMAT_BITS <- c(1L, 0L, 3L, 2L)

ECC_CODEWORDS_PER_BLOCK <- list(
  c(7L,10L,15L,20L,26L,18L,20L,24L,30L,18L,20L,24L,26L,30L,22L,24L,28L,30L,28L,28L,28L,28L,30L,30L,26L,28L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L),
  c(10L,16L,26L,18L,24L,16L,18L,22L,22L,26L,30L,22L,22L,24L,24L,28L,28L,26L,26L,26L,26L,28L,28L,28L,28L,28L,28L,28L,28L,28L,28L,28L,28L,28L,28L,28L,28L,28L,28L,28L),
  c(13L,22L,18L,26L,18L,24L,18L,22L,20L,24L,28L,26L,24L,20L,30L,24L,28L,28L,26L,30L,28L,30L,30L,30L,30L,28L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L),
  c(17L,28L,22L,16L,22L,28L,26L,26L,24L,28L,24L,28L,22L,24L,24L,30L,28L,28L,26L,28L,30L,24L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L,30L)
)

NUM_ERROR_CORRECTION_BLOCKS <- list(
  c(1L,1L,1L,1L,1L,2L,2L,2L,2L,4L,4L,4L,4L,4L,6L,6L,6L,6L,7L,8L,8L,9L,9L,10L,12L,12L,12L,13L,14L,15L,16L,17L,18L,19L,19L,20L,21L,22L,24L,25L),
  c(1L,1L,1L,2L,2L,4L,4L,4L,5L,5L,5L,8L,9L,9L,10L,10L,11L,13L,14L,16L,17L,17L,18L,20L,21L,23L,25L,26L,28L,29L,31L,33L,35L,37L,38L,40L,43L,45L,47L,49L),
  c(1L,1L,2L,2L,4L,4L,6L,6L,8L,8L,8L,10L,12L,16L,12L,17L,16L,18L,21L,20L,23L,23L,25L,27L,29L,34L,34L,35L,38L,40L,43L,45L,48L,51L,53L,56L,59L,62L,65L,68L),
  c(1L,1L,2L,4L,4L,4L,5L,6L,8L,8L,11L,11L,16L,16L,18L,16L,19L,21L,25L,25L,25L,34L,30L,32L,35L,37L,40L,42L,45L,48L,51L,54L,57L,60L,63L,66L,70L,74L,77L,81L)
)
validate_version <- function(version) {
  scalar_integer(version, 1, 40, "QR version", "INVALID_VERSION")
  invisible(NULL)
}
validate_level <- function(level) {
  if (!is.character(level) || is.object(level) || length(level) != 1L ||
      !is.null(dim(level)) || is.na(level) || !(level %in% ERROR_CORRECTION_LEVEL_ORDER))
    specqr_abort("Error correction level must be one of L, M, Q, H", "INVALID_ECC_LEVEL")
  invisible(NULL)
}
level_index <- function(level) { validate_level(level); match(level, ERROR_CORRECTION_LEVEL_ORDER) }
format_bits <- function(level) .FORMAT_BITS[level_index(level)]
qr_size <- function(version) { validate_version(version); as.integer(version * 4 + 17) }
raw_codeword_count <- function(version) {
  validate_version(version)
  result <- (16 * version + 128) * version + 64
  if (version >= 2) {
    n <- version %/% 7 + 2
    result <- result - (25 * n - 10) * n + 55
    if (version >= 7) result <- result - 36
  }
  as.integer(result %/% 8)
}
block_info <- function(version, level) {
  validate_version(version); ordinal <- level_index(level)
  blocks <- NUM_ERROR_CORRECTION_BLOCKS[[ordinal]][version]
  ecc <- ECC_CODEWORDS_PER_BLOCK[[ordinal]][version]
  raw <- raw_codeword_count(version)
  list(blocks = blocks, ecc_per_block = ecc, raw_codewords = raw,
       data_codewords = raw - blocks * ecc)
}
data_codeword_count <- function(version, level) block_info(version, level)$data_codewords
alignment_positions <- function(version) {
  validate_version(version)
  if (version == 1) return(integer())
  n <- version %/% 7 + 2L; denominator <- n * 2L - 2L
  step <- if (version == 32) 26L else ((version * 4L + 4L + denominator - 1L) %/% denominator) * 2L
  as.integer(c(6L, qr_size(version) - 7L - ((n - 2L):0L) * step))
}
character_count_bits <- function(version, mode) {
  validate_version(version)
  scalar_text(mode, "Mode", "INVALID_MODE")
  widths <- switch(mode, numeric = c(10L, 12L, 14L), alphanumeric = c(9L, 11L, 13L),
                   byte = c(8L, 16L, 16L), kanji = c(8L, 10L, 12L), NULL)
  if (is.null(widths)) specqr_abort("Mode must be numeric, alphanumeric, byte, or kanji", "INVALID_MODE")
  widths[if (version <= 9) 1L else if (version <= 26) 2L else 3L]
}

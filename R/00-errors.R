# Checked, typed failures shared by every public input boundary.
specqr_abort <- function(message, code = "INVALID_INPUT", detail_code = NULL) {
  condition <- list(message = paste0(code, ": ", message), call = NULL,
                    code = code, detail_code = detail_code)
  class(condition) <- c(paste0("specqr_", tolower(code)), "specqr_error", "error", "condition")
  stop(condition)
}

scalar_integer <- function(value, lower, upper, label, code = "INVALID_INPUT") {
  if (!(is.integer(value) || is.double(value)) || is.object(value) ||
      length(value) != 1L || !is.null(dim(value)) || is.na(value) ||
      !is.finite(value) || value != floor(value) || value < lower || value > upper)
    specqr_abort(paste0(label, " must be an integer from ", lower, " to ", upper), code)
  as.integer(value)
}

scalar_flag <- function(value, label) {
  if (!is.logical(value) || is.object(value) || length(value) != 1L ||
      !is.null(dim(value)) || is.na(value))
    specqr_abort(paste0(label, " must be TRUE or FALSE"))
  value
}

scalar_text <- function(value, label, code = "INVALID_INPUT") {
  if (!is.character(value) || is.object(value) || length(value) != 1L ||
      !is.null(dim(value)) || is.na(value))
    specqr_abort(paste0(label, " must be one non-missing string"), code)
  value
}

error_code <- function(error) {
  if (!inherits(error, "specqr_error")) specqr_abort("Expected a SpecQR error")
  error$code
}

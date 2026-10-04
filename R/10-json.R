# Small strict JSON codec used by the CLI and development adapter. Base R only.
# JSON strings containing U+0000 are represented as tagged raw bytes internally,
# because R character scalars cannot contain NUL. Public text APIs reject these.
.json_fail <- function(message) specqr_abort(paste0("JSON: ", message), "INVALID_INPUT")
.json_raw_utf8 <- function(bytes) {
  b <- as.integer(bytes); n <- length(b); i <- 1L
  if(!any(b >= 128L)) return(invisible(TRUE))
  while (i <= n) {
    x <- b[i]
    if (x < 128L) { i <- i + 1L; next }
    k <- if (x >= 194L && x <= 223L) 1L else if (x >= 224L && x <= 239L) 2L else if (x >= 240L && x <= 244L) 3L else -1L
    if (k < 0L || i + k > n) .json_fail("invalid UTF-8")
    q <- b[seq.int(i + 1L, i + k)]
    if (any(q < 128L | q > 191L) || (x == 224L && q[1L] < 160L) || (x == 237L && q[1L] > 159L) || (x == 240L && q[1L] < 144L) || (x == 244L && q[1L] > 143L)) .json_fail("invalid UTF-8")
    i <- i + k + 1L
  }
  invisible(TRUE)
}
json_parse <- function(input) {
  if (is.character(input) && length(input) == 1L && !is.na(input)) input <- charToRaw(enc2utf8(input))
  if (!is.raw(input) || length(input) > 8000000L) .json_fail("input must be bounded text or raw bytes")
  .json_raw_utf8(input)
  b <- as.integer(input); n <- length(b); at <- 1L; values <- 0L
  space <- function() { while (at <= n && b[at] %in% c(32L,9L,10L,13L)) at <<- at + 1L }
  hex4 <- function() {
    if (at + 3L > n) .json_fail("incomplete Unicode escape")
    x <- b[seq.int(at,at+3L)]; at <<- at + 4L
    d <- ifelse(x >= 48L & x <= 57L,x-48L,ifelse(x >= 65L & x <= 70L,x-55L,ifelse(x >= 97L & x <= 102L,x-87L,-1L)))
    if (any(d < 0L)) .json_fail("invalid Unicode escape")
    sum(d * c(4096,256,16,1))
  }
  string <- function() {
    at <<- at + 1L; parts <- list(); count <- 0L
    append <- function(v) { count <<- count+1L; parts[[count]] <<- v }
    while (at <= n) {
      x <- b[at]; at <<- at + 1L
      if (x == 34L) {
        raw <- as.raw(unlist(parts,use.names=FALSE)); .json_raw_utf8(raw)
        if (any(raw == as.raw(0))) return(structure(raw,class="specqr_json_nultext"))
        value <- rawToChar(raw); Encoding(value) <- "UTF-8"; return(value)
      }
      if (x == 92L) {
        if (at > n) .json_fail("incomplete escape")
        x <- b[at]; at <<- at + 1L
        if (x == 117L) {
          u <- hex4()
          if (u >= 55296 && u <= 56319) {
            if (at+1L > n || b[at] != 92L || b[at+1L] != 117L) .json_fail("unpaired high surrogate")
            at <<- at+2L; lo <- hex4()
            if (lo < 56320 || lo > 57343) .json_fail("invalid low surrogate")
            u <- 65536+(u-55296)*1024+(lo-56320)
          } else if (u >= 56320 && u <= 57343) .json_fail("unpaired low surrogate")
          append(if (u == 0) as.raw(0) else charToRaw(intToUtf8(u)))
        } else if (x %in% c(34L,92L,47L)) append(as.raw(x)) else {
          e <- match(x,c(98L,102L,110L,114L,116L))
          if (is.na(e)) .json_fail("invalid escape")
          append(as.raw(c(8L,12L,10L,13L,9L)[e]))
        }
      } else {
        if (x < 32L) .json_fail("unescaped control character")
        start <- at-1L
        while (at <= n && b[at] >= 32L && !b[at] %in% c(34L,92L)) at <<- at+1L
        append(input[seq.int(start,at-1L)])
      }
    }
    .json_fail("unterminated string")
  }
  value <- function(depth=0L) {
    if (depth > 64L) .json_fail("nesting limit exceeded")
    values <<- values+1L; if (values > 1000000L) .json_fail("value limit exceeded")
    space(); if (at > n) .json_fail("expected value")
    x <- b[at]
    if (x == 34L) return(string())
    if (x %in% c(123L,91L)) {
      object <- x == 123L; close <- if(object) 125L else 93L; at <<- at+1L;space()
      out <- list(); if (object) names(out) <- character()
      if(at <= n && b[at] == close) { at <<- at+1L; return(structure(out,class=if(object) "specqr_json_object" else "specqr_json_array")) }
      repeat {
        key <- NULL
        if(object) {
          if(at > n || b[at] != 34L) .json_fail("object key must be a string")
          key <- string(); if (!is.character(key)) .json_fail("NUL is not permitted in object keys")
          if(key %in% names(out)) .json_fail("duplicate object key")
          space();if(at > n || b[at] != 58L) .json_fail("expected colon");at <<- at+1L
        }
        v <- value(depth+1L); index <- length(out)+1L; out[index] <- list(v)
        if(object) names(out)[index] <- key
        space();if(at > n) .json_fail("unterminated container")
        sep <- b[at];at <<- at+1L
        if(sep == close) return(structure(out,class=if(object) "specqr_json_object" else "specqr_json_array"))
        if(sep != 44L) .json_fail("expected comma")
        space()
      }
    }
    if(x %in% c(116L,102L,110L)) {
      token <- if(x == 116L) "true" else if(x == 102L) "false" else "null"
      bytes <- charToRaw(token);last <- at+length(bytes)-1L
      if(last > n || !identical(input[seq.int(at,last)],bytes)) .json_fail("invalid literal")
      at <<- last+1L
      return(if(x == 116L) TRUE else if(x == 102L) FALSE else NULL)
    }
    if(x == 45L || (x >= 48L && x <= 57L)) {
      start <- at
      while(at <= n && b[at] %in% c(45L,43L,46L,101L,69L,48:57)) at <<- at+1L
      if(at-start > 128L) .json_fail("number token too long")
      token <- rawToChar(input[seq.int(start,at-1L)])
      if(!grepl("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$",token)) .json_fail("invalid number")
      v <- suppressWarnings(as.numeric(token));if(!is.finite(v)) .json_fail("non-finite number")
      if(!grepl("[.eE]",token) && abs(v) > 9007199254740991) .json_fail("integer outside exact range")
      return(v)
    }
    .json_fail("unexpected character")
  }
  result <- value();space();if(at != n+1L) .json_fail("trailing data");result
}
.json_quote <- function(x) {
  if(!is.character(x) || length(x)!=1L || is.na(x)) .json_fail("invalid string")
  x <- enc2utf8(x); .json_raw_utf8(charToRaw(x))
  x <- gsub("\\", "\\\\", x, fixed=TRUE, useBytes=TRUE)
  x <- gsub('"', '\\"', x, fixed=TRUE, useBytes=TRUE)
  for(v in 1:31) x <- gsub(rawToChar(as.raw(v)), sprintf("\\u%04x",v), x, fixed=TRUE, useBytes=TRUE)
  paste0('"',x,'"')
}
json_stringify <- function(value) {
  visited <- 0; emitted <- 0
  budget <- function(n) { emitted <<- emitted + n; if(emitted > 32000000) .json_fail("output resource limit exceeded") }
  encode <- function(x,depth=0L) {
    visited <<- visited + 1
    if(visited > 1000000) .json_fail("output value limit exceeded")
    if(depth > 64L) .json_fail("output nesting limit exceeded")
    if(is.null(x)) {budget(4);return("null")}
    if(is.list(x)) {
      budget(length(x)+2)
      object <- inherits(x,"specqr_json_object") || (!is.null(names(x)) && length(x)>0L)
      if(object) {
        if(is.null(names(x)) || anyNA(names(x)) || anyDuplicated(names(x))) .json_fail("invalid object names")
        pairs <- vapply(seq_along(x),function(i) {key <- .json_quote(names(x)[i]);budget(nchar(key,type="bytes")+1);paste0(key,":",encode(x[[i]],depth+1L))},character(1))
        return(paste0("{",paste0(pairs,collapse=","),"}"))
      }
      return(paste0("[",paste0(vapply(x,encode,character(1),depth=depth+1L),collapse=","),"]"))
    }
    if(is.raw(x)) x <- as.integer(x)
    if(!is.atomic(x) || is.object(x) || !is.null(dim(x)) || !(is.character(x)||is.logical(x)||is.numeric(x))) .json_fail("unsupported output value")
    if(length(x)!=1L) {budget(length(x)+2);return(paste0("[",paste0(vapply(as.list(x),encode,character(1),depth=depth+1L),collapse=","),"]"))}
    if(is.na(x)) .json_fail("cannot encode NA")
    if(is.character(x)) {budget(nchar(x,type="bytes")+2);q <- .json_quote(x);budget(nchar(q,type="bytes")-nchar(x,type="bytes")-2);return(q)}
    if(is.logical(x)) {budget(5);return(if(x) "true" else "false")}
    if(is.numeric(x) && !is.object(x) && is.finite(x)) {q <- format(x,digits=17L,scientific=FALSE,trim=TRUE,decimal.mark=".");budget(nchar(q));return(q)}
    .json_fail("unsupported output value")
  }
  out <- encode(value);if(nchar(out,type="bytes") > 32000000L) .json_fail("output resource limit exceeded");out
}

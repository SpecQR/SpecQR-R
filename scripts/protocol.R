# Development-only adapter. Runs the actual R source, without contributed packages.
.wire_object <- function(x) { if(!is.list(x) || is.null(names(x))) specqr_abort("Expected an object"); x }
.wire_array <- function(x) { if(!is.list(x) || (!is.null(names(x)) && length(x))) specqr_abort("Expected an array"); x }
.wire_integer <- function(x) { if(!is.numeric(x) || is.object(x) || length(x)!=1L || is.na(x) || !is.finite(x) || x!=floor(x) || abs(x)>9007199254740991) specqr_abort("Expected an exact integer");x }
.wire_text <- function(x) { if(!is.character(x) || length(x)!=1L || is.na(x)) specqr_abort("Expected a string");x }
.wire_bytes <- function(x) {
  x <- .wire_array(x);if(length(x)>1000000L) specqr_abort("Payload resource limit exceeded","DATA_TOO_LONG")
  nums <- vapply(x,.wire_integer,numeric(1));if(any(nums<0 | nums>255)) specqr_abort("Byte outside 0..255");as.raw(nums)
}
.wire_segment <- function(d) {
  d <- .wire_object(d);mode <- .wire_text(d$mode)
  if(mode %in% c("numeric","alphanumeric","kanji","byte")) {
    data <- if("bytes" %in% names(d)) .wire_bytes(d$bytes) else if("text" %in% names(d)) d$text else d$data
    if(inherits(data,"specqr_json_nultext")) data <- unclass(data)
    if(mode == "byte" && is.list(data)) data <- .wire_bytes(data)
    return(segment(mode,data))
  }
  if(mode == "eci") return(segment(mode,assignment_number=.wire_integer(d$assignmentNumber)))
  if(mode == "fnc1") return(segment(mode))
  if(mode == "fnc1-second") return(segment(mode,application_indicator=.wire_text(d$applicationIndicator)))
  if(mode == "structured-append") return(segment(mode,index=.wire_integer(d$index),total=.wire_integer(d$total),parity=.wire_integer(d$parity)))
  specqr_abort("Unknown segment mode","INVALID_MODE")
}
.wire_options <- function(d) {
  d <- .wire_object(d)
  map <- c(errorCorrectionLevel="error_correction_level",version="version",minVersion="min_version",maxVersion="max_version",maskPattern="mask_pattern",mode="mode",optimizeSegments="optimize_segments",boostErrorCorrection="boost_error_correction",allowKanji="allow_kanji",eci="eci",gs1="gs1",fnc1="fnc1",fnc1Second="fnc1_second",margin="margin",scale="scale",foreground="foreground",background="background",printDpi="print_dpi",structuredAppend="structured_append")
  unknown <- setdiff(names(d),c(names(map),"maxSymbols","output"))
  if(length(unknown)) specqr_abort(paste0("Unknown option: ",unknown[1L]))
  if("output" %in% names(d) && !identical(d$output,"matrix")) specqr_abort("Development adapter output must be matrix")
  out <- list()
  for(key in intersect(names(d),names(map))) {
    v <- d[[key]]
    if(key %in% c("version","minVersion","maxVersion","maskPattern") && !is.null(v)) v <- if(identical(v,"auto")) NULL else .wire_integer(v)
    if(key == "structuredAppend" && !is.null(v)) { v <- .wire_object(v);v$mode <- "structured-append";v <- .wire_segment(v) }
    out[map[[key]]] <- list(v)
  }
  do.call(specqr_options,out)
}
.wire_rows <- function(m) lapply(seq_len(nrow(m)),function(i) paste0(as.integer(m[i,]),collapse=""))
.wire_hex <- function(raw) paste0(sprintf("%02x",as.integer(raw)),collapse="")
.wire_base64 <- function(raw) {
  chars <- strsplit("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/","",fixed=TRUE)[[1L]]
  n <- length(raw);if(!n)return("");b<-as.integer(raw);pad<-(3L-n%%3L)%%3L;b<-c(b,rep(0L,pad));m<-matrix(b,nrow=3L)
  codes<-rbind(m[1L,]%/%4L,(m[1L,]%%4L)*16L+m[2L,]%/%16L,(m[2L,]%%16L)*4L+m[3L,]%/%64L,m[3L,]%%64L)
  out<-chars[as.vector(codes)+1L];if(pad)out[seq.int(length(out)-pad+1L,length(out))]<-"=";paste0(out,collapse="")
}
.wire_packed <- function(m) {
  b<-as.integer(t(m));pad<-(8L-length(b)%%8L)%%8L;b<-c(b,rep(0L,pad));v<-colSums(matrix(b,nrow=8L)*c(128,64,32,16,8,4,2,1));.wire_base64(as.raw(v))
}
.wire_symbol <- function(q,r=list()) {
  out<-list(version=q$version,ecc=q$error_correction_level,mask=q$mask_pattern,data=.wire_hex(q$data_codewords),codewords=.wire_hex(q$codewords),matrix=.wire_rows(q$matrix),matrixPacked=.wire_packed(q$matrix),segments=lapply(q$segments,function(s)list(mode=s$mode,count=s$count)))
  if("pngScale" %in% names(r))out$png<-.wire_hex(to_png(q,scale=.wire_integer(r$pngScale)))
  if(isTRUE(r$diagnostics))out$diagnostics<-q$diagnostics
  if(isTRUE(r$renders)){out$svg<-to_svg(q);out$svgDataUrl<-to_svg_data_url(q);out$pngDataUrl<-to_png_data_url(q)}
  out
}
.wire_gs1 <- function(v) {
  if(is.list(v)){
    if(!is.null(names(v))) {
      map<-c(base_url="baseUrl",element_string="elementString",primary_ai="primaryAi",path_elements="pathElements",query_elements="queryElements",unknown_query="unknownQuery",has_separators="hasSeparators",element_index="elementIndex")
      for(i in seq_along(v))if(names(v)[i] %in% names(map))names(v)[i]<-map[[names(v)[i]]]
    }
    return(lapply(v,.wire_gs1))
  }
  v
}
.wire_request <- function(r) {
  r<-.wire_object(r);command<-if(is.null(r$command))"generate" else .wire_text(r$command)
  if(command=="gf")return(list(bytes=.wire_hex(as.raw(unlist(lapply(0:255,function(a)vapply(0:255,function(b)gf_multiply(a,b),numeric(1))),use.names=FALSE)))))
  if(command=="rs") {degree<-.wire_integer(r$degree);data<-as.raw((0:299*61+degree)%%256);return(list(generator=.wire_hex(reed_solomon_divisor(degree)),remainder=.wire_hex(reed_solomon_remainder(data,degree))))}
  if(command=="raw") {
    v<-.wire_integer(r$version);level<-.wire_text(r$ecc);seed<-.wire_integer(r$seed);mask<-.wire_integer(r$mask)
    if(seed<0 || seed>31)specqr_abort("Seed outside 0..31");validate_level(level);ordinal<-match(level,c("L","M","Q","H"))-1L
    i<-seq_len(data_codeword_count(v,level))-1L
    data<-as.raw(if(seed==0)rep(0L,length(i)) else if(seed==1)rep(255L,length(i)) else bitwAnd(bitwXor(as.integer(i*149+v*43+ordinal*89+seed*67),as.integer(floor(i/2^(seed+1L)))),255L))
    inter<-interleave_codewords(data,v,level);q<-build_matrix(inter$codewords,v,level,mask_pattern=if(mask<0)NULL else mask)
    return(list(data=.wire_hex(data),codewords=.wire_hex(inter$codewords),matrix=.wire_rows(q$matrix),matrixPacked=.wire_packed(q$matrix),mask=q$mask_pattern,penalty=q$penalty,penalties=lapply(q$mask_penalties,function(x)x$penalty)))
  }
  if(command=="gs1-build")return(list(value=create_gs1_element_string(r$elements)))
  if(command=="digital-link-build") {lo<-.wire_object(r$linkOptions);args<-list(elements=r$elements,base_url=lo$baseUrl);if("pathAis" %in% names(lo))args$path_ais<-unlist(lo$pathAis,use.names=FALSE);return(list(value=do.call(create_gs1_digital_link,args)))}
  if(command=="digital-link-parse")return(.wire_gs1(parse_gs1_digital_link(r$url)))
  if(command=="digital-link-validate")return(.wire_gs1(validate_gs1_digital_link(r$url)))
  if(command=="digital-link-normalize")return(list(value=normalize_gs1_digital_link(r$url)))
  rawopts<-if(is.null(r$options))structure(list(),names=character()) else r$options;o<-.wire_options(rawopts)
  if(command=="capacity") {cap<-get_capacity(o$version,o$error_correction_level,mode=o$mode);return(list(maximum=cap$maximum,dataCodewords=cap$data_codewords,capacityBits=cap$capacity_bits,countBits=cap$character_count_bits))}
  data<-if("segments" %in% names(r))lapply(.wire_array(r$segments),.wire_segment) else if("bytes" %in% names(r)).wire_bytes(r$bytes) else if(is.null(r$text))"" else r$text
  if(inherits(data,"specqr_json_nultext"))data<-unclass(data)
  if(command %in% c("estimate","plan")){p<-plan(data,o);return(list(fits=p$ok,version=p$capacity_version,requiredBits=p$data_bit_length,capacityBits=p$capacity_bits))}
  if(command=="structured-append") {
    max_symbols<-if(is.null(rawopts$maxSymbols))16L else .wire_integer(rawopts$maxSymbols)
    set<-generate_structured_append(data,o,max_symbols=max_symbols);symbols<-lapply(set$symbols,.wire_symbol,r=r)
    return(list(total=set$total,parity=set$parity,inputLength=set$input_length,byteLength=set$byte_length,symbols=symbols,versions=lapply(symbols,function(x)x$version),masks=lapply(symbols,function(x)x$mask)))
  }
  if(command=="generate")return(.wire_symbol(generate(data,o),r))
  specqr_abort("Unknown command")
}
run_request <- function(r) tryCatch(.wire_request(r),error=function(e)list(error=class(e)[1L],isSpecQRError=inherits(e,"specqr_error"),code=if(inherits(e,"specqr_error"))e$code else "INTERNAL_ERROR",message=conditionMessage(e)))

# Command-line interface. Payload files/stdin are binary and preserve every byte.
.specqr_cli_usage <- function() paste(c(
 "SpecQR R 0.1.0", "Usage: Rscript specqr.R [--text TEXT | --input FILE | --stdin | --bytes-hex HEX]",
 "  [--format svg|png|json|matrix] [--output FILE|-] [--ecc L|M|Q|H]",
 "  [--version 1..40] [--min-version N] [--max-version N] [--mask 0..7]",
 "  [--mode auto|numeric|alphanumeric|byte|kanji] [--scale N] [--margin N]",
 "  [--foreground COLOR] [--background COLOR] [--eci N] [--fnc1] [--gs1]",
 "  [--fnc1-second INDICATOR] [--no-optimize] [--no-kanji] [--boost] [--plan]",
 "Files and stdin are raw bytes; text input must be one valid Unicode string.",
 "Default format: SVG. Default output: stdout. --output does not create directories.",
 "Exit status: 0 success, 2 invalid input/capacity, 3 output failure."),collapse="\n")
.specqr_cli_read <- function(path=NULL) {
  if(is.null(path) && .Platform$OS.type != "unix") specqr_abort("Binary stdin is supported on Unix; use --input FILE on this platform")
  con <- tryCatch(file(if(is.null(path)) "/dev/stdin" else path,open="rb",raw=is.null(path)),error=function(e)specqr_abort("Unable to open input file","INVALID_INPUT"))
  on.exit(close(con),add=TRUE)
  result <- readBin(con,"raw",n=1000001L)
  if(length(result)>1000000L)specqr_abort("Input exceeds one-million-byte resource limit","DATA_TOO_LONG")
  result
}
.specqr_cli_write <- function(value,path=NULL) {
  std <- is.null(path)||identical(path,"-")
  if(std && !is.raw(value)) { cat(enc2utf8(value),"\n",sep=""); return(invisible(NULL)) }
  if(std && .Platform$OS.type != "unix") specqr_abort("Binary stdout is supported on Unix; use --output FILE on this platform","INVALID_OUTPUT")
  if(!is.raw(value))value <- charToRaw(enc2utf8(paste0(value,"\n")))
  con <- tryCatch(file(if(std) "/dev/stdout" else path,open="wb",raw=std),error=function(e)specqr_abort("Unable to open output file","INVALID_OUTPUT"))
  on.exit(close(con),add=TRUE)
  tryCatch(writeBin(value,con),error=function(e)specqr_abort("Unable to write output file","INVALID_OUTPUT"))
  invisible(NULL)
}
specqr_cli <- function(args=commandArgs(trailingOnly=TRUE)) {
  if(!is.character(args)||is.object(args)||!is.null(dim(args))||anyNA(args))specqr_abort("CLI arguments must be character strings")
  if(any(args %in% c("--help","-h"))){cat(.specqr_cli_usage(),"\n",sep="");return(invisible(0L))}
  if(identical(args,"--cli-version")){cat("SpecQR R 0.1.0\n");return(invisible(0L))}
  data <- NULL; has_data <- FALSE;format <- "svg";output <- NULL;planning <- FALSE;opts <- list();seen <- character();i<-1L
  numeric_flags<-c("--version"="version","--min-version"="min_version","--max-version"="max_version","--mask"="mask_pattern","--scale"="scale","--margin"="margin","--eci"="eci","--print-dpi"="print_dpi")
  text_flags<-c("--ecc"="error_correction_level","--mode"="mode","--foreground"="foreground","--background"="background","--fnc1-second"="fnc1_second")
  boolean_flags<-c("--fnc1"="fnc1","--gs1"="gs1","--no-optimize"="optimize_segments","--no-kanji"="allow_kanji","--boost"="boost_error_correction")
  while(i<=length(args)) {
    key<-args[i];i<-i+1L
    if(key %in% seen)specqr_abort(paste0("Duplicate argument: ",key));seen<-c(seen,key)
    if(key=="--plan"){planning<-TRUE;next}
    if(key %in% names(boolean_flags)){opts[[boolean_flags[[key]]]]<-!key %in% c("--no-optimize","--no-kanji");next}
    if(key=="--stdin") {
      if(has_data)specqr_abort("Choose only one payload source")
      data<-.specqr_cli_read();has_data<-TRUE;next
    }
    allowed<-c(names(numeric_flags),names(text_flags),"--text","--input","--bytes-hex","--format","--output")
    if(!key %in% allowed)specqr_abort(paste0("Unknown argument: ",key))
    if(i>length(args))specqr_abort(paste0("Missing value for ",key))
    val<-args[i];i<-i+1L
    if(key %in% names(numeric_flags)) {
      if(!grepl("^[+]?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$",val))specqr_abort(paste0("Invalid number for ",key))
      v<-suppressWarnings(as.numeric(val));if(!is.finite(v))specqr_abort(paste0("Invalid number for ",key));opts[[numeric_flags[[key]]]]<-v
    } else if(key %in% names(text_flags))opts[[text_flags[[key]]]]<-val else if(key=="--format")format<-val else if(key=="--output")output<-val else {
      if(has_data)specqr_abort("Choose only one payload source")
      data<-if(key=="--text")val else if(key=="--input") .specqr_cli_read(val) else {
        if(nchar(val,type="bytes")>2000000L || nchar(val,type="bytes")%%2L || !grepl("^[0-9A-Fa-f]*$",val))specqr_abort("Invalid byte hex payload")
        if(!nzchar(val))raw() else as.raw(strtoi(substring(val,seq.int(1L,nchar(val),2L),seq.int(2L,nchar(val),2L)),16L))
      }
      has_data<-TRUE
    }
  }
  if(!has_data)specqr_abort("Choose --text, --input, --stdin, or --bytes-hex")
  if(!format %in% c("svg","png","json","matrix"))specqr_abort("Unsupported output format","INVALID_OUTPUT")
  o<-do.call(specqr_options,opts)
  if(planning){p<-plan(data,o);.specqr_cli_write(json_stringify(p),output);return(invisible(if(p$ok)0L else 2L))}
  q<-generate(data,o)
  content<-switch(format,svg=to_svg(q),png=to_png(q),matrix=paste0(apply(q$matrix,1L,function(r)paste0(as.integer(r),collapse="")),collapse="\n"),json=json_stringify(list(version=q$version,error_correction_level=q$error_correction_level,mask_pattern=q$mask_pattern,size=q$size,matrix=lapply(seq_len(q$size),function(i)paste0(as.integer(q$matrix[i,]),collapse="")),data_codewords=as.list(as.integer(q$data_codewords)),diagnostics=q$diagnostics)))
  .specqr_cli_write(content,output);invisible(0L)
}

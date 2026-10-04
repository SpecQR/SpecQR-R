args <- commandArgs(trailingOnly=FALSE)
filearg <- grep("^--file=",args,value=TRUE)
if(length(filearg)!=1L) stop("Bridge must run through Rscript")
root <- dirname(dirname(normalizePath(sub("^--file=","",filearg),mustWork=TRUE)))
for(f in sort(list.files(file.path(root,"R"),pattern="[.]R$",full.names=TRUE)))sys.source(f,envir=.GlobalEnv)
source(file.path(root,"scripts","protocol.R"),local=.GlobalEnv)
if("--runtime" %in% commandArgs(trailingOnly=TRUE)) {cat(json_stringify(list(R=as.character(getRversion()),os=Sys.info()[["sysname"]],arch=R.version$arch,wordSize=.Machine$sizeof.pointer*8L,rHome=R.home(),rPlatform=R.version$platform)),"\n",sep="");quit(status=0L)}
input <- file("stdin",open="r",encoding="UTF-8")
repeat {
 line<-readLines(input,n=1L,warn=FALSE)
 if(!length(line))break
 result<-tryCatch(run_request(json_parse(line)),error=function(e)list(error=class(e)[1L],isSpecQRError=inherits(e,"specqr_error"),code=if(inherits(e,"specqr_error"))e$code else "INTERNAL_ERROR",message=conditionMessage(e)))
 cat(json_stringify(result),"\n",sep="");flush(stdout())
}
close(input)

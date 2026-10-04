args <- commandArgs(trailingOnly=FALSE)
filearg <- grep("^--file=",args,value=TRUE)
if(length(filearg)!=1L)stop("Use Rscript")
root <- dirname(dirname(normalizePath(sub("^--file=","",filearg),mustWork=TRUE)))
env <- new.env(parent=baseenv())
for(f in sort(list.files(file.path(root,"R"),pattern="[.]R$",full.names=TRUE)))sys.source(f,env)
for(name in c("core.R","api.R","render-gs1.R","json-cli.R")) {
 cat("Running",name,"\n")
 sys.source(file.path(root,"inst","tests",name),envir=new.env(parent=env))
}

#!/usr/bin/env Rscript
args_all <- commandArgs(trailingOnly=FALSE)
this <- grep("^--file=",args_all,value=TRUE)
if(length(this)!=1L)stop("Run this script with Rscript")
this <- normalizePath(sub("^--file=","",this),mustWork=TRUE)
root <- dirname(dirname(this))
if(file.exists(file.path(root,"R","00-errors.R")) && file.exists(file.path(root,"DESCRIPTION"))) {
  env <- new.env(parent=baseenv())
  for(f in sort(list.files(file.path(root,"R"),pattern="[.]R$",full.names=TRUE)))sys.source(f,envir=env)
  cli <- env$specqr_cli
} else cli <- getExportedValue("specqr","specqr_cli")
status <- tryCatch(cli(commandArgs(trailingOnly=TRUE)),error=function(e){cat(conditionMessage(e),"\n",file=stderr(),sep="");if(inherits(e,"specqr_invalid_output"))3L else 2L})
quit(save="no",status=status,runLast=FALSE)

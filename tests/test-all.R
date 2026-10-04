# Execute shipped base-R tests inside an environment inheriting the installed
# namespace; internal test helpers are not exported as public API.
ns <- asNamespace("specqr")
for(name in c("core.R","api.R","render-gs1.R","json-cli.R")) {
  cat("Running",name,"\n")
  env <- new.env(parent=ns)
  sys.source(system.file("tests",name,package="specqr",mustWork=TRUE),envir=env)
}

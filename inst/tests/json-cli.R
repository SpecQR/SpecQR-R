if (!exists("json_parse",mode="function")) {
 root <- if(dir.exists("R")) "." else if(dir.exists("../R")) ".." else "specqr-r-work/SpecQR-R"
 for(f in sort(list.files(file.path(root,"R"),pattern="[.]R$",full.names=TRUE)))source(f)
}
.json_checks<-0L
.jcheck<-function(x){.json_checks<<-.json_checks+1L;if(!isTRUE(x))stop("JSON check failed: ",.json_checks)}
.jerror<-function(expr){e<-tryCatch({force(expr);NULL},error=identity);.jcheck(inherits(e,"specqr_error")&&e$code=="INVALID_INPUT")}
for(s in c('null','true','false','123','-0','-12.5','1.2e-5','{}','[]','{"a":null,"b":[1,true,"漢字🙂"]}')).jcheck(!inherits(tryCatch(json_parse(json_stringify(json_parse(s))),error=identity),"error"))
for(s in c('', 'NaN','Infinity','[1,]','{"a":1,"a":2}','01','1.','1e','+1','"\\ud800"','"\\udc00"','"\\ud800\\u0041"','"\\x00"','{"\\u0000":1}','[','{"a" 1}','true false','1e999','9007199254740993')).jerror(json_parse(s))
x<-json_parse('"A\\u0000B"');.jcheck(inherits(x,"specqr_json_nultext")&&identical(unclass(x),as.raw(c(65,0,66))))
for(cp in c(1:31,127,128,2047,2048,55295,57344,65535,65536,1114111)){s<-intToUtf8(cp);.jcheck(identical(json_parse(json_stringify(s)),s))}
for(b in list(as.raw(c(0xc0,0x80)),as.raw(c(0xed,0xa0,0x80)),as.raw(c(0xf4,0x90,0x80,0x80)))).jerror(json_parse(c(as.raw(34),b,as.raw(34))))
for(x in list(NA,NaN,Inf,-Inf,quote(x),new.env(),function()1)).jerror(json_stringify(x))
old<-options(OutDec=",");.jcheck(identical(json_stringify(list(v=0.5)),'{"v":0.5}'));options(old)
x<-0;for(i in 1:66)x<-list(x);.jerror(json_stringify(x))
.jerror(json_stringify(rep(list(strrep("a",1000000)),40)))
x<-"é";Encoding(x)<-"bytes";e<-tryCatch(GS1Element("10",x),error=identity);.jcheck(inherits(e,"specqr_invalid_gs1"))
x<-rawToChar(as.raw(233));Encoding(x)<-"latin1";.jcheck(identical(GS1Element("10",x)$value,"é"))
.jerror(specqr_cli(matrix("--help",1,1)))
.jerror(specqr_cli(structure("--help",class="specqr_invalid_cli_args")))
cat("JSON checks:",.json_checks,"\n")

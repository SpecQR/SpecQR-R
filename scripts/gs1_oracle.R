args <- commandArgs(trailingOnly=TRUE)
stopifnot(length(args)==2L)
root<-normalizePath(args[1L],mustWork=TRUE)
for(f in sort(list.files(file.path(root,'R'),pattern='[.]R$',full.names=TRUE)))sys.source(f,envir=.GlobalEnv)
ops<-c(dictionary='get_supported_gs1_ais',info='get_gs1_ai_info',checkDigit='calculate_gs1_check_digit',validateCheckDigit='validate_gs1_check_digit',gtinDigit='calculate_gtin_check_digit',gtinAppend='append_gtin_check_digit',gtinValidate='validate_gtin_check_digit',ssccDigit='calculate_sscc_check_digit',ssccAppend='append_sscc_check_digit',ssccValidate='validate_sscc_check_digit',human='parse_gs1_human_readable',raw='parse_gs1_element_string',create='create_gs1_element_string',validateElements='validate_gs1_elements',validateRaw='validate_gs1_element_string',linkCreate='create_gs1_digital_link',linkParse='parse_gs1_digital_link',linkValidate='validate_gs1_digital_link',linkNormalize='normalize_gs1_digital_link')
optmap<-c(baseUrl='base_url',primaryAi='primary_ai',pathAis='path_ais',unknownQuery='unknown_query',collectAllErrors='collect_all_errors',allowUnsupportedAi='allow_unsupported_ai',context='context',mode='mode',normalize='normalize')
keymap<-c(base_url='baseUrl',element_string='elementString',primary_ai='primaryAi',path_elements='pathElements',query_elements='queryElements',unknown_query='unknownQuery',has_separators='hasSeparators',element_index='elementIndex',value_kind='valueKind',check_digit_rule='checkDigitRule',digital_link_role='digitalLinkRole',digital_link_path_for_primary='digitalLinkPathForPrimary',is_variable='isVariable')
wire<-function(x){
 if(!is.list(x))return(x)
 if(!is.null(names(x))){
  if('digital_link_path_for_primary'%in%names(x)&&!is.null(x$digital_link_path_for_primary))x$digital_link_path_for_primary<-as.list(x$digital_link_path_for_primary)
  for(i in seq_along(x))if(names(x)[i]%in%names(keymap))names(x)[i]<-keymap[[names(x)[i]]]
 }
 lapply(x,wire)
}
corpus<-json_parse(paste(readLines(args[2L],warn=FALSE),collapse='\n'))
for(f in corpus$cases){
 result<-tryCatch({
  if(!f$op%in%names(ops))stop('Unknown operation')
  values<-if(f$op=='dictionary')list() else list(if('elements'%in%names(f))f$elements else f$input)
  for(key in names(f$options)){
   if(!key%in%names(optmap))stop('Unknown option')
   values[optmap[[key]]]<-list(f$options[[key]])
  }
  wire(do.call(get(ops[[f$op]],envir=.GlobalEnv),values))
 },error=function(e){if(!inherits(e,'specqr_error'))stop(e);list(throws=list(code=e$code,message=conditionMessage(e)))})
 cat(json_stringify(result),'\n',sep='')
}

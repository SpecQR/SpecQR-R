library(specqr)
input <- as.raw(0:255)
set <- generate_structured_append(input,version=2)
parts <- lapply(set$symbols, function(q) list(index=q$segments[[1]]$index,
  total=set$total, parity=set$parity,
  data=do.call(c,lapply(q$segments[-1],function(s)s$logical_bytes))))
merged <- merge_structured_append_parts(rev(parts))
stopifnot(identical(merged$data,input))
print(set)

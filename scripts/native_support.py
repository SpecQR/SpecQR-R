"""Strict receipts for the development-only verification harness."""
import json,math,hashlib,pathlib

def strict_json(data):
 def finite(t):
  v=float(t)
  if not math.isfinite(v): raise ValueError("Nonfinite JSON number")
  return v
 def pairs(items):
  out={}
  for k,v in items:
   if k in out:raise ValueError("Duplicate JSON key")
   out[k]=v
  return out
 return json.loads(data,object_pairs_hook=pairs,parse_float=finite,parse_constant=lambda x: (_ for _ in ()).throw(ValueError("Nonfinite JSON value")))

def binding(path):
 p=pathlib.Path(path)
 return {"file":p.name,"sha256":hashlib.sha256(p.read_bytes()).hexdigest(),"bytes":p.stat().st_size}

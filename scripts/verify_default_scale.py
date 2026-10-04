#!/usr/bin/env python3
"""Run the unchanged default-scale decoder verifier with one real R per request.

This is orchestration only: requests, actual PNG generation, every-pixel proof,
independent decoding, payload checks and symbol coverage remain those of the
source-bound verifier. Each child is strictly finalized before another starts.
"""
import argparse,gzip,hashlib,importlib,json,os,pathlib,subprocess,sys,time
if not __debug__:raise SystemExit('Default-scale verification rejects Python -O/PYTHONOPTIMIZE.')
p=argparse.ArgumentParser();p.add_argument('--source',type=pathlib.Path,required=True);p.add_argument('--rscript',type=pathlib.Path,required=True);p.add_argument('--python-deps',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--heap-mib',type=int,default=1024);p.add_argument('--smoke',action='store_true');a=p.parse_args()
a.source=a.source.resolve();a.output=a.output.resolve();a.output.parent.mkdir(parents=True,exist_ok=True)
if a.output.exists():raise SystemExit('Output receipt already exists; use a new attempt path.')
sys.path.insert(0,str(a.source/'scripts'));import verification_support as support
from prepare_ci import verify
from auxiliary_process import run_auxiliary,exact_number
before=verify(a.source);original=support.execute;finish=support.finish_clients
env=os.environ.copy();env.update(R_MAX_VSIZE=str(a.heap_mib*1024*1024),R_GC_MEM_GROW='0')
# R's documented cap is a vector-heap bound, not an OS RSS limit.
outcomes=[];start=time.monotonic();ledger=a.output.with_suffix('.processes.jsonl.gz')
metadata={'mode':'fresh-real-R-process-per-request','scale':8,'heapMiB':a.heap_mib,'R_MAX_VSIZE':env['R_MAX_VSIZE'],'R_GC_MEM_GROW':'0','memoryDocumentation':'https://stat.ethz.ch/R-manual/R-devel/library/base/html/Memory.html','sourceManifestSha256':before['manifestSha256'],'wrapperSha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),'verifierSha256':hashlib.sha256((a.source/'scripts/verify_decoders.py').read_bytes()).hexdigest()}
stream=gzip.open(ledger,'wt',encoding='utf-8')
def bounded(command,requests,env=None,timeout=900):
 results=[]
 for request in requests:
  partial={}
  try:
   result=original(command,[request],env=globals()['env'],timeout=timeout)
   finish(partial)
   record={'index':len(outcomes),'requestSha256':hashlib.sha256(json.dumps(request,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()).hexdigest(),'request':request,'process':partial['nativeProcesses'][0]}
   assert len(result)==1 and len(partial['nativeProcesses'])==1
   outcomes.append(record['process']);stream.write(json.dumps(record,separators=(',',':'))+'\n');stream.flush();results.extend(result)
  except BaseException:
   finish(partial,raise_errors=False)
   for outcome in partial.get('nativeProcesses',[]):
    if outcome not in outcomes:outcomes.append(outcome)
   raise
 return results
support.execute=bounded
report={"status":"running","nativeProcesses":outcomes,"boundedOrchestration":metadata}
heap_processes=[]
try:
 limit=run_auxiliary([str(a.rscript),'--vanilla','-e','cat(mem.maxVSize())'],report,'r-vector-heap',env=env,validator=lambda data:exact_number(data,a.heap_mib))
 heap_processes=list(report.get('auxiliaryProcesses',[]))
 if a.smoke:
  sys.path.insert(0,str(a.python_deps.resolve()));import zxingcpp
  from decoder_support import verify_png
  r=bounded(support.rscript_command(a.rscript),[{'bytes':list(range(200)),'options':{'version':40,'errorCorrectionLevel':'H','maskPattern':7},'pngScale':8}])[0]
  assert 'error' not in r,r
  png,luma,dim=verify_png(r['png'],r['matrix'],8);q=zxingcpp.read_barcode(memoryview(luma).cast('B',shape=(dim,dim)),text_mode=zxingcpp.TextMode.Plain)
  assert q is not None and q.valid and q.bytes==bytes(range(200))
  report={'status':'passed','scale':8,'maximumVersionSmoke':True,'pixels':dim*dim,'pngBytes':len(png)}
 else:
  module=importlib.import_module('verify_decoders')
  sys.argv=[str(a.source/'scripts/verify_decoders.py'),'--rscript',str(a.rscript),'--decoder','cpp','--scale','8','--python-deps',str(a.python_deps),'--output',str(a.output)]
  module.main();report=json.loads(a.output.read_text())
  assert report['status']=='passed' and report['scale']==8 and report['counts']['pngDecodes']==764
  assert len(outcomes)==725,len(outcomes)
 report['auxiliaryProcesses']=heap_processes+report.get('auxiliaryProcesses',[])
 assert verify(a.source)==before,'Source changed'
 assert all(x['status']=='passed' and x['exitCode']==0 and x['stderrBytes']==0 and x['trailingStdoutBytes']==0 for x in outcomes)
 report.update(nativeProcesses=outcomes,boundedOrchestration=metadata,sourceStable=True,elapsedSeconds=round(time.monotonic()-start,3))
except BaseException as error:
 try:
  saved=json.loads(a.output.read_text()) if a.output.exists() else {}
  if isinstance(saved,dict):
   auxiliary=heap_processes or report.get('auxiliaryProcesses',[]);report.update(saved);report['auxiliaryProcesses']=auxiliary+saved.get('auxiliaryProcesses',[])
 except (OSError,ValueError):pass
 # Set failure before any secondary verification; never retain an inner pass.
 report.update(status='failed',error=repr(error),nativeProcesses=outcomes,boundedOrchestration=metadata,sourceStable=False,elapsedSeconds=round(time.monotonic()-start,3))
 try:report['sourceStable']=verify(a.source)==before
 except BaseException as source_error:report['sourceVerificationError']=repr(source_error)
 raise
finally:
 finish(raise_errors=False);stream.close()
 report['processLedger']={'file':ledger.name,'bytes':ledger.stat().st_size,'sha256':hashlib.sha256(ledger.read_bytes()).hexdigest()}
 a.output.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'status':report['status'],'scale':8,'processes':len(outcomes),'elapsedSeconds':report['elapsedSeconds']}))

#!/usr/bin/env python3
"""Actual Linux R version, package, consumer, CLI and full-reference validation."""
from __future__ import annotations
import argparse,datetime,hashlib,json,os,pathlib,platform,re,subprocess,sys,time
from prepare_ci import verify,extract,sha
from verify_cli import check as check_cli
from auxiliary_process import run_auxiliary,json_records
ROOT=pathlib.Path(__file__).resolve().parents[1]
def require(ok,message):
 if not ok:raise RuntimeError(message)
def main():
 p=argparse.ArgumentParser();p.add_argument('--rscript',required=True);p.add_argument('--expect-version',required=True);p.add_argument('--expect-platform',required=True);p.add_argument('--expect-arch',required=True);p.add_argument('--source-archive',type=pathlib.Path,required=True);p.add_argument('--archive-sha256',required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
 out=a.output.resolve();require(not out.exists(),'Output directory already exists; use a new attempt directory');out.mkdir(parents=True)
 start=time.monotonic();report={'status':'running','startedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'checks':{},'host':{'system':platform.system(),'machine':platform.machine(),'release':platform.release()},'archiveSha256':sha(a.source_archive)}
 rscript=pathlib.Path(a.rscript).resolve();r=rscript.with_name('R');source=None
 def run(name,args,cwd=None,env=None,timeout=7200):
  log=out/(name+'.log');beg=time.monotonic()
  with log.open('wb') as f:proc=subprocess.run([str(x) for x in args],cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
  result={'exitCode':proc.returncode,'elapsedSeconds':round(time.monotonic()-beg,3),'log':log.name,'sha256':sha(log)};report['checks'][name]=result
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');require(proc.returncode==0,name+' failed; see '+str(log));return log
 try:
  require(platform.system().lower()==a.expect_platform=='linux','This receipt requires actual Linux')
  arch={'amd64':'x86_64','x64':'x86_64','aarch64':'arm64'}.get(platform.machine().lower(),platform.machine().lower());require(arch==a.expect_arch,'Architecture mismatch')
  require(report['archiveSha256']==a.archive_sha256,'Archive SHA256 mismatch');source=extract(a.source_archive,out/'source');report['source']=verify(source)
  runtime=run_auxiliary([str(rscript),'--vanilla',str(source/'scripts/bridge.R'),'--runtime'],report,'r-runtime',validator=lambda data:json_records(data,1)[0]);require(runtime['R']==a.expect_version and runtime['os']=='Linux' and runtime['arch']=='x86_64' and runtime['wordSize']==64,'Actual R runtime mismatch');report['runtime']=runtime
  native_executable=pathlib.Path(runtime['rHome'])/'bin/exec/R';require(native_executable.is_file(),'Missing native R executable');report['rscriptLauncherSha256']=sha(rscript);report['nativeRExecutableSha256']=sha(native_executable)
  library=out/'library';library.mkdir();build=out/'build';build.mkdir();env=os.environ.copy();env.update(R_LIBS_USER=str(library),R_LIBS_SITE='',R_PROFILE_USER=str(out/'no-profile'),R_ENVIRON_USER=str(out/'no-environ'),_R_CHECK_FORCE_SUGGESTS_='false',_R_CHECK_CRAN_INCOMING_='false',_R_CHECK_CRAN_INCOMING_REMOTE_='false',R_GSCMD='false',LANG='C.UTF-8')
  run('build',[r,'CMD','build','--no-build-vignettes',source],cwd=build,env=env)
  tar=build/'specqr_0.1.0.tar.gz';require(tar.exists(),'Missing source package');report['packageSha256']=sha(tar)
  run('install',[r,'CMD','INSTALL','--library='+str(library),tar],cwd=build,env=env)
  check=run('package-check',[r,'CMD','check','--no-manual','--no-build-vignettes',tar],cwd=build,env=env)
  checklog=build/'specqr.Rcheck/00check.log';text=checklog.read_text();require('Status: OK' in text and not any(x in text for x in (' WARNING',' ERROR',' NOTE')),'R CMD check was not clean')
  (out/'R-CMD-check.log').write_text(text)
  unitlog=build/'specqr.Rcheck/tests/test-all.Rout';unittext=unitlog.read_text();(out/'unit-tests.Rout').write_text(unittext)
  unit_patterns={'core':r'Core tests passed: ([0-9]+) checks','api':r'API, optimizer, and Structured Append checks: ([0-9]+) passed','renderGs1':r'Render/GS1: ([0-9]+) checks passed','json':r'JSON checks: ([0-9]+)'}
  units={}
  for key,pattern in unit_patterns.items():
   match=re.search(pattern,unittext);require(match is not None,'Missing unit group '+key);units[key]=int(match.group(1))
  require(units=={'core':93162,'api':412,'renderGs1':448,'json':87},'Unit counts differ from the pinned package suite')
  report['unitCounts']=units;report['unitAssertions']=sum(units.values())
  consumer=out/'consumer.R';consumer.write_text('library(specqr)\nstopifnot(identical(getNamespaceImports("specqr"),list(base=TRUE)))\nq<-generate(as.raw(c(0,29,255)))\nstopifnot(is.logical(q$matrix),is.raw(to_png(q,scale=1)))\nfor(f in list.files(system.file("examples",package="specqr"),full.names=TRUE))source(f)\ncat("Installed consumer passed\\n")\n')
  run('installed-consumer',[rscript,'--vanilla',consumer],cwd=out,env=env)
  direct=out/'direct-consumer.R';direct.write_text('e<-new.env(parent=baseenv())\nfor(f in sort(list.files('+json.dumps(str(source/'R'))+',pattern="[.]R$",full.names=TRUE)))sys.source(f,e)\nq<-e$generate("UTF-8: \\u6f22\\u5b57",eci=TRUE)\nstopifnot(is.raw(e$to_png(q,scale=1)))\ncat("Base-environment source consumer passed\\n")\n')
  run('source-consumer',[rscript,'--vanilla',direct],cwd=out,env=env)
  installed_cli=library/'specqr/exec/specqr.R';cli=check_cli(rscript,out/'cli.json',cli=installed_cli,env=env);report['cliChecks']=cli['checks']
  run('reference',[sys.executable,source/'scripts/verify_reference.py','--rscript',rscript,'--suite','both','--output',out/'reference.json','--timeout','7200'],cwd=source,env=env,timeout=7500)
  reference=json.loads((out/'reference.json').read_text());require(reference['status']=='passed' and reference['responseCount']==10186 and reference['sourceStable'],'Incomplete reference');report['referenceCases']=reference['responseCount']
  require(verify(source)==report['source'],'Source changed during native validation');report['status']='passed'
 except BaseException as error:report['status']='failed';report['error']=repr(error);raise
 finally:
  report['elapsedSeconds']=round(time.monotonic()-start,3);(out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'status':report['status'],'runtime':runtime,'referenceCases':report['referenceCases'],'cliChecks':report['cliChecks']}))
if __name__=='__main__':main()

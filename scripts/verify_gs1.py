#!/usr/bin/env python3
"""Execute every original GS1 request against source-bound independent targets."""
import argparse,collections,hashlib,json,pathlib,subprocess,tempfile,time
from gs1_contract import load_main,load_shared,load_extra,compare_contract,contract,accepted
from native_support import strict_json,binding
from prepare_ci import verify,inventory
ROOT=pathlib.Path(__file__).resolve().parents[1]
def require(v,message):
 if not v:raise RuntimeError(message)
def run(rscript,requests,expected,output):
 out=pathlib.Path(output);out.parent.mkdir(parents=True,exist_ok=True)
 before=inventory(ROOT);manifest=verify(ROOT);start=time.monotonic()
 report={'status':'running','requestCount':len(requests),'sourceSha256':before,'sourceManifestSha256':manifest['manifestSha256'],'harness':binding(ROOT/'scripts/gs1_oracle.R'),'binary':binding(rscript)}
 stdout=out.with_suffix('.stdout.jsonl');stderr=out.with_suffix('.stderr');inputfile=out.with_suffix('.inputs.json')
 inputfile.write_text(json.dumps({'cases':requests},ensure_ascii=True,separators=(',',':'))+'\n')
 cmd=[str(pathlib.Path(rscript).resolve()),'--vanilla',str(ROOT/'scripts/gs1_oracle.R'),str(ROOT),str(inputfile.resolve())];report['argv']=cmd
 try:
  p=subprocess.run(cmd,capture_output=True,timeout=1800);stdout.write_bytes(p.stdout);stderr.write_bytes(p.stderr)
  report.update(exitCode=p.returncode,stderrBytes=len(p.stderr),stdout=binding(stdout),stderr=binding(stderr),input=binding(inputfile))
  require(p.returncode==0,'R GS1 process failed');require(not p.stderr,'Unexpected GS1 stderr')
  rows=[strict_json(line)for line in p.stdout.splitlines()];report['responseCount']=len(rows)
  require(len(rows)==len(requests),'Missing or extra GS1 responses')
  for i,(want,got)in enumerate(zip(expected,rows)):compare_contract(want,got,'case '+str(i))
  require(before==inventory(ROOT),'Source changed during GS1 execution');require(verify(ROOT)==manifest,'Source manifest changed');report['status']='passed'
  return rows,report
 except BaseException as e:report.update(status='failed',error=repr(e));raise
 finally:
  report.update(sourceStable=before==inventory(ROOT),elapsedSeconds=time.monotonic()-start);out.write_text(json.dumps(report,indent=2)+'\n')
def main():
 p=argparse.ArgumentParser();p.add_argument('--rscript',required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
 main=load_main(ROOT);shared=load_shared(ROOT)
 rows=main['current']['cases'];expected=[main['residual'].get(r['caseId'],r)['expected']for r in rows]
 actual,receipt=run(a.rscript,[r['request']for r in rows],expected,a.output/'corpus.json')
 for i,r in main['restored'].items():compare_contract(r['expected'],actual[i],'restoration '+str(i));require(accepted(actual[i]),'Restoration rejected')
 residual=[i for i,r in enumerate(rows)if contract(r['expected'])!=contract(actual[i])];require(set(residual)==set(main['residual']),'Unexpected residual scope')
 rows=shared['current']['cases'];want=[shared['residual'].get(r['id'],r)['expected']for r in rows]
 shared_actual,shared_receipt=run(a.rscript,[r['request']for r in rows],want,a.output/'shared49.json')
 authority_path=ROOT/'inst/tests/gs1-authority-expected.json';require(binding(authority_path)['sha256']=='5b137c40a9553e49d6326f86af7c43c81eb3401dca6d85c4f0f1528aaa56ebfa','Authority fixture changed')
 authority=strict_json(authority_path.read_bytes());require(authority['provenance']['upstreamCommit']=='16efc6c0a8e397c9df3d051d20fce6c1eebdfad7','Authority source changed');require(authority['provenance']['generatorSha256']==binding(ROOT/'verification/gs1/generate_authority_expected.mjs')['sha256'],'Authority generator changed')
 controls=authority['cases'];require(len(controls)==113,'Authority control count changed')
 run(a.rscript,[{'op':'linkNormalize','input':r['input']}for r in controls],[r['expected']for r in controls],a.output/'authority113.json')
 extra=load_extra(ROOT);run(a.rscript,[r['request']for r in extra['cases']],[r['expected']for r in extra['cases']],a.output/'extra139.json')
 summary={'status':'passed','allCases':1411,'restoredPositiveCases':80,'currentTsMatches':1243,'residualCategories':main['categoryCounts'],'diagnosticMigrations':5,'sharedOperations':49,'authorityControls':113,'extraPositiveCases':139,'sharedAccepted':sum(map(accepted,shared_actual)),'fixtures':main['artifacts']|shared['artifacts'],'sourceStable':receipt['sourceStable']and shared_receipt['sourceStable']}
 (a.output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary))
if __name__=='__main__':main()

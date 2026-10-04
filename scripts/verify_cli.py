#!/usr/bin/env python3
"""Native R CLI exact-byte and failure-path verification; standard Python only."""
import argparse,hashlib,json,os,pathlib,subprocess,tempfile,struct,zlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
def require(ok,message):
 if not ok:raise RuntimeError(message)
def check(rscript,output,cli=None,env=None):
 output=pathlib.Path(output);output.parent.mkdir(parents=True,exist_ok=True)
 cmd=[str(pathlib.Path(rscript).resolve()),'--vanilla',str(cli or ROOT/'exec/specqr.R')]
 results=[];report={'status':'running','argv':cmd,'checks':0,'results':results}
 def run(name,args=(),data=None,want=0):
  p=subprocess.run(cmd+list(args),input=data,capture_output=True,env=env,timeout=90)
  result={'name':name,'exitCode':p.returncode,'stdoutBytes':len(p.stdout),'stdoutSha256':hashlib.sha256(p.stdout).hexdigest(),'stderr':p.stderr.decode(errors='replace')}
  results.append(result);require(p.returncode==want,(name,result));require(not p.stderr if want==0 else bool(p.stderr) or '--plan' in args,(name,result));return p.stdout
 try:
  with tempfile.TemporaryDirectory(prefix='specqr-cli-') as tmp:
   work=pathlib.Path(tmp);payload=b' A\x00B\x1d\x1d%\x7f\x80\xff\r\n '
   file=work/'空 白 payload.bin';file.write_bytes(payload)
   a=json.loads(run('binary-file',['--input',str(file),'--format','json']))
   b=json.loads(run('binary-stdin',['--stdin','--format','json'],payload))
   c=json.loads(run('binary-hex',['--bytes-hex',payload.hex(),'--format','json']))
   require(a==b==c,'File/stdin/hex byte payload changed')
   # Recover raw byte segment from the data bitstream (small v1, no controls).
   bits=''.join(f'{v:08b}' for v in a['data_codewords']);require(bits[:4]=='0100','Expected byte segment')
   count=int(bits[4:12],2);actual=bytes(int(bits[i:i+8],2) for i in range(12,12+count*8,8));require(actual==payload,'Control/whitespace bytes lost')
   empty=json.loads(run('empty-stdin',['--stdin','--format','json'],b''));require(empty['version']==1,'Empty stdin')
   text='e\u0301漢字🙂\t\n%';run('unicode-text',['--text',text,'--eci','26','--format','json'])
   path=work/'画 像.png';out=run('png-path',['--text','HELLO','--format','png','--output',str(path)]);require(not out,'File output leaked stdout')
   png=path.read_bytes();require(png.startswith(b'\x89PNG\r\n\x1a\n'),'Missing PNG signature')
   direct=run('png-stdout',['--text','HELLO','--format','png']);require(direct==png,'Binary stdout differs')
   s=work/'図.svg';run('svg-path',['--text','HELLO','--format','svg','--output',str(s)]);require(s.read_text().startswith('<svg'),'SVG write')
   matrix=run('matrix',['--text','HELLO','--format','matrix']);rows=matrix.decode().splitlines();require(len(rows)==21 and all(len(x)==21 and set(x)<=set('01') for x in rows),'Matrix')
   plan=json.loads(run('plan',['--text','12345','--plan']));require(plan['ok'],'Plan failed')
   overflow=json.loads(run('plan-overflow',['--text','a'*1000,'--version','1','--plan'],want=2));require(not overflow['ok'],'Overflow plan')
   run('help',['--help']);run('version',['--cli-version'])
   cases=[('missing-payload',[]),('missing-value',['--text']),('duplicate-text',['--text','A','--text','B']),('two-sources',['--text','A','--stdin']),('unknown',['--text','A','--bogus']),('invalid-ecc',['--text','A','--ecc','constructor']),('invalid-version',['--text','A','--version','0']),('fractional-scale',['--text','A','--scale','1.5']),('invalid-mask',['--text','A','--mask','8']),('invalid-hex',['--bytes-hex','0x']),('odd-hex',['--bytes-hex','0']),('missing-file',['--input',str(work/'absent')]),('conflicting-controls',['--text','A','--eci','26','--fnc1']),('too-long',['--text','a'*5000]),('bad-format',['--text','A','--format','bmp'])]
   for name,args in cases:run(name,args,want=3 if name=='bad-format' else 2)
   run('output-failure',['--text','A','--output',str(work/'absent'/'no.svg')],want=3)
   run('oversized-stdin',['--stdin'],b'A'*1000001,want=2)
  report.update(status='passed',checks=len(results));return report
 except BaseException as error:report.update(status='failed',error=repr(error));raise
 finally:output.write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--rscript',required=True);p.add_argument('--output',required=True);a=p.parse_args();r=check(a.rscript,a.output);print(json.dumps({'status':r['status'],'checks':r['checks']}))

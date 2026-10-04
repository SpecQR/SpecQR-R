#!/usr/bin/env python3
"""Exact source manifests, bounded deterministic staging, and report collection."""
from __future__ import annotations
import argparse,hashlib,json,pathlib,shutil,stat,zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
IGNORE={'.git','__pycache__','validation-output','build'}
def sha(path):return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
def inventory(root):
 root=pathlib.Path(root);out={}
 for p in sorted(root.rglob('*')):
  rel=p.relative_to(root)
  if any(x in IGNORE or x.endswith('.Rcheck') for x in rel.parts) or p.suffix=='.pyc' or rel.as_posix()=='SOURCE-SHA256.json':continue
  if p.is_symlink():raise ValueError('Source symlink rejected: '+str(rel))
  if p.is_file():out[rel.as_posix()]=sha(p)
 return out
def verify(root):
 root=pathlib.Path(root);m=json.loads((root/'SOURCE-SHA256.json').read_text())
 if m.get('schemaVersion')!=1 or m.get('files')!=inventory(root):raise ValueError('Source manifest mismatch')
 return {'manifestSha256':sha(root/'SOURCE-SHA256.json'),'files':m['files'],'fileCount':len(m['files'])}
def archive(root,path):
 root=pathlib.Path(root);manifest=verify(root)
 with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for name in sorted([*manifest['files'],'SOURCE-SHA256.json']):
   data=(root/name).read_bytes();zi=zipfile.ZipInfo('SpecQR-R/'+name,date_time=(2026,1,1,0,0,0));zi.compress_type=zipfile.ZIP_DEFLATED;zi.external_attr=(stat.S_IFREG|0o644)<<16;z.writestr(zi,data)
 return sha(path)
def extract(path,destination):
 destination=pathlib.Path(destination);total=0;seen=set()
 with zipfile.ZipFile(path) as z:
  entries=z.infolist()
  if len(entries)>1000:raise ValueError('Too many archive entries')
  for i in entries:
   name=i.filename;parts=name.split('/')
   if name in seen or '\\' in name or ':' in name or any(x in ('','.','..') for x in parts) or parts[0]!='SpecQR-R' or len(parts)<2:raise ValueError('Unsafe archive path')
   seen.add(name);total+=i.file_size
   mode=i.external_attr>>16
   if stat.S_ISLNK(mode) or (mode and not stat.S_ISREG(mode)) or i.is_dir():raise ValueError('Nonregular archive entry')
   if total>10000000:raise ValueError('Archive source exceeds 10MB budget')
  for i in entries:
   p=destination/i.filename;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(z.read(i))
 return destination/'SpecQR-R'
def stage(output):
 output=pathlib.Path(output).resolve()
 if output.exists():raise ValueError('Stage destination already exists')
 output.mkdir(parents=True);m=verify(ROOT);a=output/'SpecQR-R-source.zip';digest=archive(ROOT,a);source=extract(a,output/'stage');verify(source)
 report={'status':'passed',**m,'archiveSha256':digest,'archiveBytes':a.stat().st_size,'source':str(source)}
 (output/'stage-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
def collect(native,output):
 native=pathlib.Path(native);output=pathlib.Path(output);output.mkdir(parents=True,exist_ok=True)
 if not native.exists():(output/'MISSING.txt').write_text('Native verification directory is missing; no pass may be inferred.\n');return
 # Preserve receipts and complete compressed streams, not the redundant installed libraries/build tree.
 for p in native.rglob('*'):
  rel=p.relative_to(native)
  if not p.is_file() or any(x in ('source','build','library','stage','consumer') for x in rel.parts):continue
  if p.suffix in ('.json','.log','.stderr','.gz','.txt','.Rout','.Rout.fail') or p.name in ('00check.log','00install.out'):
   d=output/rel;d.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,d)
if __name__=='__main__':
 p=argparse.ArgumentParser();s=p.add_subparsers(dest='command',required=True)
 q=s.add_parser('stage');q.add_argument('--output',required=True)
 q=s.add_parser('collect');q.add_argument('--native',required=True);q.add_argument('--output',required=True)
 q=s.add_parser('manifest');q.add_argument('--root',default=ROOT)
 q=s.add_parser('verify');q.add_argument('--root',default=ROOT)
 a=p.parse_args()
 if a.command=='stage':stage(a.output)
 elif a.command=='collect':collect(a.native,a.output)
 elif a.command=='verify':print(json.dumps({'status':'passed',**verify(a.root)}))
 else:
  root=pathlib.Path(a.root);(root/'SOURCE-SHA256.json').write_text(json.dumps({'schemaVersion':1,'files':inventory(root)},indent=2)+'\n')

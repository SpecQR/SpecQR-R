#!/usr/bin/env python3
"""Negative controls for strict GS1 process, type and pinned-ledger checks."""
import json,pathlib,shutil,tempfile,sys
import verify_gs1 as v
from prepare_ci import inventory
from gs1_contract import load_main
checks=0
with tempfile.TemporaryDirectory(prefix='specqr-gs1-controls-')as td:
 root=pathlib.Path(td)/'source';shutil.copytree(v.ROOT,root,ignore=shutil.ignore_patterns('__pycache__'))
 v.ROOT=root
 (root/'SOURCE-SHA256.json').write_text(json.dumps({'schemaVersion':1,'files':inventory(root)}))
 cases=[('valid','{"ok":true}\n','',0,True),('missing','','',0,False),('extra','{"ok":true}\n{"ok":true}\n','',0,False),('stderr','{"ok":true}\n','noise',0,False),('nonzero','{"ok":true}\n','',3,False),('bool-as-int','{"ok":1}\n','',0,False),('duplicate-key','{"ok":true,"ok":true}\n','',0,False),('extra-field','{"ok":true,"unexpected":1}\n','',0,False),('malformed','not json\n','',0,False)]
 for name,out,err,code,want in cases:
  binary=pathlib.Path(td)/('mock-'+name);binary.write_text('#!'+sys.executable+'\nimport sys\nsys.stdout.write('+repr(out)+')\nsys.stderr.write('+repr(err)+')\nsys.exit('+str(code)+')\n');binary.chmod(0o700)
  passed=False
  try:v.run(binary,[{'op':'control'}],[{'ok':True}],pathlib.Path(td)/(name+'.json'));passed=True
  except (RuntimeError,ValueError):pass
  if passed!=want:raise RuntimeError('Fail-closed control failed: '+name)
  checks+=1
 original=root/'verification/fixtures/approved-restorations80.json';data=original.read_bytes();original.write_bytes(data+b' ')
 try:load_main(root)
 except RuntimeError:checks+=1
 else:raise RuntimeError('Corrupted pinned positive ledger accepted')
 original.write_bytes(data)
print(json.dumps({'status':'passed','failClosedChecks':checks}))

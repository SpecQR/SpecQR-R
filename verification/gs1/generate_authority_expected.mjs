// Rebuild synthetic authority expectations from a verified archived TypeScript src directory.
// Usage: node tests/generate_gs1_authority_expected.mjs /path/to/current-ts/src
import {readFileSync,readdirSync,statSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,relative,join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const src=resolve(process.argv[2] ?? '');
const oracle=await import(pathToFileURL(join(src,'gs1/digital-link.js')).href);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
function walk(dir){return readdirSync(dir).flatMap(name=>{const path=join(dir,name);return statSync(path).isDirectory()?walk(path):[path]})}
const sourceFiles=walk(src).sort().map(path=>({path:relative(src,path),sha256:sha(readFileSync(path))}));
const sourceTreeSha256=sha(JSON.stringify(sourceFiles));
const requests=[
  {
    "caseId": "authority-000",
    "input": "https://example.com/01/04912345678904"
  },
  {
    "caseId": "authority-001",
    "input": "https://EXAMPLE.com:00443/01/04912345678904"
  },
  {
    "caseId": "authority-002",
    "input": "https://example.com:/01/04912345678904"
  },
  {
    "caseId": "authority-003",
    "input": "https://example.com:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000443/01/04912345678904"
  },
  {
    "caseId": "authority-004",
    "input": "https://%65xample.com/01/04912345678904"
  },
  {
    "caseId": "authority-005",
    "input": "https://%45XAMPLE.%63om/01/04912345678904"
  },
  {
    "caseId": "authority-006",
    "input": "https://exa_mple.com/01/04912345678904"
  },
  {
    "caseId": "authority-007",
    "input": "https://-bad-.example/01/04912345678904"
  },
  {
    "caseId": "authority-008",
    "input": "https://example..com/01/04912345678904"
  },
  {
    "caseId": "authority-009",
    "input": "https://.example/01/04912345678904"
  },
  {
    "caseId": "authority-010",
    "input": "https://0x+1/01/04912345678904"
  },
  {
    "caseId": "authority-011",
    "input": "https://0+7/01/04912345678904"
  },
  {
    "caseId": "authority-012",
    "input": "https://0x/01/04912345678904"
  },
  {
    "caseId": "authority-013",
    "input": "https://0X/01/04912345678904"
  },
  {
    "caseId": "authority-014",
    "input": "https://0x./01/04912345678904"
  },
  {
    "caseId": "authority-015",
    "input": "https://1.0x/01/04912345678904"
  },
  {
    "caseId": "authority-016",
    "input": "https://1.2.3.0x/01/04912345678904"
  },
  {
    "caseId": "authority-017",
    "input": "https://127.1/01/04912345678904"
  },
  {
    "caseId": "authority-018",
    "input": "https://0177.0.0.1/01/04912345678904"
  },
  {
    "caseId": "authority-019",
    "input": "https://127.0.0.01/01/04912345678904"
  },
  {
    "caseId": "authority-020",
    "input": "https://2130706433/01/04912345678904"
  },
  {
    "caseId": "authority-021",
    "input": "https://0x7f000001/01/04912345678904"
  },
  {
    "caseId": "authority-022",
    "input": "https://0x7f.1/01/04912345678904"
  },
  {
    "caseId": "authority-023",
    "input": "https://127.0.0.1./01/04912345678904"
  },
  {
    "caseId": "authority-024",
    "input": "https://4294967295/01/04912345678904"
  },
  {
    "caseId": "authority-025",
    "input": "https://255.16777215/01/04912345678904"
  },
  {
    "caseId": "authority-026",
    "input": "https://255.255.65535/01/04912345678904"
  },
  {
    "caseId": "authority-027",
    "input": "https://255.255.255.255/01/04912345678904"
  },
  {
    "caseId": "authority-028",
    "input": "https://0/01/04912345678904"
  },
  {
    "caseId": "authority-029",
    "input": "https://00/01/04912345678904"
  },
  {
    "caseId": "authority-030",
    "input": "https://0.0.0.0/01/04912345678904"
  },
  {
    "caseId": "authority-031",
    "input": "https://[0:0:0:0:0:0:0:0]/01/04912345678904"
  },
  {
    "caseId": "authority-032",
    "input": "https://[0:0:0:0:0:0:0:1]/01/04912345678904"
  },
  {
    "caseId": "authority-033",
    "input": "https://[2001:0db8:0:0:1:0:0:1]/01/04912345678904"
  },
  {
    "caseId": "authority-034",
    "input": "https://[::ffff:192.168.1.1]/01/04912345678904"
  },
  {
    "caseId": "authority-035",
    "input": "https://[1:0:0:2:0:0:3:4]/01/04912345678904"
  },
  {
    "caseId": "authority-036",
    "input": "https://[1:0:2:3:4:5:6:7]/01/04912345678904"
  },
  {
    "caseId": "authority-037",
    "input": "https://[1:2:3:4:5:6:0:0]/01/04912345678904"
  },
  {
    "caseId": "authority-038",
    "input": "https://[::]/01/04912345678904"
  },
  {
    "caseId": "authority-039",
    "input": "https://[1::]/01/04912345678904"
  },
  {
    "caseId": "authority-040",
    "input": "https://[1:2:3:4:5:6:7:8]/01/04912345678904"
  },
  {
    "caseId": "authority-041",
    "input": "https://user:pass@EXAMPLE.com:443/01/04912345678904"
  },
  {
    "caseId": "authority-042",
    "input": "https://user@@example.com/01/04912345678904"
  },
  {
    "caseId": "authority-043",
    "input": "https://:pass@example.com/01/04912345678904"
  },
  {
    "caseId": "authority-044",
    "input": "https://user:@example.com/01/04912345678904"
  },
  {
    "caseId": "authority-045",
    "input": "https://@example.com/01/04912345678904"
  },
  {
    "caseId": "authority-046",
    "input": "https://:@example.com/01/04912345678904"
  },
  {
    "caseId": "authority-047",
    "input": "https://u:p:a@example.com/01/04912345678904"
  },
  {
    "caseId": "authority-048",
    "input": "https://u%41:p%3a@example.com/01/04912345678904"
  },
  {
    "caseId": "authority-049",
    "input": "https://u!$&'()*+,;=:@example.com/01/04912345678904"
  },
  {
    "caseId": "authority-050",
    "input": "https://user%20x:pa%23ss@example.com/01/04912345678904"
  },
  {
    "caseId": "authority-051",
    "input": "https://user:p@ss@example.com/01/04912345678904"
  },
  {
    "caseId": "authority-052",
    "input": "https://u \u00e9:p\ud83d\ude00@example.com/01/04912345678904"
  },
  {
    "caseId": "authority-053",
    "input": "https://4294967296/01/04912345678904"
  },
  {
    "caseId": "authority-054",
    "input": "https://999999999999999999999999999999/01/04912345678904"
  },
  {
    "caseId": "authority-055",
    "input": "https://0x100000000/01/04912345678904"
  },
  {
    "caseId": "authority-056",
    "input": "https://0xfffffffffffffffffffff/01/04912345678904"
  },
  {
    "caseId": "authority-057",
    "input": "https://040000000000/01/04912345678904"
  },
  {
    "caseId": "authority-058",
    "input": "https://256.0.0.1/01/04912345678904"
  },
  {
    "caseId": "authority-059",
    "input": "https://1.16777216/01/04912345678904"
  },
  {
    "caseId": "authority-060",
    "input": "https://1.2.65536/01/04912345678904"
  },
  {
    "caseId": "authority-061",
    "input": "https://1.2.3.256/01/04912345678904"
  },
  {
    "caseId": "authority-062",
    "input": "https://1.2.3.08/01/04912345678904"
  },
  {
    "caseId": "authority-063",
    "input": "https://1.2.3.4.5/01/04912345678904"
  },
  {
    "caseId": "authority-064",
    "input": "https://.1/01/04912345678904"
  },
  {
    "caseId": "authority-065",
    "input": "https://example.123/01/04912345678904"
  },
  {
    "caseId": "authority-066",
    "input": "https://0xg.0x/01/04912345678904"
  },
  {
    "caseId": "authority-067",
    "input": "https://%2fexample.com/01/04912345678904"
  },
  {
    "caseId": "authority-068",
    "input": "https://example%5c.com/01/04912345678904"
  },
  {
    "caseId": "authority-069",
    "input": "https://example%3a443/01/04912345678904"
  },
  {
    "caseId": "authority-070",
    "input": "https://example%40.com/01/04912345678904"
  },
  {
    "caseId": "authority-071",
    "input": "https://example%23.com/01/04912345678904"
  },
  {
    "caseId": "authority-072",
    "input": "https://example%3f.com/01/04912345678904"
  },
  {
    "caseId": "authority-073",
    "input": "https://example%5b.com/01/04912345678904"
  },
  {
    "caseId": "authority-074",
    "input": "https://example%5d.com/01/04912345678904"
  },
  {
    "caseId": "authority-075",
    "input": "https://example%5e.com/01/04912345678904"
  },
  {
    "caseId": "authority-076",
    "input": "https://example%7c.com/01/04912345678904"
  },
  {
    "caseId": "authority-077",
    "input": "https://example%20.com/01/04912345678904"
  },
  {
    "caseId": "authority-078",
    "input": "https://example%00.com/01/04912345678904"
  },
  {
    "caseId": "authority-079",
    "input": "https://example%25.com/01/04912345678904"
  },
  {
    "caseId": "authority-080",
    "input": "https://example%GG.com/01/04912345678904"
  },
  {
    "caseId": "authority-081",
    "input": "https://example%C0%AF.com/01/04912345678904"
  },
  {
    "caseId": "authority-082",
    "input": "https://example.com:65536/01/04912345678904"
  },
  {
    "caseId": "authority-083",
    "input": "https://example.com:999999999999999999/01/04912345678904"
  },
  {
    "caseId": "authority-084",
    "input": "https://[1::2::3]/01/04912345678904"
  },
  {
    "caseId": "authority-085",
    "input": "https://[1:2:3:4:5:6:7]/01/04912345678904"
  },
  {
    "caseId": "authority-086",
    "input": "https://[::ffff:192.000.2.1]/01/04912345678904"
  },
  {
    "caseId": "authority-087",
    "input": "https://[1.2.3.4::]/01/04912345678904"
  },
  {
    "caseId": "authority-088",
    "input": "https://[::1]oops/01/04912345678904"
  },
  {
    "caseId": "previous-native-00",
    "input": "https://0x/01/09506000134352",
    "previousNativeLabel": "rejected host 0x"
  },
  {
    "caseId": "previous-native-01",
    "input": "https://0X/01/09506000134352",
    "previousNativeLabel": "rejected host 0X"
  },
  {
    "caseId": "previous-native-02",
    "input": "https://1.0x/01/09506000134352",
    "previousNativeLabel": "rejected host 1.0x"
  },
  {
    "caseId": "previous-native-03",
    "input": "https://0x./01/09506000134352",
    "previousNativeLabel": "rejected host 0x."
  },
  {
    "caseId": "previous-native-04",
    "input": "https://1.0X/01/09506000134352",
    "previousNativeLabel": "rejected host 1.0X"
  },
  {
    "caseId": "previous-native-05",
    "input": "https://1.2.3.0x/01/09506000134352",
    "previousNativeLabel": "rejected host 1.2.3.0x"
  },
  {
    "caseId": "previous-native-06",
    "input": "https://0x7f000001/01/09506000134352",
    "previousNativeLabel": "rejected host 0x7f000001"
  },
  {
    "caseId": "previous-native-07",
    "input": "https://0177.0.0.1/01/09506000134352",
    "previousNativeLabel": "rejected host 0177.0.0.1"
  },
  {
    "caseId": "previous-native-08",
    "input": "https://127.1/01/09506000134352",
    "previousNativeLabel": "rejected host 127.1"
  },
  {
    "caseId": "previous-native-09",
    "input": "https://2130706433/01/09506000134352",
    "previousNativeLabel": "rejected host 2130706433"
  },
  {
    "caseId": "previous-native-10",
    "input": "https://127.0.0.01/01/09506000134352",
    "previousNativeLabel": "rejected host 127.0.0.01"
  },
  {
    "caseId": "previous-native-11",
    "input": "https://1.2.3.4./01/09506000134352",
    "previousNativeLabel": "rejected host 1.2.3.4."
  },
  {
    "caseId": "previous-native-12",
    "input": "https://user:password@example.com/01/09506000134352",
    "previousNativeLabel": "rejected host user:password@example.com"
  },
  {
    "caseId": "previous-native-13",
    "input": "https://user@example.com/01/09506000134352",
    "previousNativeLabel": "rejected host user@example.com"
  },
  {
    "caseId": "previous-native-14",
    "input": "https://%65xample.com/01/09506000134352",
    "previousNativeLabel": "rejected host %65xample.com"
  },
  {
    "caseId": "previous-native-15",
    "input": "https://a..example/01/09506000134352",
    "previousNativeLabel": "rejected host a..example"
  },
  {
    "caseId": "previous-native-16",
    "input": "https://-bad.example/01/09506000134352",
    "previousNativeLabel": "rejected host -bad.example"
  },
  {
    "caseId": "previous-native-17",
    "input": "https://bad-.example/01/09506000134352",
    "previousNativeLabel": "rejected host bad-.example"
  },
  {
    "caseId": "previous-native-18",
    "input": "https://bad_name.example/01/09506000134352",
    "previousNativeLabel": "rejected host bad_name.example"
  },
  {
    "caseId": "previous-native-19",
    "input": "https:///01/09506000134352",
    "previousNativeLabel": "rejected host "
  },
  {
    "caseId": "previous-native-20",
    "input": "https://example.com:/01/09506000134352",
    "previousNativeLabel": "rejected port "
  },
  {
    "caseId": "previous-native-21",
    "input": "https://example.com\\x/01/09506000134352",
    "previousNativeLabel": "rejected URI"
  },
  {
    "caseId": "previous-native-22",
    "input": " https://example.com/01/09506000134352",
    "previousNativeLabel": "rejected URI"
  },
  {
    "caseId": "previous-native-23",
    "input": "https://example.com/01/09506000134352?x=raw space",
    "previousNativeLabel": "rejected URI"
  }
];
const cases=requests.map(test=>{try{return {...test,expected:oracle.normalizeGs1DigitalLink(test.input)}}catch(error){return {...test,expected:{throws:{code:error.code}}}}});
const provenance={description:'Synthetic authority vectors evaluated independently with archived SpecQR TypeScript',upstreamCommit:'16efc6c0a8e397c9df3d051d20fce6c1eebdfad7',nodeVersion:process.version,generatorSha256:sha(readFileSync(fileURLToPath(import.meta.url))),sourceTreeSha256,sourceFiles};
console.log(JSON.stringify({provenance,cases},null,2));

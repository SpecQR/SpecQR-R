# 検証 / Verification

This edition targets portable source on R4.5.3 or later. Actual native verification is performed on Linux x86-64 with R4.5.3 and R4.6.1, the current stable version checked against the official R release page on2026-10-04. Windows, macOS, other architectures, 32-bit R, R versions below4.5.3, and development R are not claimed as tested.

The local interpreters are official CRAN Debian binary packages, installed in an isolated task-owned directory and verified against CRAN's SHA256 package metadata. Only launcher/configuration paths are relocated; there is no global system installation. Exact provenance and hashes accompany the verification receipt. CI uses pinned official R sources and hash-checked test tools.

Required gates:

1. Native base-R unit checks for segments, Unicode/raw data, GF256/RS, all160 version/ECC combinations and1,280 explicit-mask matrices, optimizer exactness, GS1, PNG checksums and resource rejection
2. The unchanged10,186-case language-neutral corpus, including5,610 public and4,576 internal records. It covers all masks, raw-codeword construction,255 RS degrees,65,536 GF products, high-level planning/encoding and Structured Append
3. Independent ZXing-C++ and ZXing Java actual PNG decoding, metadata and payload checks; SVG rasterization and exact RGBA comparison
4. Shared regressions for FNC1 literal percent/consecutive GS, Digital Link dot values/strict authority, dynamic ECC keys and finite print geometry
5. R CMD build/check, installed-library consumer, direct-source consumer, examples and binary-safe CLI with whitespace/control bytes and Unicode paths
6. Final source manifest, source-stable receipts, independent review and post-publication CI on the exact commit

The JSON-line development adapter maps NUL-containing JSON payload text to equivalent UTF-8 raw bytes, because R character values cannot represent NUL. All eight such reference cases remain present and are compared without changing their expected bytes/codewords/matrices. This is an adapter boundary, not a claim that R strings can contain NUL. Applications should use `raw` explicitly.

The reference corpora and hashes are pinned in `verification/fixtures/manifest.json`. Failed/interrupted attempts are retained separately from later corrected runs. A pass is never inferred from a partial run, generated file existence, or a different source revision. Development decoders and rasterizers are not package runtime dependencies. No CRAN submission, tag or release is created by this verification workflow.

Run `R CMD build --no-build-vignettes .`, then `R CMD check --no-manual --no-build-vignettes specqr_0.1.0.tar.gz`. The explicit no-manual option avoids a TeX dependency; Rd documentation and examples are still checked. Hosted CI is a separate gate and cannot be reported as passed merely because equivalent local tests passed.

## Request-bound GS1 URL compatibility

`python3 scripts/verify_gs1.py --rscript /path/to/Rscript --output /tmp/gs1`
executes all 1,411 original requests, all 80 independent current-TypeScript
positives, the complete 49 shared operations and 113 authority controls. Fixture
hashes, per-request hashes, exact typed contracts, source hashes, process status,
stderr and cardinality are mandatory. `scripts/test_verify_gs1.py` exercises ten
fail-closed harness controls. Both existing hosted R lanes require these gates.
The unchanged historical corpus and TS/Nim provenance live in
`verification/fixtures` and `verification/gs1`.

The original 444 render/GS1 unit assertions remain active, with four strict
credential-decoding rejections added for 448 total. Former harmless-host,
empty delimiter/port and backslash rejections are now exact positive assertions;
`verification/gs1/native-assertion-migrations.json` maps the original inputs.
All 102 FNC1 percent vectors, 48 shared PNG decodes, 28 data-preservation
operations and 21 legacy authority operations remain required. Existing QR,
CLI, offline package, independent matrix/codeword and decoder gates are unchanged.

## Additional URL serialization evidence

The independent 139-positive extension also gates raw caret path serialization
as `%5E`, including resolver-prefix builder input. Caret escaping is a URL
serialization correction; decoded GS1 payload bytes do not change.

Outside the original 1,411 inputs, inherited base-path cleanup collapses duplicate
separators (`/a//b` becomes `/a/b`), unlike browser URL serialization. ASCII
reg-name support does not fully validate ACE (`xn--`) labels: some names accepted
here are rejected by a UTS46-aware parser. This is an explicit incomplete IDNA
validation contract, not evidence that such names are valid or safe destinations.
No partial IDNA decoder or new networking dependency is introduced.

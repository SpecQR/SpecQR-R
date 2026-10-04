# Linux continuous integration

The checked-in workflow defines two Ubuntu 24.04 x86-64 lanes: the minimum
supported **R 4.5.3** and **R 4.6.1**, the stable release selected on 2026-10-04.
It builds the official CRAN source distributions rather than using a moving
`release` alias or binaries compiled for a newer system C library. The workflow
has not yet been executed on GitHub-hosted runners. Local verification and
installer self-tests are separate evidence; neither is a hosted CI pass.
Windows, macOS and other architectures are not claimed as verified.

Both lanes require the native unit suite, complete reference corpus, CLI
contract, package build/check/install, and clean offline installed-package
consumers implemented by `scripts/verify_native.py`. Separate required steps
exercise ZXing-C++ 3.1.1 actual PNG decoding, ZXing Java 3.5.4 PNG and matrix
decoding, independent librsvg SVG rasterization and PNG pixel comparisons,
and shared regressions including strict Digital Link authorities. Harness
self-tests and installer security/failure fixtures are mandatory too.

Decoder scales retain their reviewed defaults: C++ uses 8 and Java uses 3.
These lanes do not assert that Java's detector passes at the library's default
scale 8. Logs and JSON receipts give the actual assertions and counts for each
run; a version matrix is not a substitute for those receipts.

## Pins and runtime dependencies

The installer verifies a downloaded archive before extracting or executing it.
The accepted R source SHA-256 digests are:

- R 4.5.3: `aa5c1ed4293c7271ac513d654670356ac0e8a6ad5e42be014365d11150b5b8f2`
- R 4.6.1: `4da6e61d2c0aac5f14a2e7e432cb5fcc269efe83da4293050ba7f03dff4e2cf4`

They come from the official [R 4.5.3 announcement](https://stat.ethz.ch/pipermail/r-announce/2026/000718.html)
and [R 4.6.1 announcement](https://stat.ethz.ch/pipermail/r-announce/2026/000727.html).
The exact CRAN download URL, expected and actual digest, build commands, logs,
`config.log`, runtime probe and bundled recommended-package archive digests
are retained. Extraction rejects paths or links outside the R source tree,
duplicate members, special files and oversized archives before writing files.

The build includes the recommended packages already contained in the pinned
R source archive, including `codetools` for `R CMD check`. It fails if bundled
`codetools` is absent; it does not fetch a replacement from a package repository.
No contributed R package is a SpecQR runtime dependency. R's recommended
packages, compilers, Python, ZXing, Pillow, Java and librsvg are development or
verification tools, not encoder runtime dependencies. The CI R build disables
X11, Tcl/Tk, readline and system bitmap devices; SpecQR's PNG and SVG encoders
remain pure R and do not use these devices.

`requirements-ci.txt` pins test-only binary wheels by version and SHA-256 for
Linux x86-64 / CPython 3.12. Pip requires hashes, disallows source builds and
dependency resolution, and installs into a temporary directory. The ZXing Java
jar is pinned by SHA-256. Official Ubuntu apt repositories provide the
compiler/build libraries, Java 17 and librsvg; their installed package versions
are recorded, not frozen. The Ubuntu runner image and its Python 3.12 can
receive patches. This is source-hash-bound verification, not a claim of
bit-for-bit reproducible R toolchain binaries.

Official actions are commit-pinned to
[checkout v7.0.1](https://github.com/actions/checkout/commit/3d3c42e5aac5ba805825da76410c181273ba90b1)
and [upload-artifact v7.0.1](https://github.com/actions/upload-artifact/commit/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a),
verified against their release targets; both use Node 24. The token has only
`contents: read`. There is no persistent checkout credential, cache, secret,
OIDC grant, repository mutation or release publication. Artifact upload uses
GitHub's per-job artifact service.

## Source identity and intentional changes

`prepare_ci.py stage` checks the committed `SOURCE-SHA256.json`, copies its
validated inventory to a new temporary directory, and creates a deterministic
source ZIP. The verifiers run from the staged source, bind their receipts to
its hashes and check the archive passed to `verify_native.py`. The manifest
includes the workflow, helpers, test lockfile and documentation. CI never
refreshes the manifest to make unexpected changes pass. A final independent
manifest check revalidates the staged source after all verification steps,
including when an earlier check failed.

After an intentional, reviewed edit, maintainers regenerate it explicitly:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/prepare_ci.py manifest
python3 scripts/prepare_ci.py stage --output /tmp/specqr-r-stage
```

The explicit `manifest` command rewrites `SOURCE-SHA256.json` in place. Review
and commit that file together with the intended edits. Use a fresh stage
destination. A digest binds evidence to bytes; it does not authenticate the
publisher. A later intentional change has a new source manifest/archive hash.

## Evidence, failures and required checks

Each lane allows up to 180 minutes for source-building R and interpreted-R
verification. Bash explicitly enables `-e` and `pipefail`; a failing verifier
cannot be hidden by `tee`. Independent checks continue after a test failure
when their prerequisites succeeded. No step uses `continue-on-error`.

Evidence initialization precedes staging, so a manifest failure still leaves
a log to upload. Compiler, configure, build, install, decoder, package-check
and native failure logs are retained. Native evidence collection and artifact
upload run on success or failure; raw native JSON, logs and R test-output
globs are also included in case collection fails. Cancellation or forced runner termination may still
prevent a complete artifact. Build trees and R installations are not uploaded.

Each artifact contains the exact checkout commit, deterministic source ZIP,
staging report, host/tool versions and verification receipts. Artifact paths
record the original runner provenance. Retention is 14 days; download release
evidence before expiry if it must be retained longer.

`Required Linux checks` succeeds only if every R matrix lane succeeds. A failed,
skipped or cancelled lane makes that aggregate fail. Repository owners can
select that name in branch protection; this workflow does not configure branch
protection itself. Offline consumers test their own isolated package/repository
configuration. Those settings are not an OS-level network sandbox.

## Small offline installer rehearsal

```sh
python3 scripts/install_ci_tools.py self-test
```

These fixture tests cover a valid archive, safe internal links, traversal and
link escapes, duplicate/special members, wrong roots, required bundled
`codetools`, correct/incorrect digests and preserving a failed process's exit
status and log. They do not build R or represent a hosted run. Source building
requires the development packages listed in the workflow and several gigabytes
of free space; use a fresh temporary tool destination.

## Bounded default-scale PNG verification

The required C++ PNG lane uses the default scale8 and all764 symbols, with one real R process for each of725 requests. Every process must exit0 with no stderr or trailing output. `verify_default_scale.py` applies the documented `R_MAX_VSIZE=1073741824` vector-heap limit and `R_GC_MEM_GROW=0`; this is not an OS RSS limit. The wrapper records per-request hashes and process outcomes in a compressed ledger. Java detection retains scale3 as separately identified coverage. The180-minute job limit accommodates native source builds and the fresh-process default8 replay. No reduced-scale pass substitutes for the default8 gate.

## Auxiliary-process and Java detector controls

Machine-readable Java, SVG-rasterizer and R probe processes must exit cleanly
without stderr; receipts record both output hashes and sizes. The separate Java
scale-8 characterization compares the real R PNG with an independently encoded
PNG having identical luminance pixels, and keeps matrix, scale-3 and C++ payload
controls. A matching Java PNG rejection is recorded as a detector rejection,
not a successful decode. These sampled controls do not replace the complete
C++ default-scale-8 gate or the strict Java scale-3 suite.

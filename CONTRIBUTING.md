# Contributing

Keep runtime algorithms in base R, with no external packages, compiled QR code,
FFI, web services, or dynamic resources. Preserve payload bytes and explicit
validation. Add regression tests before fixing errors and retain failed evidence.

After intended edits, rebuild and review the source manifest, then stage an
immutable source archive. Run unit checks, both native R version lanes, the full
pinned corpus, independent decoders, CLI and package consumers against that
archive. Do not modify the source or manifest afterward: an altered source tree
invalidates prior source-bound evidence. Do not regenerate expected
fixtures from the implementation under test. Public CI tests Linux only.

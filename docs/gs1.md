# GS1 and Digital Link

SpecQR implements a bounded 50-AI catalog, check digits, element strings and an
offline Digital Link adapter. It is not a complete GS1 General Specifications
validator. Dates are checked for their fixed six-digit representation, not
calendar validity; application-specific AI associations and the entire current
GS1 dictionary are outside this catalog.

```r
library(specqr)
items <- parse_gs1_human_readable("(01)09506000134352(10)LOT%1(17)251231")
raw <- create_gs1_element_string(items)
link <- create_gs1_digital_link(items, base_url="https://id.gs1.org")
parsed <- parse_gs1_digital_link(link)
checked <- validate_gs1_digital_link(link)
```

Elements are `GS1Element(ai,value)` or `list(ai="10",value="LOT")` objects in a list. Both fields must be scalar strings. Numeric conversion is never used for AI/value input, so leading zeroes cannot be lost. Data frames are rejected; explicitly turn rows into element lists when appropriate.

## Catalog and validation

`get_supported_gs1_ais()` returns metadata for:

* `00`, `01`, `02`, `10`, `11`, `12`, `13`, `15`, `16`, `17`, `20`, `21`, `22`
* `30`, `37`, `240`, `241`, `400`, `410`–`415`, `420`, `422`, `424`–`426`
* Concrete `3100`–`3105`, `3200`–`3205`, and `91`–`99`

`get_gs1_ai_info(ai)` returns one entry or `NULL`. Metadata includes fixed or
variable length, numeric/text kind, check-digit rule, separator rule, Digital
Link role, and eligible primary key. Generic GS1, GTIN, and SSCC check digit
helpers calculate, append where applicable, and validate the modulo-10 digit.
AI `01`/`02` enforce GTIN check digits and `00` enforces SSCC check digits. AI
`414` is a 13-digit primary key in this bounded profile; no additional GLN
check-digit rule is claimed.

`parse_gs1_human_readable`, `parse_gs1_element_string`, and
`create_gs1_element_string` convert parenthesized/raw representations.
`normalize_gs1_elements` accepts either input representation or element objects;
`gs1_to_human_readable` produces the parenthesized representation.

Values must use printable ASCII and contain neither parentheses nor ASCII GS.
A literal percent sign remains a literal percent sign. Variable-length fields
receive ASCII GS only when another element follows. Unexpected, doubled, or
trailing separators fail. A final variable-length value that ends in an
apparently concatenated fixed-length AI/value is rejected as an ambiguous
missing separator; this is a conservative bounded suffix heuristic.

`validate_gs1_elements` and `validate_gs1_element_string` return structured list results. `collect_all_errors=FALSE` limits element-validation
errors to the first failure; `context="digital-link"` requires a supported
primary AI. Unsupported AIs cannot be enabled with `allow_unsupported_ai`.
Custom iterator protocols are not supported.

## Digital Link profile

`create_gs1_digital_link`, `parse_gs1_digital_link`,
`validate_gs1_digital_link`, and `normalize_gs1_digital_link` never fetch URLs.
They use a bounded HTTP(S) URL adapter with strict payload decoding. This is
not complete WHATWG URL or IDNA/UTS46 conformance:

* HTTP(S) slash spellings and authority/path backslashes are repaired; edge
  ASCII C0/space is trimmed and TAB/LF/CR removed. A query backslash remains data
* Nonempty fragments reject. Empty `#` is accepted, retained by creation and
  removed by normalization. Empty builder `?` is replaced; nonempty query rejects
* ASCII reg-name hosts are lowercased, including harmless punctuation/empty DNS
  labels accepted by browser URL parsing. ASCII percent-encoded hosts decode
  strictly; encoded authority delimiters and empty hosts reject
* Numeric IPv4 accepts short, octal, hexadecimal and integer aliases with checked
  accumulation, exact component bounds and canonical dotted-decimal output.
  `0x`, `0X`, `1.0x`, `0x.`, `1.0X`, and `1.2.3.0x` are valid aliases;
  `example.0x`, malformed numeric candidates and overflow reject
* Bracketed RFC IPv6, including valid dotted-decimal tails, uses lowercase hex
  groups and the first longest zero run. Zone identifiers reject
* Credentials are escaped and preserved as URL text, without fetching or
  authentication; diagnostics never echo extra credential data
* Empty ports are omitted. Decimal ports use checked 0–65535 bounds, allow
  leading zeros and omit HTTP/HTTPS defaults
* Percent escapes and decoded UTF-8 remain strict in host, credentials, path
  and query. Invalid UTF-8 and decoded NUL reject; R strings cannot contain NUL
* Unicode/IDNA hostname conversion remains outside this base-R-only adapter.
  No partial UTS46 or IDNA implementation is claimed. An ASCII hostname can be
  supplied by an application that has independently resolved its IDNA policy

The adapter does not validate DNS existence, reachability, URL trust, or SSRF
safety. Parsing performs no networking.

Primary AIs are `00`, `01` (builder default), and `414`. Qualifiers `10`, `21`,
`22` can appear in the path only after `01`. Other supported AIs are query data.
AIs cannot repeat within a Digital Link. `path_ais=character()` keeps all qualifiers in
the query. Dot-only qualifier values `.` and `..` are always kept in the query,
even when selected for the path; actual path dot segments after the primary AI
are rejected before interpreting AI/value pairs. Percent-encoded dots are also
rejected there. A literal value `%2e` is encoded as `%252e` and preserved.

The builder normalizes resolver-prefix dot segments, then rejects any surviving
prefix component that decodes once to a primary AI, including `%30%31`. This
prevents generated links from having an ambiguous payload start. Primary-looking
components removed by preceding dot normalization are allowed. Other prefix
components preserve existing escapes; raw UTF-8 and path characters are percent
encoded without changing their decoded value.

Query decoding uses form semantics (`+` is a space), with strict percent/UTF-8
validation. `unknown_query="preserve"` retains non-GS1 keys, duplicates, order,
empty values, and decoded whitespace; `"reject"` fails on them. Numeric AI-shaped
keys still require catalog support. Normalization uses the
`"specqr-deterministic"` mode, places eligible qualifiers in the path, sorts GS1
query attributes lexically by AI/value, and appends unknown query pairs in their
original order. Dot-only query qualifiers remain in query. It is idempotent for
accepted normalized output.

Validation reports HTTP and preserved-unknown-query warnings. The
`normalize=TRUE` validation option is unsupported; call the explicit normalizer.
Failures throw `specqr_invalid_gs1` with stable `error_code(error) == "INVALID_GS1"`
and a finer `detail_code`; validation issues expose that finer code, message,
reason and applicable context fields.

## Bounds

Text is valid UTF-8 and at most 1,000,000 UTF-16 code units (with a preliminary
4,000,000-byte ceiling). Element-list aggregate AI/value work is capped at
1,000,000 bytes; valid AI/value text is ASCII. Element and query pair counts are
limited to 16,384, and path component counts to 32,769. Limits are checked before
unbounded iteration, numeric parsing, or large output growth.

## URL 互換性の回復

従来の狭い URL 受理範囲を見直し、TypeScript の固定ソース
`16efc6c0a8e397c9df3d051d20fce6c1eebdfad7` が受理する 77 件と、IPv6 の
正規化 3 件を回復しました。通常の QR の符号化・行列・描画・FNC1 の意味や
実行時依存関係は変更していません。無害な URL 表記の受理範囲を広げる変更です。

元の 1,411 入力は変更せず、現在の TypeScript を実行して得た型付き期待値と
照合します。R で残る 168 差分は診断 132、不正 percent/UTF-8/NUL 20、
Unicode/IDNA host 12、raw Digital Link primary 検査 2、安全な dot query
生成 2 です。診断 5 件の順序変更は固定した旧 Nim による意味的 witness で
独立に確認しています。これらをすべて同じ「不正 URL」とは扱いません。

検証は 80 正例、既存 49 authority/Digital Link 操作、追加 113 authority
対照例と process の失敗・余分な出力・stderr・型不一致を明示的に検査します。
期待値を候補実装の出力から作っていません。

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

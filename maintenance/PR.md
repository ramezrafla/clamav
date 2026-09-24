Scanning with a large logical-signature database repeatedly allocates 64-slot
counter/offset rows and reparses the same logical expressions. This change sizes
ordinary signature rows to their actual width and shares immutable compiled
expressions within each target matcher. Compatibility-sensitive signatures keep
64 slots, and expressions outside bounded compilation limits use the existing
interpreter.

The series also reuses PCRE2 match data within a pattern's global-match loop,
specializes grayscale Lanczos resizing without changing fuzzy-image hash pixels,
and packs AC candidate lists with cached rejection fields. Generated Rust
bindings follow the updated C layouts. cbindgen dependency discovery is limited
to the build target to support offline builds.

### Measurement

| Workload | Original time | Modified time | Time reduction | Original peak RSS | Modified peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 worker, 60 scans | 30.483 s | 13.238 s | 56.6% | 1,627.9 MiB | 1,584.5 MiB |
| 4 workers, 120 scans | 30.622 s | 13.771 s | 55.0% | 2,123.5 MiB | 1,684.8 MiB |

All 720 timed scan statuses and exact detection names match. Library, database
and corpus hashes remained unchanged.

These are native persistent-engine measurements against unmodified scanner code
at `72cd48c9faed4fa4afc22bc4ed0b9b19f8d3f8f7`, using 7,497,205 supplied signatures and
60 decoded repository HDB fixtures. Two alternating rounds per configuration use
one shared i5-1235U host. The clean cache is disabled; scan timing excludes engine
loading and warmup, while peak RSS includes both. This is a test-corpus result,
not a production workload or TCP latency claim. See
`docs/optimization-results.md` for compiler settings, artifacts and reproduction.

There is an explicit memory tradeoff: AC list records grow from 24 to 32 bytes
on this platform, and retained construction allocations contribute to roughly
100 MiB more idle-engine memory in the earlier isolated measurement. Compact
per-scan state reduces active memory; it does not remove that idle cost. The
compiled expression storage is capped at 1 MiB per target matcher.

### Validation

- Native libclamav, Rust, clamscan and sigtool suites pass.
- Regression tests cover PCRE global counts/captures/limits, pixel equivalence,
  compact row boundaries and compatibility fallbacks, expression count/ID
  semantics, sharing, and interpreter fallback after compilation limits.
- Full supplied database: 2,187,229 expression comparisons against the original
  interpreter pass. All 313,309 ordinary logical signatures use 1,830 shared trees.
- All 13 native matcher cases pass Valgrind: zero memory errors and zero
  definitely/indirectly/possibly lost bytes.
- Clang-format 16, rustfmt and whitespace checks pass for modified source.

No signatures, scan windows or parser coverage are removed. The scope is several
related optimization commits; this is prepared as a draft to allow discussion of
the AC memory tradeoff and whether maintainers prefer separate PRs. Private
signature databases, deployment configuration and Docker packaging are excluded.

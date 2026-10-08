# Performance benchmarks

GDSQL includes a deterministic benchmark harness for measuring the current
ConfigFile backend. It produces Markdown for quick review and JSON for later
comparison or visualization. Benchmarks are kept separate from correctness
tests and do not fail because a query exceeded a timing threshold.

## Run a benchmark

From the repository root:

```bash
./scripts/run-configfile-benchmark.sh smoke
./scripts/run-configfile-benchmark.sh standard
./scripts/run-configfile-benchmark.sh full
```

Profiles select dataset size and a practical default sample count:

| Profile | Row counts | Default samples | Intended use |
|---|---|---:|---|
| `smoke` | 1,000 | 3 | Verify the harness and report format |
| `standard` | 1,000 and 10,000 | 3 | Routine local or CI comparison |
| `full` | 1,000, 10,000, and 100,000 | 1 | Explore the practical ConfigFile limit |

The full profile can take tens of minutes because ConfigFile rewrites the
complete table for mutations and parses the complete file on a cold read. This
is evidence the benchmark is intended to expose, not a harness failure. The
harness prints the active case while it runs so a long capacity investigation
does not look stalled.

Set `GODOT_BIN` when Godot is not available as `godot`. The sample count can be
changed without changing the fixture:

```bash
GDSQL_BENCHMARK_ITERATIONS=5 ./scripts/run-configfile-benchmark.sh standard
```

## Find the reports

Each run creates:

```text
reports/benchmarks/configfile/<UTC timestamp>-<profile>/report.md
reports/benchmarks/configfile/<UTC timestamp>-<profile>/report.json
```

The `reports/` directory is intentionally ignored by Git. A manual **GDSQL
Benchmarks** workflow runs the same harness and uploads both files as a GitHub
Actions artifact. Use the same profile, Godot build, machine, and iteration
count when comparing two revisions.

## What is measured

Every dataset uses the same formula-generated scalar rows and indexes. No
random generator or external asset affects the fixture.

Large read fixtures are seeded directly with GDSQL's current ConfigFile codec,
then reopened through the normal public database API before measurement. Seed
time is excluded: otherwise the known staged-insert cost would prevent the
100,000-row read cases from completing in a useful period. The separate
1,000-row insert probe does use the public query API and preserves that cost in
every report. Direct fixture setup duration is recorded separately so it is
visible without being confused with public query performance.

| Case | Question answered |
|---|---|
| 1,000-row batched insert probe | How expensive is staging, validating, and committing one public-API batch? |
| Database reopen | How expensive is catalog and schema reconstruction? |
| Bounded scan | Does returning a small middle window avoid decoding unused rows? |
| Ordered index window | What does a limited ordered read cost? |
| Primary-key lookup | What does one identity lookup cost? |
| Secondary-index lookup | What does one stable external-key lookup cost? |
| Filtered ordering | What does filtering an indexed group and sorting its results cost? |
| Full count | What is the baseline cost of visiting the whole table? |
| Single indexed update/delete | How does rewriting the table scale for one changed row? |

Query cases have explicit `cold` and `warm` states. A cold sample invalidates
GDSQL's ConfigFile cache, so it includes reading and parsing the table file. A
warm sample reuses the cached ConfigFile. Both still execute validation,
planning, row decoding, and result construction.

## Read the results

Use the Markdown table for a first look. The JSON report preserves individual
microsecond samples, environment information, table size, query statistics,
and process-memory observations.

Important fields include:

- `median_usec`, `min_usec`, and `max_usec`: observed wall-clock duration;
- `table_file_bytes`: final serialized table size;
- `storage_rows_scanned` and `storage_rows_returned`: logical storage work;
- `storage_bytes_read`: table bytes read on measured cache misses;
- `storage_physical_read_bounded`: whether the backend bounded physical I/O;
- `scan_window_pushed` or `ordered_index_window_pushed`: whether planning
  pushed the requested result window into storage;
- `process_peak_memory_bytes`: Godot's process-wide peak allocator usage.

ConfigFile currently reports the complete table-file size as bytes read on a
cache miss even when row decoding is bounded. It can avoid decoding irrelevant
rows, but it cannot parse only part of one ConfigFile. A future paged backend
should report bounded pages and bytes for the same logical benchmark cases.

Memory values are observations rather than isolated allocations. Godot caches,
allocator reuse, prior cases, and the engine itself contribute to the
process-wide peak. Compare memory only between equivalent runs.

## What the ConfigFile baseline reveals

The benchmark distinguishes several costs that can otherwise look like one
generic "database is slow" problem:

- a warm primary-key or secondary-index lookup can remain inexpensive because
  it reuses an already parsed ConfigFile and stored index sections;
- the equivalent cold lookup still parses the complete table file, so its cost
  grows with physical file size even when only one row is returned;
- a deep bounded scan can avoid decoding rows outside the result window, but
  cursor advancement still enumerates the ConfigFile section set for each
  batch; and
- changing one row still validates the effective table, rebuilds affected
  indexes, and saves the complete ConfigFile, so large indexed tables have a
  much lower practical write ceiling than their warm lookup time suggests.

These are backend limitations rather than query-model limitations. The same
logical cases become acceptance benchmarks for paged storage: bounded scans
should read bounded pages, cold lookups should avoid parsing unrelated rows,
and a one-row mutation should not rebuild or rewrite an entire table.

## Comparison policy

Do not compare one laptop run directly with a CI run. Keep reports first and
establish several stable baselines before defining budgets. A useful
comparison records:

- the same GDSQL revision range and fixture format version;
- the same Godot version and build type;
- the same operating system and processor;
- the same benchmark profile and iteration count; and
- similar background load and thermal conditions.

Timing thresholds can be introduced per case only after the normal variation
is understood. Correctness tests remain responsible for semantic behavior;
benchmarks describe cost and scaling.

## Current scope

This first harness isolates scalar ConfigFile behavior. Resource identity,
deferred materialization and prefetch, in-memory save checkpoints, and Managed
Content composition require separate fixtures so their costs are not confused
with scalar serialization. Those suites can reuse the report format after the
ConfigFile baseline is stable.

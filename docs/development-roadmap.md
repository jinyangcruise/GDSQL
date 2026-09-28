# GDSQL Development Roadmap

## Product direction

GDSQL is **table-first and graph-capable**. The conventional table workbench is
the primary editor surface. The graph remains an optional advanced frontend and
is not active delivery work.

Every frontend produces canonical `GDSQLQuerySpec` values and executes through
`GDSQLDatabase`. The catalog remains the schema authority. Models bind typed
code and behavior to existing tables; they never create, alter, or migrate a
table implicitly.

GDSQL supports two setup profiles:

| Profile | Content role | Intended use |
|---|---|---|
| Direct Content | Project-authored content under `res://` | Small and medium projects with minimal setup |
| Managed Content | Derived `effective_content` built from a base and optional packages | Customizable or moddable projects requiring deterministic overlays |

Changing profiles changes composition guidance, not project data. Moving
physical data, package metadata, references, or save expectations is an
explicit migration.

## Current baseline

The current implementation provides:

- Canonical typed queries, expressions, planning, transactions, indexes, joins,
  grouping, ordering, mutations, and structured diagnostics.
- Table browsing, filtering, nested typed WHERE groups, paging, row editing,
  duplication, bounded Undo/Redo, and Resource-aware fields.
- Schema authoring with defaults, indexes, generated values, Resource
  ownership, and same-database foreign keys.
- Direct and Managed Content onboarding, runtime roles, save slots,
  checkpoints, deterministic content overlays, caching, provenance, and save
  compatibility reports.
- Generated/user-owned model bindings, inferred same-database navigation,
  explicit many-to-many relationships, and cross-role content references.
- Multi-table navigation and read-only Godot-AI MCP inspection tools.

Implementation detail belongs in `docs/architecture/`, public usage belongs in
the VitePress guides, and completed change history belongs in Git. This file
tracks only product direction, active work, and deliberately deferred work.

## Active priorities

| Priority | Outcome | State |
|---|---|---|
| High — first | Bounded Resource Stage A: prevent accidental loading | Roadmap contract defined; architecture contract required |
| High — second | Versioned migration v1 and compatibility policy | Architecture decision and implementation required |
| High | Release, recovery, performance, and supported-version QA | Required before a stable release |
| Medium | Godot-AI lifecycle verification | Tools work; reload, disable, and teardown need live-editor verification |
| Medium | Large reference-picker search and paging | Current authoring picker is intentionally bounded |
| Medium | Opt-in release update checker | Blocked by version and compatibility contracts |

## Committed delivery sequence

The order below is intentional and should remain stable across development
sessions unless new evidence changes an architectural dependency:

1. **Resource Stage A — avoid accidental loads.** Stabilize referenced-asset
   identity, required-column reads, explicit materialization, and contextual
   diagnostics. Preserve the existing eager public behavior only for Resource
   values an operation actually needs.
2. **Migration v1 — durable schema history.** Build ordered forward schema
   migrations, checksums, an applied ledger, dry runs, backups, recovery, and
   headless validation on top of the stable stored-value boundary.
3. **Migration data/save phases.** Add bounded data transformations,
   multi-table orchestration, and migration of older `user://` saves after the
   schema-only path is reliable.
4. **Resource Stage B — explicit deferred loading.** Add opt-in handles,
   threaded loading, and prefetch scopes only when the simple eager path and
   migrations are stable.
5. **Bounded reads and paged binary storage.** Add cursor/page execution before
   implementing the binary backend so paging does not inherit full-snapshot
   behavior.
6. **Optional working-set eviction.** Add manual or budgeted release policies
   only after profiling demonstrates that projects need them.

Do not expand Resource Stage A into a complete asset-streaming subsystem before
migration v1. Do not start migration value copying while storage decoding still
loads referenced assets as an implicit side effect. The two high-priority
tracks are sequential for this reason, not competing parallel rewrites.

## 1. Resource materialization and memory policy

Referenced Resource columns persist compact UID/path locators, but persistence
size and runtime memory behavior are separate concerns.

### Why this is a foundation concern

Referenced storage solves database size: the row contains a small, versioned
UID/path locator instead of serialized mesh, texture, scene, or audio bytes. It
does not by itself solve runtime loading. The locator becomes inexpensive only
if it can remain a locator until game code actually needs the asset.

Current ConfigFile decoding resolves every referenced locator with
`ResourceLoader.load()`. Opening a ConfigFile registration does not itself read
every row, but a table scan currently decodes every column before filtering,
projection, or `LIMIT`. As a result:

- selecting only NPC names may still load every NPC mesh and voice;
- editor pagination can display 25 rows after loading Resources from the full
  scanned table;
- `COUNT` and other operations that do not return Resource values can still pay
  Resource-loading cost;
- in-memory hydration can retain Resources for the database lifetime; and
- a Managed Content rebuild can resolve assets while it is only copying rows
  into a disposable cache.

An asset that is loaded but never rendered avoids draw calls and normal
per-frame rendering cost, but it can still consume RAM or VRAM, load
dependencies, compile or upload rendering data, and create a synchronous load
spike. This matters first for asset-heavy 3D, audio-heavy, mobile, web, VR, or
modded projects, but the database contract must not make it impossible to solve
later.

Preloading remains a valid policy. Small games with a bounded content set
should not be forced to use handles, streaming, or eviction. The concern is
that GDSQL currently chooses eager loading as a side effect of reading storage,
rather than as an explicit application policy.

### Separate performance dimensions

Resource loading and table paging are related but independent:

| Dimension | Current limitation | Primary solution |
|---|---|---|
| Asset materialization | Decoding a locator loads the external asset | Preserve a reference value and resolve it only when required |
| Column selection | A row read decodes all stored columns | Push required-column information into storage reads |
| Table I/O | ConfigFile parses a complete table file on first access | Future paged binary storage and indexed page reads |
| Query working set | Scan operators materialize complete snapshots | Batch/cursor reads and limit/index-aware execution |
| Asset lifetime | Results and in-memory rows may retain loaded Resources | Explicit ownership, prefetch scopes, and optional eviction |

A paged binary backend cannot fix eager Resource loading if it returns rows
through the current eager decoder. Conversely, deferred Resource references can
provide a large memory and loading improvement while ConfigFile remains the
storage backend. Binary paging becomes necessary when row count, table-file
parsing, or database working-set size is itself the problem.

### Supported strategies

The future design should support increasingly advanced choices without making
them mandatory:

| Strategy | Intended use | Tradeoff |
|---|---|---|
| Eager materialization | Small bounded content sets | Simplest typed API; assets remain loaded while referenced |
| Separate metadata and asset tables | Available now for medium projects | Explicit extra lookup; clear and backend-independent |
| Deferred Resource reference | Asset-heavy rows | Requires an explicit load/materialization API |
| Prefetch scope | Areas, encounters, menus, or upcoming characters | Game must predict a useful loading boundary |
| Manual release | Deterministic scene or area ownership | Game code owns lifecycle discipline |
| Budgeted working-set eviction | Large dynamic or modded content | More runtime complexity and platform-specific tuning |
| Paged binary rows | Very large tables and saves | New backend and cursor/page execution; does not load assets itself |

Separating lightweight definitions from heavy assets is the stable authoring
pattern available today:

```text
npc_definitions
    id, name, stats, dialogue_id

npc_assets
    npc_id, mesh, textures, voice
```

The game can browse `npc_definitions` broadly and retrieve one indexed
`npc_assets` row when it prepares that NPC. This pattern remains useful after
deferred references and binary paging are implemented.

### Required invariants

The architecture work must preserve these rules:

1. A referenced asset locator is authoritative persisted data. A loaded Godot
   `Resource` is a runtime materialization of that value, not storage state.
2. Resource loading remains outside `QuerySpec`; canonical queries describe
   data intent without depending on `ResourceLoader` or cache state.
3. Storage backends expose the same referenced-asset semantics. ConfigFile and
   paged binary formats may encode locators differently, but neither changes
   query or model meaning.
4. Existing eager Resource fields remain the simple default until a user opts
   into a deferred contract. A compatibility change must not silently replace a
   concrete `Mesh` model property with an unrelated object.
5. A transparent lazy proxy must not pretend to be every concrete Resource
   subtype. Deferred fields expose an explicit reference/handle and validate
   their expected subtype before returning a loaded Resource.
6. Referenced Resources may be shared through Godot's cache. GDSQL must release
   only references it owns and must not claim it can forcibly unload an asset
   still used by a scene, model, result, or another system.
7. Owned Resource columns remain row-owned values. They are not converted into
   external lazy references implicitly.
8. Dirty mutable data checkpoints before working-set eviction. Immutable
   content and disposable caches may be reloaded or rebuilt.
9. Filtering a referenced Resource property explicitly requires that Resource
   to be resolved unless the backend has equivalent indexed metadata. This
   cost must be visible rather than hidden.
10. Missing, unreadable, or type-mismatched assets return diagnostics carrying
    database, table, row, column, locator, and expected type.

### Contract evolution before binary storage

Exact class names belong in the architecture proposal, but the runtime needs
four capabilities before a paged backend can deliver meaningful gains:

1. **Storage-neutral references.** Decoding must be able to return validated
   asset identity without loading the asset. The current locator concept must
   not remain an implementation detail usable only by ConfigFile storage.
2. **Bounded read requests.** Storage reads need required columns, lookup or
   scan range, batching/page information, and Resource materialization intent.
   A backend that cannot optimize a request may fall back to a full read while
   preserving semantics.
3. **Column dependency analysis.** Planning/execution must identify columns
   required by predicates, joins, grouping, ordering, projection, identity, and
   mutation safety. Projection alone is not sufficient because an unreturned
   column may still be needed to filter or order rows.
4. **Explicit materialization.** Result and model materializers decide whether
   a projected reference becomes a concrete Resource, remains a deferred
   handle, or is prefetched asynchronously. Storage decoding does not make this
   presentation decision.

The first implementation can preserve current public behavior by eagerly
materializing projected Resource fields while avoiding loads for fields that
the operation never needs. Deferred handles become an explicit later API.
Generated models continue to use concrete Resource properties for eager fields;
a deferred field requires separately generated reference access and a typed
load helper.

### Delivery stages

#### Stage A — avoid accidental loads

- Keep referenced locators unresolved through generic storage decoding.
- Determine the columns required by a planned operation.
- Do not resolve referenced assets for `COUNT`, unrelated projections, or
  metadata-only cache copying.
- Materialize required Resource result values synchronously for compatibility.
- Add contextual diagnostics and an injectable resolver so behavior can be
  tested without loading real assets.

This stage is backend-independent and provides the main benefit for ordinary
small and medium projects.

#### Stage B — explicit deferred loading

- Add opt-in deferred Resource fields or result materialization.
- Provide synchronous load, threaded request, status, and completion behavior
  without blocking ordinary query construction.
- Provide bounded prefetch scopes suitable for a scene, area, encounter, or UI
  screen.
- Document how consumers release scene, model, result, and cache references.

This stage is for asset-heavy projects and should not complicate the default
workflow.

#### Stage C — bounded table reads

- Extend storage capabilities with batch/page reads and ordered indexed access.
- Let scan execution consume bounded batches instead of requiring one complete
  `TableSnapshot`.
- Push `LIMIT`/`OFFSET` only when doing so preserves filter, sort, aggregate,
  distinct, and join semantics.
- Measure row bytes/pages read separately from Resources materialized.

ConfigFile may continue parsing a whole table file while implementing this
contract through a compatibility adapter.

#### Stage D — paged binary backend

- Store versioned table headers, schema fingerprints, generated-key state,
  row/index roots, and independently addressable pages.
- Read only the row and index pages required by the bounded storage request.
- Preserve the same external Resource locator and materialization rules.
- Add clean-page eviction and crash-safe persistence without exposing binary
  details above storage infrastructure.

#### Stage E — optional working-set policy

- Implement `LOAD_ALL`, `LAZY_TABLES`, `PAGED`, and `MANUAL` policies described
  in `docs/architecture/databases.md` only after their underlying capabilities
  exist.
- Add explicit clean-table/page release and optional budgeted eviction.
- Keep automatic asset eviction opt-in; project code may already own a more
  appropriate scene, area, or asset lifecycle.

### Verification criteria

The foundation is successful when tests and profiling can demonstrate that:

- selecting or counting scalar NPC fields performs zero Resource resolutions;
- a primary-key asset lookup resolves only the requested row's projected asset;
- pagination does not resolve assets discarded only by the final page limit
  when filtering and ordering do not require those assets;
- Managed Content cache copying preserves locators without loading the assets;
- in-memory hydration can retain reference identities without retaining every
  concrete Resource;
- a Resource-property predicate documents and measures its required loads;
- eager and deferred model fields retain their declared type behavior;
- releasing all GDSQL-owned references permits Godot to reclaim an otherwise
  unused asset; and
- ConfigFile and future paged binary backends pass the same semantic tests while
  reporting different I/O and working-set statistics.

Profile Resource-resolution count, synchronous load time, peak RAM/VRAM,
retained GDSQL references, scanned rows, bytes/pages read, and cache hit rate.
Optimization decisions should follow measurements on supported target hardware,
not project-size labels alone.

## 2. Versioned migrations

Models remain bindings, not migrations. A migration is project-owned,
version-controlled history describing how an older catalog and its data reach
the current catalog.

Resource Stage A precedes this work because migrations, dry runs, backups, and
cache rebuilds must copy referenced-asset identity without loading the assets.
Migration v1 begins after that stored-value/materialization boundary is stable.

Before implementation, update the architecture documents that currently place
a general migration framework outside scope. The first supported slice should
provide:

1. Stable ordered migration IDs, descriptions, checksums, and target database
   registrations or roles.
2. Forward-only typed schema steps built from the existing
   `GDSQLTableAlteration` vocabulary.
3. A persisted applied-migration ledger and schema fingerprint.
4. Dry-run planning with affected objects, destructive classification, and
   structured diagnostics.
5. Backup and recovery behavior for ConfigFile databases.
6. Headless validation suitable for professional-team CI.

Later slices add canonical data transformations, multi-table orchestration,
and migration of older `user://` saves. Fresh databases and saves start at the
current schema; existing durable data applies only pending migrations. Managed
content sources migrate during authoring, while disposable effective-content
caches are rebuilt rather than migrated.

Applied migration files are immutable. Editing an applied file must produce a
checksum or schema-drift diagnostic instead of silently changing history.
Downgrades are optional and supported only when a migration is genuinely
lossless.

## 3. Release and compatibility QA

Track these version dimensions independently:

- GDSQL plugin release.
- Registry and persisted storage format.
- Database schema migration head.
- Managed package and cache format.
- Generated-model template contract.
- Godot-AI MCP surface.

Release readiness requires:

- Recovery tests for interrupted catalog, migration, and checkpoint writes.
- Paging, reference-materialization, and managed-cache benchmarks using large
  datasets and heavy project assets.
- Verification across supported Godot versions and exported builds.
- Clear compatibility and support matrices.
- Stable diagnostics for missing files, unsupported formats, schema drift, and
  incompatible generated models.

## 4. Editor and integration completion

- Verify Godot-AI tool registration across plugin load order, reload, disable,
  teardown, and project changes. Query execution and mutations remain deferred
  until the read-only contract is stable.
- Replace the 500-row foreign-key/content-reference popup boundary with
  debounced canonical search and paginated results.
- Keep editor actions, table navigation, and schema operations exposed through
  the shared action hub and Godot's command palette.

## 5. Updates

The first update feature is an opt-in checker, not a self-overwriting updater.
It should compare one canonical plugin version and supported Godot range, show
release notes and migration requirements, and direct the user to the official
release or Asset Library package.

Assisted installation remains blocked until compatibility and migration
policies are versioned. A later updater must stage and verify an archive,
replace only `res://addons/gdsql`, preserve project-owned data and models,
require a safe reload or restart boundary, and restore the previous plugin when
activation fails.

## Backlog — not active delivery

- SQL text compiler and editor.
- Advanced or saved query graphs.
- Model-backed dynamic scene previews.
- Generated-model nullability ergonomics.
- JSON, CSV, and portable database interchange.
- Player-to-player data exchange; `docs/architecture/network.md` remains its
  design log.
- Editor localization.
- Configurable shortcuts in a dedicated Godot editor-settings section.
- Automatic background updates.

## Documentation policy

The public documentation now covers installation, setup profiles, first-project
workflow, table and schema authoring, Resource storage, managed content,
runtime/model relationships, typed APIs, troubleshooting, Godot-AI integration,
architecture, and project philosophy.

New documentation should accompany an implemented or approved contract. The
next required documents are migration/recovery guidance and a release
compatibility matrix; do not add end-user updater instructions before that
feature exists.

## Definition of plug and play

A new user should be able to install GDSQL and, without reading source code:

1. Create and edit authored content in a conventional table.
2. Create or select a save database in a safe writable location.
3. Generate a model binding while understanding that the table is authoritative.
4. Bootstrap runtime roles, query content and save models, mutate save state,
   and checkpoint it through one documented path.
5. Diagnose setup, query, storage, reference, and compatibility failures from
   structured messages.

## Guardrails

- Do not fork execution logic between table, graph, SQL, model, or agent
  frontends.
- Do not make models schema authorities or migration sources.
- Do not hide content/save separation behind cross-database behavior.
- Do not expose ConfigFile paths or sections above storage infrastructure.
- Do not promise transparent lazy loading where concrete Godot Resource types
  require explicit materialization.
- Keep the roadmap, architecture glossary, and implementation state aligned.

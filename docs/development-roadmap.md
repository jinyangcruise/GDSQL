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
| High | Versioned database migrations and compatibility policy | Architecture decision and implementation required |
| High | Bounded Resource materialization and runtime loading policies | Current eager decode behavior must be replaced |
| High | Release, recovery, performance, and supported-version QA | Required before a stable release |
| Medium | Godot-AI lifecycle verification | Tools work; reload, disable, and teardown need live-editor verification |
| Medium | Large reference-picker search and paging | Current authoring picker is intentionally bounded |
| Medium | Opt-in release update checker | Blocked by version and compatibility contracts |

## 1. Versioned migrations

Models remain bindings, not migrations. A migration is project-owned,
version-controlled history describing how an older catalog and its data reach
the current catalog.

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

## 2. Resource materialization and memory policy

Referenced Resource columns persist compact UID/path locators, but persistence
size and runtime memory behavior are separate concerns.

Current ConfigFile decoding resolves a locator with `ResourceLoader.load()`.
Opening a ConfigFile registration does not by itself read every row, but a
table scan currently decodes every stored column before filtering, projection,
or `LIMIT`. Consequently, a query for inexpensive NPC fields may synchronously
load referenced meshes, audio, textures, or scenes that the result does not
use. Managed-content rebuilds and in-memory hydration can also materialize full
tables.

The target contract is:

1. Storage reads preserve referenced-asset locators until a query or
   materializer explicitly requires the Resource value.
2. Projection and index lookup avoid decoding unrequested columns.
3. Resource materialization supports synchronous and threaded requests without
   placing Godot loading details in `QuerySpec`.
4. Runtime content selects an explicit `LOAD_ALL`, `LAZY_TABLES`, `PAGED`, or
   `MANUAL` policy, as defined in `docs/architecture/databases.md`.
5. Manual and eviction-capable policies expose safe release boundaries for
   clean content. Dirty save data must checkpoint before eviction.
6. Missing or type-mismatched assets return table, row, column, and locator
   diagnostics rather than only becoming `null`.

True deferred Resource fields require an explicit handle or materialization
contract; a transparent proxy cannot satisfy arbitrary concrete Godot types
such as `Mesh` or `AudioStream`. The design must preserve typed model behavior
without pretending a locator is already a loaded Resource.

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

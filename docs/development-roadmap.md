# GDSQL Development Roadmap

## Product direction

GDSQL should be **table-first and graph-capable**.

Opening a table should show a familiar data workbench: a compact query header,
the result grid, paging, and row actions. The query graph remains an advanced
document for joins, calculated results, reusable visual queries, and users who
benefit from spatial composition. It is not the default table browser.

This is an editor change, not a runtime rewrite. Both surfaces must continue to
produce `GDSQLQuerySpec` and execute through `GDSQLDatabase`.

The catalog remains the authority for tables. A model binds typed code and
behavior to a table; creating or changing a model must not create or alter that
table implicitly.

## Supported setup profiles

GDSQL has two composition profiles, not two query APIs:

| Profile | Content role | Intended use |
|---|---|---|
| Direct content | Project-authored database under `res://` | Small and medium projects that need definitions, save models, and minimal setup. |
| Managed content | Derived `effective_content` database built from base content and optional packages | Large, customizable, or moddable games that need deterministic overlays, provenance, and cache orchestration. |

Both profiles use the same tables, models, relationships, `QuerySpec` pipeline,
and save-role behavior. A project can move from direct to managed content
without changing normal `GDSQLContentModel` queries. The editor must expose
only implemented profile actions; planned managed-content controls remain
status information until their orchestration exists.

## Current leverage and gaps

- Query execution, typed expressions, joins, grouping, ordering, mutations,
  indexes, transactions, model materialization, database roles, and persistence
  contracts already exist behind the canonical API.
- The graph result node and table document share the typed result grid for
  schema-aware editing, dirty-state protection, and Resource handling.
- The reusable WHERE editor already creates canonical expressions.
- Table selection opens the standalone table document; query graphs remain the
  advanced visual-query surface.
- Database-role and model APIs plus the optional runtime/autoload scene are
  implemented. Managed content now builds deterministic snapshots, reuses
  fingerprinted disposable caches, and activates them without exposing partial
  runtime state. Save-owned package expectations now produce typed compatibility
  reports; recording integration and managed setup UI remain.
- SQL lexer/parser/compiler contracts are scaffolded, so the editor must not
  present SQL text as a complete query frontend yet.

## Remaining delivery workstreams

After the current experimental table, creation, bootstrap, and model-assistant
slices, five substantive workstreams remain. They are grouped by outcome;
individual workstreams may require several small changes.

| Outcome | Count | Remaining workstreams |
|---|---:|---|
| Reliable direct-content setup | 0 | Complete for the current direct profile. |
| Managed-content full kit | 1 | Mod-aware save compatibility and setup UI. |
| Advanced tooling and release | 4 | Advanced graph operations and saved graphs; completed SQL compiler/editor; shared batch tooling; migration, performance, and release QA. |

## Delivery order

### 1. Make table browsing the default

Experimental status: table selection opens the standalone table document, runs
the initial SELECT automatically, and pages with canonical `LIMIT` and
`OFFSET`. It now reuses the graph result's compact native grid and submits
multi-row updates and selected-row deletes atomically. The first query-header
slice reuses the typed WHERE editor, applies filters explicitly, and derives
filtered page totals through a canonical `COUNT` query. Projection and ordering
controls are active in the native result header: the leading row-number header
opens visible-column selection, while content headers cycle sort direction.
Hidden primary keys remain in the query result for safe row mutations without
being displayed.

1. Continue separating graph orchestration from the shared typed result grid.
   Keep graph ports, graph sizing, and node chrome in the graph adapter.
2. Keep standalone table actions outside the grid so row height and column
   width do not change when editing or selecting a batch.
3. Open the table document when a table is selected. Expose query graphs through
   an explicit `New Query Graph` action.
4. Add a compact query header above the grid:
   - typed WHERE conditions using the existing expression editor;
   - projection/visible-column selection;
   - ORDER BY and direction;
   - page size, previous/next navigation, and refresh;
   - a clear summary of the active query.
5. Page through canonical `LIMIT`/`OFFSET` queries rather than loading a complete
   large table solely to paginate it in Controls. Preserve edits across refresh
   only when the row identity and query result still permit it.
6. Keep advanced clauses progressive: common filtering stays visible, while
   grouping, aggregates, joins, and calculated projections open an advanced
   query surface.

This slice is complete when browsing, filtering, paging, inserting, updating,
and deleting a table requires no graph interaction, and the graph uses the same
result component without losing its current capabilities.

### 2. Turn the welcome page into setup status

Experimental status: the welcome document now uses the shared typed direct-setup
report to validate the selected content and save roles, content catalog, first
table and row, model bindings, and runtime autoload. It reports one concrete next
action and can install the supported runtime adapter. Runtime bootstrap reuses
the same profile checks as non-fatal structured warnings. Its scene contains
representative checklist content so it remains understandable in the Godot
scene editor.

The welcome document should show a short, actionable project checklist:

1. Create or open an authored content database under `res://data`.
2. Create a table and add a first row.
3. Configure runtime roles for content, save, and settings as needed.
4. Generate or copy a model binding for an existing table.
5. Open focused integration examples and API documentation.

It should detect completed steps from workbench metadata where possible. Empty
projects get one primary action; existing projects get recent databases and the
next incomplete setup action. Detailed tutorials belong in user guides, not in
architecture documents or long welcome-page prose.

### 3. Replace raw database creation with an intent-based wizard

Experimental status: creation now starts with Content, Save Slot, Shared
Settings, or Custom intent. The first three derive their recommended root,
implemented storage backend, and logical runtime role; storage details remain
available under an advanced toggle. Successful creation persists the selected
role binding, and opening an existing logical database remains non-destructive.

The first choice should be the database purpose:

| Purpose | Recommended root | Runtime policy |
|---|---|---|
| Authored content | `res://data` | Read-only in exported games |
| Save slot | `user://gdsql/saves/<slot>` | Mutable and checkpointed |
| Shared settings | `user://gdsql/settings` | Mutable, independent of slots |
| Custom | Explicit root | Explicit access and persistence choices |

Advanced storage selection stays available but should not be the first concept
shown to new users. Creation must explain whether it created new files or opened
an existing logical database at that root.

### 4. Provide one supported runtime bootstrap path

Experimental status: `GDSQLRuntimeFactory.bootstrap()` now loads the durable
registry created by the editor, opens registered databases, restores roles,
configures the default model context, and returns a `GDSQLRuntimeSession` with
role resolution and explicit checkpoints. In-memory save data is verified to
checkpoint back into its durable ConfigFile source. Save-slot selection now
validates the target, checkpoints the previous slot, and prevents model
instances loaded from one slot from mutating another. The optional scene-backed
`GDSQLRuntimeNode` now bootstraps that session, exposes common delegates,
schedules periodic dirty checkpoints, and flushes synchronously on application
pause or tree exit. It retains structured startup results and emits lifecycle
results without printing or imposing game-specific quit behavior.

The editor now has a scene-backed Save Slots document. It discovers standard
slot directories, identifies the active role binding, opens a slot, switches
the durable selection, and launches the existing creation wizard directly in
Save Slot mode. It presents unregister-and-keep-files separately from permanent
deletion. Permanent deletion requires confirmation, shows the exact database
path, and is rejected unless the data root is one direct child of the standard
save directory.

Runtime bootstrap and the welcome checklist now share a typed direct-setup
report. Missing roles, unsafe roots, unavailable backends, missing content, and
an absent runtime autoload produce actionable status without preventing custom
runtime compositions from booting.

Add a small runtime setup API or optional autoload that composes and exposes:

- the database registry;
- content, save, and settings role selection;
- the default model context;
- model registration;
- checkpoint policies and lifecycle hooks.

The initial supported path should cover one project content database, one active
save slot, and shared settings. Content overlays and mod caches remain a later
extension and must not block the basic experience.

The documented content/runtime reference pattern is:

```text
content.items.id = "iron_sword"
        ↑ stable identifier
save.inventory.item_id = "iron_sword"
```

These are separate database contexts. Game or model-layer code resolves the
content record from the stored identifier; GDSQL does not promise a cross-root
join or a transaction spanning content and save databases.

### 5. Make model binding understandable and assisted

Experimental status: every table document now exposes a scene-backed model
assistant. It previews a generated schema base and a user-owned subclass,
infers the registration's bound role, permits an explicit custom role and model
root, and never replaces the user script. Existing generated bases require
confirmation before regeneration. The assistant also inspects an existing user
model against the authoritative table, reports identity/property mismatches,
validates relationship declarations, and displays each related model's logical
role and table. The pure source builder and compatibility inspector have focused
tests. The runtime guide and executable example models now cover authored
content lookup, a save model resolving a stable content identifier through a
cross-role relationship, and fresh model queries after save-slot switching.
Focused integration tests exercise all three flows against separate databases.

Add a table action that previews a GDScript model skeleton. The user chooses
`GDSQLContentModel`, `GDSQLSaveModel`, `GDSQLSettingsModel`, or a custom role.
The preview should include typed properties, table name, primary key, and the
small static query/find forwarding methods required by GDScript.

Generated schema bindings and user behavior must live in separate scripts:

```text
res://models/generated/hero_model_generated.gd  # safe to regenerate
res://models/hero.gd                            # created once; user-owned
```

The generated base contains table-derived properties and instance metadata.
The user model extends that base and owns custom methods, relationships, and the
static forwarding methods that must reference the concrete user class. A
regeneration may replace only the generated base. It must never rewrite the
user model. The root `res://models/` location should be configurable in
`res://.gdsql/settings.cfg`, with `generated/` reserved for generated output.

Generation is one-way assistance:

```text
catalog table -> model script draft
model script -X-> catalog mutation
```

Before writing a script, show its destination and generated source. Never
overwrite a user script without explicit confirmation. Add read-only
compatibility diagnostics for missing properties, incompatible types, primary
key mismatches, and invalid relationships.

The first integration guide should contain three complete examples:

- authored content lookup;
- save data that stores and resolves a content identifier;
- changing save slots while model queries continue to use the `save` role.

### 6. Close visual/API capability gaps deliberately

Expose code features according to user intent rather than mirroring every
internal class:

| Capability | Visual treatment |
|---|---|
| Select, filter, order, projection, paging | Primary table workbench |
| Insert, update, delete | Table row actions |
| Joins, grouping, aggregates, calculated columns | Advanced query document / graph |
| Schema, defaults, indexes, generated values, Resource constraints | Database/table designer |
| Transactions | Atomic multi-row save/import and operation summaries |
| Model mapping and relationships | Model assistant and compatibility view |
| Registry roles and checkpoints | Runtime setup page |
| Planner, executor, storage sessions | Diagnostics only; no direct visual clone |
| SQL text | Enable only after the SQL compiler is implemented and tested |

After the table-first path is solid, resume graph work for joins, ordering,
grouping, calculated projections, saved graph assets, and explicit result-root
selection. Atomic batch editing should follow the shared table view so both
table and graph workflows can reuse it.

### 7. Build the effective-content and mod pipeline

Experimental status: package manifests now have typed base-game, DLC, and mod
metadata; semantic versions; required-package constraints; explicit priority
and before/after declarations; package-relative data and asset paths; structured
validation; and a ConfigFile reader behind a runtime store contract. Directory
discovery now supports direct and nested `content/` packages. Resolution selects
one mandatory base plus explicitly enabled DLC/mod packages, checks semantic
version constraints, and topologically orders dependency and before/after edges
with stable priority and package-ID tie-breaking. The overlay loader now reads a
selected logical database through an injected layer-reader contract, copies
compatible schemas, and deterministically applies stable-ID upserts and explicit
removals into an effective-content snapshot. Provenance and conflict reporting
now record every applied package operation, preserve removal histories,
resolve the winning package for effective rows, and report later-package
overrides without failing the deterministic build. Cache manifests and rebuilds
now fingerprint package order, versions, and directory content; reuse only an
exact compatible cache; and rebuild malformed or stale caches through a staged
ConfigFile directory replacement. The runtime composition root now opens that
candidate first and replaces the runtime-local `effective_content` registration
and `content` role together. Save compatibility now compares persisted package
expectations with the active manifest without imposing a load policy. Managed
setup UI and save-recording integration are next.

Runtime content should always be consumed through one derived
`effective_content` database bound to the `content` role. Base content and
enabled mod packages are immutable inputs; gameplay models do not query those
source registrations directly. The same build path applies when no mods are
enabled, so adding mod support does not change application query code.

The content loader should:

1. Read the base package and enabled packages in deterministic order.
2. Validate compatible schemas, package dependencies, stable identifiers, and
   asset references.
3. Apply typed additions, overrides, and explicit removals while recording row
   provenance and conflicts.
4. Produce one effective database, optionally persisted at
   `user://gdsql/cache/effective_content` before loading its active working set.
5. Fingerprint base and package versions, checksums, and load order so stale
   cache data is rebuilt rather than treated as authoritative.
6. Replace the `content` role binding atomically after a successful rebuild.

Persistent and memory-only cache policies may differ by project size and
platform, but both expose the same logical effective database. Save rows retain
stable content identifiers rather than copying definitions. Save metadata may
record its expected package set; missing mod-owned identifiers return structured
diagnostics and remain subject to an explicit game policy instead of being
silently deleted or rewritten.

This slice is complete when base-only and modded launches use the same content
model queries, deterministic rebuilds produce reproducible data, and disabling
a package cannot mutate the base sources or corrupt save rows.

## Backlog — not active delivery

- **GDSQL-aware MCP integration:** investigate a focused MCP surface for schema
  inspection, safe query drafting, setup diagnostics, and editor actions. It may
  integrate with `godot-ai`, but must remain optional and must not bypass GDSQL
  validation or mutation safeguards.
- **Portable database interchange:** export and import tables or query results
  as JSON, CSV, and compatible GDSQL data. The interchange contract must remain
  independent of ConfigFile and the future paged-binary backend, with schema
  validation, previews, and atomic imports.
- **Player-to-player data exchange:** use the existing
  `docs/architecture/network.md` as the design log. The first future spike
  should distinguish transferable data snapshots from synchronized gameplay
  state and define authority, authentication, size limits, versioning,
  validation, and conflict policy before selecting a transport.

## Definition of plug and play

A new user should be able to install the plugin and, without reading source
code:

1. Create authored content and edit it in a conventional table.
2. Create or select a save database with a safe writable location.
3. Generate a model draft for an existing table and understand that the table
   remains authoritative.
4. Run the game, resolve content and save roles, query a model, mutate save
   state, and checkpoint it through one documented bootstrap path.
5. Diagnose setup and query failures from structured messages in the editor.

## Guardrails

- Do not fork execution logic for table, graph, SQL, or model frontends.
- Do not duplicate the typed result editor; extract and reuse it.
- Do not make model scripts schema authorities.
- Do not hide content/save separation behind cross-database behavior.
- Do not remove the graph while it contains reusable working behavior.
- Keep roadmap progress synchronized with tests and the glossary when stable
  concepts change implementation state.

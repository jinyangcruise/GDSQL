# GDSQL Development Roadmap

## Product direction

GDSQL should be **table-first and graph-capable**.

Opening a table should show a familiar data workbench: a compact query header,
the result grid, paging, and row actions. The query graph remains an advanced
document for joins, calculated results, reusable visual queries, and users who
benefit from spatial composition. It is not the default table browser. Further
graph authoring is suspended until the primary table, setup, and release flows
are complete and the graph has a discoverable entry point.

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
without changing normal `GDSQLContentModel` queries, but moving physical data,
package metadata, resource paths, and save expectations is an explicit migration
rather than a profile toggle.

## Current leverage and gaps

- Query execution, typed expressions, joins, grouping, ordering, mutations,
  indexes, transactions, model materialization, database roles, and persistence
  contracts already exist behind the canonical API.
- The graph result node and table document share the typed result grid for
  schema-aware editing, dirty-state protection, and Resource handling.
- The reusable WHERE editor already creates canonical expressions.
- Table selection opens the standalone table document. The existing graph code
  is retained, but further graph work is not active delivery.
- Database-role and model APIs plus the optional runtime/autoload scene are
  implemented. Managed content now builds deterministic snapshots, reuses
  fingerprinted disposable caches, and activates them without exposing partial
  runtime state. The runtime node reads the selected setup profile and activates
  configured managed content automatically. Save-owned package expectations now
  produce typed compatibility reports. A managed setup document validates package
  inputs, builds the cache, reports active-save compatibility, and confirms
  expectation recording.
- SQL lexer/parser/compiler contracts remain scaffolded, but SQL text is not an
  active product priority while typed query interactions have larger gaps.

## Remaining delivery workstreams

After the current experimental table, creation, bootstrap, model-assistant, and
row-history slices, four substantive workstreams remain. They are grouped by outcome;
individual workstreams may require several small changes.

| Outcome | Count | Remaining workstreams |
|---|---:|---|
| Reliable direct-content setup | 0 | Complete for the current direct profile. |
| Managed-content full kit | 0 | Complete for the current managed profile. |
| Data integrity | 0 | Foreign-key enforcement and role-reference inference complete for the current contract. |
| Editor interaction | 2 | Multi-table navigation/schema actions; nested typed WHERE groups. |
| Agent integration | 1 | Live-editor verification of the implemented read-only Godot-AI MCP surface. |
| Release | 1 | Migration, performance, compatibility, and release QA. |

## Delivery order

### 1. Make table browsing the default

Experimental status: table selection opens the standalone table document, runs
the initial SELECT automatically, and pages with canonical `LIMIT` and
`OFFSET`. It now reuses the graph result's compact native grid and submits
multi-row updates and selected-row deletes through a shared validated canonical
batch plan and one transaction. Empty, duplicate, unknown-column, and read-only
mutations are rejected before execution. The first query-header
slice reuses the typed WHERE editor, applies filters explicitly, and derives
filtered page totals through a canonical `COUNT` query. Projection and ordering
controls are active in the native result header: the leading row-number header
opens visible-column selection, while content headers cycle sort direction.
Hidden primary keys remain in the query result for safe row mutations without
being displayed. The typed result grid now lives in a graph-independent,
scene-backed editor component; graph chrome, table paging, and mutation actions
remain with their owning frontends. Data columns use stable equal expansion
with fixed minimum widths, so table and insert views fill their host consistently
and overflow horizontally only when all columns have reached their minimum.
Selected rows can be duplicated through one atomic insert batch when the table
has a generated identity and copies only non-unique scalar or referenced
Resource values. Manual identities, copied unique constraints, or owned
Resource values instead populate one editable insert draft from the first
selected row. Owned Resource values are deep-cloned; referenced values preserve
their asset identity. Constrained Resource columns expose only validated
Inspector-visible scalar leaves to typed WHERE choices; compound values such as
`Vector3` expose their scalar components instead of the container.
Visual Resource thumbnails are applied through deferred editor-thread updates;
non-visual Resources keep their editor type icon and do not invoke preview
plugins that cannot safely represent them.
Schema reopening reads stored Resource type metadata without constructing empty
prototypes, and imported MP3/Ogg Vorbis picker entries are load-only.
Tab advances through editable cells and Enter commits an inline edit before
moving down the same column.

1. Keep the shared typed result grid independent from graph orchestration.
2. Keep standalone table actions outside the grid so row height and column
   width do not change when editing or selecting a batch.
3. Open the table document when a table is selected.
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
and deleting a table requires no graph interaction.

### 2. Turn the welcome page into setup status

Experimental status: an empty project now chooses Direct Content or Managed
Content from two explicit cards and confirms that profile changes do not migrate
data. The selection is persisted in project settings. The welcome page then
shows only the chosen profile's actions, typed checklist, and next step. Direct
checks cover the content/save roles, rows, models, and runtime; managed checks
cover the base package, source tables, effective cache, save, models, and runtime.

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

Experimental status: creation now starts with Direct Content, Managed Base
Content, Save Slot, Shared Settings, or Custom intent. Managed creation
scaffolds a base manifest plus data/assets roots and leaves the immutable source
unbound; the generated effective database owns the runtime content role. Other
intents derive their recommended root, storage backend, and logical role. The
database document separates recoverable unregistering from confirmed permanent
destruction of the selected database's catalog, schemas, tables, and rows.

The first choice should be the database purpose:

| Purpose | Recommended root | Runtime policy |
|---|---|---|
| Authored content | `res://data` | Read-only in exported games |
| Managed base content | `res://content/base/data` | Immutable source for generated effective content |
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

The workbench now treats an in-memory backend as a runtime policy and opens its
durable ConfigFile source for editor authoring. Successful table edits are
therefore visible when a separately launched runtime hydrates the registration;
the stored backend selection remains in-memory and runtime checkpoint behavior
is unchanged. This removes the persistence blocker for the cross-role
content-reference cell selector.

Runtime bootstrap and the welcome checklist now share a typed direct-setup
report. Missing roles, unsafe roots, unavailable backends, missing content, and
an absent runtime autoload produce actionable status without preventing custom
runtime compositions from booting.

When the selected setup profile is Managed Content, `GDSQLRuntimeNode` loads
the typed package configuration shared with the editor, resolves the selected
package order, and builds or reuses `effective_content`. It exposes the runtime
only after that database owns the `content` role; failed activation clears the
partial model context and remains a structured startup failure. It also checks
the active save against that package set before `runtime_started`, retains the
typed report for late consumers, and refreshes it after save-slot selection.
Compatibility never changes whether startup succeeds; the game owns that load
policy.

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
model against the authoritative table and reports generated-base, role, and
property mismatches through static script metadata. It never instantiates the
user model or executes `relationships()` in the editor; the runtime registry
validates executable metadata and explicit relationships. The assistant displays
catalog-inferred relationships separately. New bindings require an explicit
singular class name, remember it per registration/database/table, and share the
project-wide model root. The pure source builder and static
compatibility inspector have focused tests. The runtime guide and executable
example models now cover authored
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
overwrite a user script without explicit confirmation. Keep editor compatibility
inspection static: check the generated base, role inheritance, and typed
properties without executing project-owned model code.

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

Atomic batch editing should follow the shared table view. The existing graph
may reuse it later without making graph work a prerequisite.

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
expectations with the active manifest without imposing a load policy. The
managed setup document persists package inputs, builds the cache, and records
save expectations only after confirmation. Managed runtime startup now consumes
that configuration automatically and exposes the active save's report through
the runtime node for explicit game policy.

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

### 8. Improve multi-table navigation and schema actions

Experimental status: the database document filters existing table folds by
table or column name without hiding unsaved table drafts. Registered databases
and tables are also exposed through Godot's existing command palette
(`Ctrl+Shift+P` by default), so GDSQL does not claim a competing editor
shortcut. Existing table folds provide direct data and model actions plus a
confirmed Reset Data macro. Reset Data stages transactional truncation through
the shared storage contract, respects final-state foreign-key restrictions,
and resets generated-key metadata without ConfigFile access from Controls.
Column rows expose an extensible right-click action menu without adding a
per-row action cluster. Removal previews stored-value loss, automatically
stages dependent local index and foreign-key removal, discards dependent
unsaved constraints, blocks on named cross-table foreign keys, and remains
restorable from the same menu until Save Changes.

1. Search and filter tables within a database without loading their rows.
2. Search table and column names across registered databases, with keyboard
   navigation and direct open actions. Keep the command-palette inventory in
   sync after discovery and schema changes.
3. Give each database-document table direct actions for opening its data and
   creating or updating its model binding.
4. Let the model-binding assistant open the user-owned model directly in the
   Script editor when that file exists.
5. Keep table reset as an explicit confirmed administrative operation,
   distinct from ordinary row deletion and independent of storage format.
6. Keep column deletion in the row context menu and reversible before save,
   with one explicit confirmation and visible dependency handling.

### 9. Add bounded row mutation history

Experimental status: table documents expose per-table Undo/Redo through the
action hub. One entry represents a successfully committed non-Resource value
update batch;
inverse updates use the same canonical transactional batch path, and stack state
moves only after success. History is capped, exists only in editor memory, and is
never serialized or restored after Godot restarts. Inserts, deletes, graph-side
mutations, and Resource edits clear the table history until generated identities,
timestamps, and object snapshots have a safe restoration policy. Undo restores
editable values while `updated_at` records the undo operation time.

### 10. Add foreign keys and role-aware reference inference

Experimental status: tables can carry typed named, single-column,
same-database foreign-key definitions with `RESTRICT` policy metadata.
ConfigFile schemas round-trip them; catalog creation and alteration restrict
keys to exact `int`, `String`, or `StringName` pairs; referenced tables and
unique columns are resolved; existing rows are rejected when orphaned; and
managed-content schema comparison, copying, and cache persistence preserve the
constraints. ConfigFile and in-memory runtimes validate the final effective
transaction state before commit, so inserts and updates cannot create orphans,
referenced target updates/deletes use `RESTRICT`, and related changes may be
staged in either order atomically. Catalog administration blocks referenced
table/column renames and drops plus removal of the target's last uniqueness
contract; safe self-referencing renames update their constraint metadata. The
database table designer now creates and removes these constraints through typed
catalog alterations. Searchable selectors expose only supported local columns
and exact-type unique targets in other tables, and foreign-key columns carry the
dedicated key indicator. Existing self-references remain readable and removable,
but the table designer does not offer the source table as a new target. New
constraint names follow the deterministic
`fk_<source>_<local>_<target>_<target_column>` convention and stay synchronized
with their selected inputs. Data and insert grids expose the foreign-key action
for columns with one unambiguous constraint, load an ordered canonical target
query on demand, and present the first 500 rows through a searchable popup with
context fields before applying the selected key through the normal batch draft.
Large reference sets remain bounded: replace the loaded-page popup with debounced
server-side search and paginated results before raising or removing that limit.

The model registry now infers default same-database navigation when both model
types are registered. The foreign-key owner receives `belongs_to`; its inverse
is `has_one` when the local foreign key is unique and `has_many` otherwise.
Declared user relationships take precedence by name, no model script is
rewritten, and the model assistant previews the inferred edges directly from
the catalog. Explicit `many_to_many()` relationships now resolve source models
through a registered junction model, validate every participating key, preserve
junction associations while batching eager loads, and return typed related-model arrays.
Cross-role references remain logical contracts resolved through database roles.
For save models, the Model Assistant now matches supported local identifiers to
content-model primary keys and copies the corresponding `references_one()` entry;
it does not create a catalog constraint across databases.

Save-table cells reuse the bounded reference selector for Model
Assistant-registered `references_one()` navigation. The assistant stores typed
editor metadata while copying the runtime declaration; the selector reads the
target content registration without synthesizing a cross-database catalog
foreign key. Registered bindings are listed with copy and remove actions so an
accidental picker mapping is reversible without touching user model code.
Server-side search and paging beyond the bounded first result set remain future
work for this authoring picker.

| Relationship delivery step | State |
|---|---|
| Same-role `belongs_to`, `has_one`, and `has_many` catalog inference | Implemented |
| Empty relationship scaffold, compatibility guidance, and copyable clean model scaffold | Implemented |
| Same-role registration and eager-loading micro guide | Implemented |
| Explicit many-to-many/through contract | Implemented |
| Assisted cross-role `save` → `content` declarations | Implemented |

### 11. Improve nested typed WHERE interactions

The first bounded nesting slice is implemented: Resource columns expand to
Inspector-visible scalar leaves, including supported Vector and Color
components. Validation rejects unknown paths and intermediate compound values,
and execution remains a canonical typed query rather than editor-side filtering.

The shared WHERE editor now provides explicit scene-backed nested groups with
group-level `NOT`, bounded nesting depth, visible precedence boundaries,
reordering, and compact collapse summaries. Conditions remain left-associative
inside their owning group, and recursive composition produces only canonical
logical-expression trees without introducing SQL parsing into the control.

### 12. Define a GDSQL-aware MCP surface

Experimental status: the architecture contract and first implementation slice
are complete. GDSQL delegates transport and protocol negotiation to the optional
Godot-AI bridge, while its versioned inspection service stays project-scoped and
independent from editor Controls and ConfigFile. Capabilities, setup inspection,
and bounded schema inspection are promoted read-only tools, with deterministic
JSON contract coverage and optional-plugin lifecycle handling. Godot-AI has
accepted the tools in the live editor; reload, disable, and teardown behavior
remain to be verified manually. The next read-only tool should inspect model
bindings and relationships without loading row values. Query drafting and
two-step confirmed editor actions follow only after the inspection contract is
stable; a separate GDSQL resource namespace is not active work because Godot-AI
already provides custom-tool discovery.

### 13. Migration, performance, and release QA

Version persisted formats, provide dry-run migrations and recovery guidance,
benchmark paging and managed-content caches with large datasets, and verify
editor/runtime behavior across supported Godot versions and exported builds.
Before release, add diagnostic-bearing storage read results so a missing or
type-mismatched referenced Resource is reported with its table, row, column,
and locator instead of being exposed only as a null value.

## Backlog — not active delivery

- **SQL compiler and editor:** complete the supported SQL frontend only when SQL
  text unlocks a concrete workflow beyond the typed table and expression tools.
- **Advanced query graph:** preserve the current implementation, but do not add
  operations or saved graphs until it has a discoverable entry point and the
  primary table, setup, and release workflows are complete.
- **Dynamic editor content preview:** defer model-backed scene previews. Use
  normal authored placeholders in editor scenes and load content models through
  the runtime. Reconsider only if a core workflow cannot be served by placeholders.
- **Generated model nullability and type ergonomics:** keep exact GDScript
  property types for non-null columns and make nullable scalar fallbacks
  explicit in the model assistant. Because GDScript has no nullable scalar or
  union syntax, do not silently generate `String`, `float`, or other value types
  when the table permits `NULL`; investigate a typed optional representation or
  a schema action that lets users intentionally make required columns non-null.
- **Portable database interchange:** export and import tables or query results
  as JSON, CSV, and compatible GDSQL data. The interchange contract must remain
  independent of ConfigFile and the future paged-binary backend, with schema
  validation, previews, and atomic imports.
- **Player-to-player data exchange:** use the existing
  `docs/architecture/network.md` as the design log. The first future spike
  should distinguish transferable data snapshots from synchronized gameplay
  state and define authority, authentication, size limits, versioning,
  validation, and conflict policy before selecting a transport.
- **Editor localization:** extract user-facing strings so future translations
  can be added without changing control scripts or scenes.
- **Configurable shortcuts:** register GDSQL actions and shortcuts in a dedicated
  plugin section of Godot's editor settings, including conflict-safe defaults.
- **Automatic updater:** provide opt-in release checks and safe updates only
  after plugin, registry, database, package, and generated-model compatibility
  policies are versioned.

## Documentation transition

The rewrite sources of truth are `docs/architecture/` and this roadmap. The
remaining VitePress documentation is legacy and scheduled for replacement; the
new end-user documentation will be developed separately.

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

## Completed summary

- Table-first browsing, filtering, ordering, paging, and atomic row editing.
- Guided Direct Content and Managed Content setup plus safe database deletion.
- Runtime bootstrap, roles, save-slot switching, checkpoints, and diagnostics.
- Generated/user-owned model assistance and cross-role content references.
- Deterministic managed-content overlays, caching, provenance, and save checks.
- Explicit owned/reference Resource-column semantics with compact ConfigFile
  asset locators and native owned-Resource serialization.
- Command-palette database/table navigation, direct table/model actions, and
  transactional table reset with generated-key restart.
- Context-menu column removal with local constraint cleanup, cross-table
  dependency warnings, and pre-save restoration.
- Nested typed WHERE groups with group-level inversion, visible precedence, and
  compact summaries across table and graph consumers.
- Read-only Godot-AI MCP integration with promoted capabilities, setup, and
  bounded schema tools, project-scoped inspection contracts, and explicit
  future mutation boundaries.

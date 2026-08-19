# GDSQL Editor Architecture

## Purpose

The GDSQL editor is a Godot-only frontend over the existing database runtime.
It provides database discovery, catalog and row manipulation, visual query
authoring, and structured operation feedback without introducing a second
database execution path.

This document defines editor boundaries and ownership. The legacy capability
inventory is maintained separately in
[`editor-ui-migration-blueprint.md`](editor-ui-migration-blueprint.md), while
the runtime pipeline remains defined by [`core.md`](core.md).

## Architectural position

The editor depends on public runtime and catalog contracts. Runtime code has no
dependency on editor classes, controls, documents, or Godot editor state.

```text
Godot editor surfaces
    ↓
Editor actions and coordinators
    ↓
Workbench / WorkbenchSession / graph compiler
    ↓
Public runtime, catalog administration, and QuerySpec
    ↓
Runtime architecture
```

Editor controls present state and collect intent. Database discovery, catalog
changes, query compilation, execution, transactions, and persistence remain
owned by their existing services.

## Editor surfaces

The editor is divided across native Godot regions according to lifecycle and
space requirements.

| Surface | Responsibility |
|---|---|
| Database dock | Persistent navigation through registrations, schemas, tables, and columns |
| Central workspace | SQL graph documents and focused database task pages |
| Activity bottom panel | Operation status, diagnostics, duration, and history |
| Editor-wide action entry | Discovery of actions shared across surfaces and active contexts |

The central workspace is not a general database ownership graph. `GraphEdit`
and `GraphNode` represent query composition only when used by the SQL graph
frontend.

## Composition and action ownership

`EditorIntegration` is the editor composition boundary. It owns the lifecycle
of the registered surfaces and connects them to the editor coordinators.
The `EditorPlugin` places the central workspace inside a clipped main-screen
host and registers peripheral surfaces as native `EditorDock` instances.
Each dock has a stable layout key. Plugin activation replaces a stale dock with
the same key before registering the current instance, while deactivation
removes the owned instance. This keeps project opening and plugin refresh
idempotent.
`EditorController` registers shared actions and coordinates workbench
operations with those surfaces.

Actions have stable identities independent from where they appear.
`EditorActionDefinition` contains presentation metadata such as translation
keys, icon, shortcut, grouping, and entry kind. It contains no database or
feature behavior.

`EditorActionRegistrar` owns the stable metadata for shared actions. The
editor coordinator supplies their handlers, keeping action presentation
registration separate from operation coordination.

`EditorActionHub` provides editor-wide action discovery and routes invocation to
the active `ContextActionHub`. Each context hub belongs to a feature surface or
open document and owns:

- The actions available in that context.
- Visibility, enabled, and selected state.
- Validation required before invocation.
- Delegation to the appropriate coordinator or runtime contract.
- The structured result of the action.

Menus, toolbars, context menus, shortcuts, and future command search may
reference the same action definition. They do not duplicate its behavior.

## Coordination state

`Workbench` is the collection-level coordinator. It owns the durable database
registration snapshot and lightweight inspections used by the database dock.
Discovery is restricted to explicit roots and does not load row values.

`WorkbenchSession` represents one opened registration. It owns the active
catalog snapshot, selected table, bounded row page, and pending
`CatalogChangePlan`. It does not depend on Godot controls.

The distinction is:

```text
Workbench
    All known registrations and lightweight metadata.

WorkbenchSession
    One opened database and its current editing state.
```

The database dock reads collection state from `Workbench`. A central task page
binds to a `WorkbenchSession` when it requires an opened database. Opening a
second database may create another session or replace the active one according
to the workspace document policy; controls do not store authoritative database
state themselves.

Project-root discovery runs when the editor workbench loads. The database dock
therefore exposes refresh as its persistent toolbar operation; database
creation and other structural operations are opened as workspace tasks.
Discovery reconciles registrations by data root and logical database identity.
Registrations whose databases no longer exist under the refreshed project root
are removed from the persisted editor snapshot. Registrations that still exist
retain their selected runtime storage backend.

## Database dock

`DatabaseDock` presents the hierarchy:

```text
Registration / schema
└── Tables
    └── Table
        └── Column
```

It delegates registration loading, explicit-root discovery, refresh, and
selection to `Workbench`. Selecting a database opens or focuses its session.
Selecting a table may open a task page backed by that session. Drag payloads
identify database resources through typed metadata and may be consumed by the
query graph.

The dock displays lightweight inspection state. Row pages are loaded only by a
table task or query result that requests them.

Database and table items expose context actions. Removing a database unregisters
it from the durable catalog and the editor registry while explicitly identifying
the database folder that remains unchanged. Creating the same logical database
under that root registers and loads the existing schemas, tables, and rows.
Table deletion remains a confirmed catalog operation because it removes its
schema and stored rows.

## Central workspace

`WorkspaceHost` owns active editor documents and focused database tasks. Its
documents may include:

- SQL graph documents.
- Table inspection and row editing.
- Database and table definition tasks.
- Import and export tasks.
- Settings or informational pages.

The workspace uses an editor-style category menu followed by a document tab
bar. The stable categories are `File`, `Edit`, `Query`, `Database`, and `Help`.
Tabs identify the welcome page, database creation, opened database documents,
and future query-graph documents. Menu and tab controls delegate through the
action hub and workbench session rather than owning operations.

Workspace documents and their reusable controls are separate scenes. The host
owns tab identity, activation, and closure; each document owns only its local
presentation and draft state. Popup menu entries are declared in scenes so
tool-script and addon-refresh lifecycles do not append duplicate persistent
items.

Reusable `EditorActionButton` controls resolve presentation and availability
through the active action-hub context. Database documents contribute contextual
save and refresh actions, while global create-database and create-table actions
reuse the same button contract. Refresh explicitly discards local drafts after
confirmation and reloads the durable catalog.

File-backed documents track identity and dirty state independently from
database transaction state. Saving an editor document persists its authoring
state. Committing a database transaction validates and makes database
mutations visible. These operations are separate.

Workspace documents contribute their actions through a `ContextActionHub`.
The active document determines which contextual actions are exposed by the
editor hub.

## SQL graph frontend

`QueryGraphEditor` is the presentation frontend for `QueryGraph`. Graph nodes
and connections describe canonical query meaning. The editor delegates
structural validation to the graph model and compilation to
`GraphQueryCompiler`.

```text
Graph controls
    ↓ edit
QueryGraph
    ↓ compile(graph)
QuerySpec
    ↓ execute(query)
Database runtime
```

Generated queries use the same canonical expressions, validation, planning,
execution, and result materialization as the fluent API. Query graph documents
may be stored under `res://.gdsql/` because they are project editor assets, not
runtime table data.

The query-graph operations, result mutation capability rules, selectable
column work, `GDSQLExpr` WHERE controls, and next model-source slice are recorded in
[`query-graph-roadmap.md`](query-graph-roadmap.md).

`WhereExpressionEditor` is a reusable graph presentation component shared by
operations that accept a predicate. It receives typed catalog columns and
returns a canonical `GDSQLQueryExpression` plus structured diagnostics. SELECT,
UPDATE, and DELETE may embed it; INSERT does not, because insertion has no row
selection predicate. The component does not bind or evaluate expressions.

Every operation and result view derives from `QueryGraphNode`. The base extends
Godot's native `GraphNode` titlebar through `get_titlebar_hbox()`, provides a
close button, one-shot viewport-fit button, and an operation-specific actions
host, and emits presentation intent. `QueryGraphEditor` resets the graph to
100% zoom and resizes the requested node to the current viewport once; later
zooming, scrolling, or viewport changes do not keep resizing the node. Future
raw-table or registered-model selectors may use the actions host without adding
model resolution to the base presentation class.

`QueryTableResultNode` uses Godot's native multi-column `Tree` for aligned
titles, scrollable columns, row selection, and bounded page rendering. Resource
cells request the same editor preview service used by Inspector-facing controls
and retain their editor type icon when no preview can be generated. Its
header Safe Mode keeps typed editing in one focused `EditorVariantValueField`
row below the table. `GDSQLQueryTableResultTable` owns display rendering,
thumbnail caching, inline validation, and pending cell state. With Safe Mode
disabled, mutable catalog cells use Tree's inline editor, are validated back
into their declared Variant type, and remain highlighted until their row
updates are saved as one UI batch or discarded.
Resource cells instead use Tree's custom button mode: activation opens the
assigned Resource in Godot's Inspector. Content fingerprints filter incidental
`Resource.changed` emissions, while Inspector property edits provide the dirty
signal for custom Resource scripts that do not call `emit_changed()`. Scripted
Resources display their global class name, with their script filename as the
anonymous-class fallback. Safe Mode remains the assignment surface for empty
or replacement Resource references and uses the same Inspector edit tracking.
In direct mode, clearing a nullable String cell produces `null`; clearing a
non-nullable String cell produces a validation error instead of an empty value.
Page navigation and edit-mode switching are blocked while either surface is
dirty, preventing silent loss of an unsaved draft. The reusable row owns typed
values and validation only; Save, Delete, and Discard controls belong to the
result node so result-level mutation and dirty tracking have one presentation
owner. Running the query again is rejected while the result is dirty, and
closing the query document requires explicit discard confirmation from the
workspace tab lifecycle.

Each executable operation owns at most one result node, keyed by the operation
node name. Executing another SELECT creates or refreshes that SELECT's result
without replacing existing results. Dirty state, row actions, removal, and
post-mutation refreshes remain scoped to the originating operation/result pair;
document close checks every open result.

The direct-mode batch reuses the existing per-row mutation boundary; it is not
an atomic database transaction. Each successful row refreshes the result, and
updates that do not receive that success refresh remain pending and highlighted.

Nullable Variant fields always expose an explicit Null checkbox, including
editable compound values such as `Vector2`. Their value input remains
interactive while Null is selected. Typing a value or choosing a Resource
clears Null; checking Null again preserves an explicit null mutation. Focused
editable text fields enter `LineEdit` edit mode immediately, including inside a
GraphNode.

Standalone INSERT, UPDATE, and DELETE nodes reuse an inspection-backed source
selector and typed mutation-value editor. Their controls translate only to
typed graph nodes; `GraphQueryCompiler` produces the canonical mutation specs.
Unfiltered UPDATE and DELETE operations require a source-reset inline
confirmation before compilation. Successful mutation execution is coordinated
by the editor controller, which refreshes catalog and inspection surfaces and
presents affected-row statistics without putting runtime dependencies in graph
controls.

## Database and table tasks

Structure tasks use typed catalog definitions and
`CatalogAdministrationService`. Potentially destructive table alterations use
`CatalogChangePlan` for preview and confirmation before application.

Database creation creates a durable catalog when the logical database does not
already exist. If that database already exists under the selected root, the
editor loads and registers it instead. The editor may register the database
with ConfigFile runtime storage or with the in-memory runtime backend. An
in-memory registration continues to use the durable ConfigFile catalog and rows
as its hydration and checkpoint boundary. Planned backends are not offered as
selectable creation options. Successful catalog mutations request an editor
filesystem scan so folder and file changes become visible without restarting
the plugin.

One database document presents the logical database name, location, runtime
storage, and every table as a `FoldableContainer`. Its table folds manage
schema configuration through reusable column and index controls. Selecting a
table opens or focuses a separate data document.

New tables are editable drafts placed after existing table folds and before the
persistent `Add Table` action. Database rename and new-table definitions remain
local dirty state until the user requests save and confirms a concise change
summary. Invalid drafts keep Save unavailable and expose the first actionable
database, table, column, default, primary-key, or index validation message in
the document footer. The editor then delegates the typed database rename and
`TableDefinition` objects to catalog administration. Broader alterations
continue through previewed `CatalogChangePlan` instances.

Registration names are internal identities. User-facing titles and database
fields display `DatabaseRegistration.database_name`; location and storage
backend are displayed separately.

Each table fold presents its primary key, index definitions, and column
properties supported by `ColumnDefinition`. The column editor is composed from
a header scene, a reusable row scene, a typed draft model, and a small list
coordinator under `components/table/column_editor/`. A default row instance is
visible in the editor scene for 2D layout work and is overwritten with the first
column draft when data is configured; additional columns instantiate the same
row scene. Fixed cell widths and the Variant type options are scene-authored.
Each draft row has a drag grip in its Name cell. Dropping it before or after
another row saves the resulting names as one non-destructive schema-order
alteration. Result tables apply that configured order to returned catalog
columns; calculated or aliased outputs retain query order after them.

The header and body use separate synchronized `ScrollContainer` nodes. The
header stays above the rows, vertical scrolling cannot paint rows over it, and
the body's horizontal scrollbar exposes the complete fixed-width row. This
removes the overlay positioning and per-frame cell tracking previously required
by `TreeItem`, which cannot own scene children.
Resource cells use the native `EditorResourcePicker` presentation directly, so
texture thumbnails, audio previews, and other editor-provided Resource displays
are retained instead of being reduced to proxy text. Existing column types and
Resource constraints remain read-only because replacement is represented as
add, migrate values, and drop. Newly added rows expose both selectors.
The Resource constraint cell uses an unrestricted Resource prototype picker,
not a discovered class-name list, so native, global, and anonymous custom
Resource scripts are supported. Enabling a Resource default creates a deep
duplicate of that prototype. The duplicate is then owned by the default field
and can be mutated through the normal Inspector without modifying the type
prototype. Anonymous script types use their native Resource base in the picker
because Godot's picker accepts registered type names rather than script paths;
kernel validation still enforces the exact resolved Script identity.
Saving or refreshing through the database document applies or discards the
whole local schema draft. Saving previews typed alterations and presents their
descriptions before application.

#### Column editor component inventory

The scene-based schema editor has the following explicit component status:

| Component | Status | Reason |
|---|---|---|
| `column_editor/gdsql_column_editor.gd` / `.tscn` | Active | Shared scroll and row-list coordinator instantiated by both table-fold scenes. |
| `column_editor/gdsql_column_editor_header.tscn` | Active | Self-contained scene-authored header with directly editable labels, separators, and cell sizing. |
| `column_editor/gdsql_column_editor_row.gd` / `.tscn` | Active | Self-contained reusable column row with a conventional directly editable node hierarchy; the editor scene keeps one instance as its visual template and first configured row. |
| `column_editor/gdsql_column_editor_draft.gd` | Active | Typed mutable editor draft responsible for validation and conversion to catalog definitions or alterations. |
| `gdsql_editor_resource_type_field.gd` | Active | Native Resource prototype picker used by scene-backed column rows. |
| `gdsql_editor_variant_value_field.gd` | Active | Shared typed value editor used by schema defaults, table rows, predicates, and mutation values. |
| `gdsql_table_data_row.gd` / `.tscn` | Active | Still used by the table data document and query result node; it is not part of the schema-row migration. |
| `index/gdsql_index_property_row.gd` / `.tscn` | Active | Scene-authored summary and removal control for an existing primary or secondary index. |

The superseded `gdsql_column_tree`, `gdsql_column_draft_row`, and
`gdsql_column_property_row` scripts and scenes were removed after their table
fold references moved to the new component.

A table data document owns row viewing and manipulation without schema editing.
It uses canonical `SELECT`, `INSERT`, `UPDATE`, and `DELETE` queries through
the opened database. Column names and catalog types remain visible while
entering values. A shared typed value field parses scalar, vector, transform,
collection, and packed-array values through Godot Variant syntax. It uses the
native editor resource picker for `TYPE_OBJECT`, with explicit access to the
appropriate Godot resource editor by selecting the displayed resource; the
picker's caret owns replacement and clearing. Column default editors reuse the
same typed field contract.
Generated or new auto-increment values are read-only.
Editor controls do not read or write ConfigFile sections directly.

`EditorDataGrid` is a shared presentation component with capability profiles
for row data, query results, schema definitions, import/export previews, and
activity entries. A profile controls available interactions; it does not own
query or persistence behavior.

## Results and feedback

Every editor operation consumes structured results and diagnostics. Successful
values update the relevant surface state. Informational messages, warnings,
errors, duration, and operation identity are forwarded to `ActivityPanel`.

The activity panel uses a bounded scrollable list of responsive entry controls.
Entries retain time, severity, action, and message fields while adapting to the
dock width. The oldest entry is removed when the configured retention limit is
exceeded. Right-clicking the panel exposes feed-level actions such as clearing
all entries. Error entries retain severity styling and may focus the dock.

Inline validation remains close to the field or graph element that caused it.
Destructive operations and external-file conflicts use explicit prompts.
Ordinary runtime failures remain diagnostics and do not become editor-side
exceptions.

## Configuration and project files

Editor presentation configuration may define action metadata, translation
keys, icons, shortcuts, labels, tooltips, empty states, and display ordering.
It does not define database behavior, validation policy, filesystem access, or
transactions.

Project-owned editor state belongs under `res://.gdsql/`. Runtime database
content remains under the roots selected through database registrations.
Editor layout preferences that belong to one user may use Godot editor settings
or user-scoped plugin data rather than project database files.

## Dependency rules

- Editor surfaces depend on editor coordinators or public runtime contracts.
- Runtime, catalog, storage, and query-model classes do not import editor code.
- `Workbench` and `WorkbenchSession` remain independent from `Control`.
- Query graph controls mutate `QueryGraph`; they do not construct execution
  plans or access storage.
- Catalog structure changes use `CatalogAdministrationService`.
- Row changes use canonical queries.
- Physical paths and ConfigFile details remain inside registration, catalog,
  and storage infrastructure.
- Action definitions contain presentation metadata; context hubs own behavior.
- Structured results and diagnostics cross the runtime-to-editor boundary.

## Documentation boundaries

- [`core.md`](core.md) defines the runtime architecture and the editor-to-runtime
  dependency direction.
- [`editor.md`](editor.md) defines editor ownership and communication.
- [`editor-mermaid-diagram.md`](editor-mermaid-diagram.md) gives the compact
  editor dependency flow.
- [`query-graph-roadmap.md`](query-graph-roadmap.md) records the ordered visual
  query operations and table-result capability rules.
- [`editor-ui-migration-blueprint.md`](editor-ui-migration-blueprint.md)
  records legacy capabilities and possible reassignment without prescribing
  implementation.
- [`glossary.md`](glossary.md) tracks the state of each stable editor concept.

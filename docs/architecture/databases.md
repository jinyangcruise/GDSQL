# Database Roles, Runtime Loading, and Game Persistence

## Purpose

GDSQL should provide approachable defaults for the common data lifecycles most
games manage:

- Authored game data shipped with the project.
- Mutable state owned by a particular save slot.
- Mutable user or installation state shared across save slots.
- Project-defined databases such as analytics, logs, or temporary simulations.

These kinds of data have different ownership, durability, and deployment
requirements. GDSQL should support advanced arrangements without presenting
every arrangement as equally advisable.

The recommended default is:

> Keep authored content in a project database under `res://` and keep mutable
> player or world state in a separate save database under `user://`. Keep
> settings and other global user state outside individual save slots.

## 1. Opinionated database roles

### Project database

The project database contains data authored as part of the game:

- Items, skills, heroes, enemies, and classes.
- Dialogue and quest definitions.
- Level and encounter configuration.
- Balance values and progression tables.
- Other editor-managed reference data.

Editor documents and database content use separate project-owned roots:

```text
res://.gdsql/
├── settings.cfg
└── graphs/

res://data/
├── databases.cfg
└── game_content/
    ├── schema/
    └── tables/
```

This database is shipped with the game and should normally be treated as
read-only at runtime. An exported project's `res://` content may be packed and
must not be used as a writable save location.

### Save-state database

The save-state database contains mutable runtime state:

- Save slots and player profiles.
- Inventory quantities and equipped items.
- Quest progress and dialogue state.
- Current world, map, and checkpoint state.
- Runtime-created characters or objects.
- Difficulty or gameplay options intentionally owned by that save slot.

The recommended writable root is:

```text
user://gdsql/saves/
├── save_1/
│   ├── databases.cfg
│   └── game_state/
│       ├── schema/
│       └── tables/
└── new_game_plus/
    ├── databases.cfg
    └── game_state/
        ├── schema/
        └── tables/
```

The schema definition or initialization code is shipped with the project. On
first use of a save name, GDSQL creates or opens the corresponding database
under `user://gdsql/saves/<save_name>/`. Later schema compatibility can use a
lightweight table or save-format version; a general migration framework remains
outside the current scope.

### Settings database

The settings database contains mutable user or installation state that should
not change when the active save slot changes:

- Audio, input, language, and accessibility preferences.
- The last selected profile or save slot.
- Account-wide or installation-wide options.
- Global unlocks, when the game intentionally owns them outside save slots.

The recommended location is independent from `saves/`:

```text
user://gdsql/settings/
├── databases.cfg
└── settings/
    ├── schema/
    └── tables/
```

The standard logical role is `settings`. This database can use the same
transactions and checkpoint policies as a save database without being managed
as a save slot.

### Content representations are stages, not separate authorities

The content lifecycle has three representations of one logical content
database:

```text
1. Authoring sources
   res:// base database + optional content packages
        ↓ build and validate
2. Derived persistent cache
   user://gdsql/cache/effective_content
        ↓ lazy loading
3. Active in-memory working set
   typed loaded tables, rows, indexes, and pages
```

Only the authoring sources are authoritative for content. The derived cache is
reproducible, and the active working set is a runtime representation of that
cache or of a direct source build. Neither belongs to player save state.

The save database is a separate logical database rather than a fourth content
stage:

```text
user://gdsql/saves/<save_name>/
    Authoritative mutable state for one save
```

## 2. Keep database execution boundaries explicit

One canonical query executes against one logical database context. A table
source, join, transaction, and query plan remain within that database.

The project and save databases may refer to the same domain concepts through
stable identifiers without becoming one execution context. For example, a save
row may store an `item_id` whose definition exists in the project database:

```text
res:// game_content.items
    id = "iron_sword"
    display_name = "Iron Sword"
    base_damage = 12

user://gdsql/saves/save_1 game_state.inventory
    item_id = "iron_sword"
    quantity = 1
    durability = 83
```

The application or future model layer queries each database independently and
composes the result:

```gdscript
var inventory_rows := save_database.execute(inventory_query)
var item_definitions := content_database.execute(item_query)
var inventory_view := inventory_service.combine(
	inventory_rows,
	item_definitions,
)
```

This preserves several useful properties:

- Save files do not duplicate complete authored definitions.
- Content updates can replace project data without rewriting every save row.
- Transactions have one clear durability target.
- Storage backends can differ between content and save data.
- Missing or changed content identifiers can produce an application-level
  fallback instead of corrupting storage behavior.

## 3. Memory-resident operation

The active database does not need to decode and reopen persistent files for
every query. A buffered storage implementation can keep loaded tables, rows,
and indexes in memory while using another storage backend for persistence:

```text
QueryExecutor
    ↓
TableStorage
    ↓
BufferedTableStorage
    ├── Loaded tables and indexes
    ├── Committed in-memory state
    ├── Dirty row/table/page tracking
    └── Persistence backend
        ├── ConfigFileTableStorage
        └── Future BinaryTableStorage
```

Loading should be lazy by default. Opening a database loads its catalog and
small structural metadata; querying a table loads that table when needed.

The practical loading unit depends on the backend:

- ConfigFile storage can lazily load separate table files, but Godot parses a
  complete `.cfg` file when that table is loaded.
- A paged binary backend can load index and row pages independently.
- A purely in-memory backend has no persistent source and is useful for tests,
  simulations, and temporary session data.

The planned paged binary backend keeps the same one-file-per-table organization
as ConfigFile storage. A table file begins with a header containing a format
version, schema fingerprint, page size, row count, generated-key sequence, and
root page references for rows and indexes. The remaining file contains
independently addressable pages. A `.gsql` extension can identify this binary
table representation while `.cfg` continues to identify the readable backend.

Read-only project tables may remain cached until explicitly unloaded or until a
memory policy evicts them. Dirty save-state data must be checkpointed before it
can be safely evicted.

The working set should use typed runtime concepts such as `TableSnapshot`,
`RowRecord`, and index structures. It should not expose a second dictionary-
based query API. Dictionaries remain appropriate when decoding dynamic storage
or materializing compatibility-oriented results.

Keeping all content in memory is a valid policy when the content comfortably
fits the game's memory budget. Larger projects may choose among:

| Loading policy | Behavior |
|---|---|
| `LOAD_ALL` | Load the complete effective content database. |
| `LAZY_TABLES` | Load a complete table on first access. |
| `PAGED` | Load only required binary index and row pages. |
| `MANUAL` | Let game code preload and release selected tables. |

ConfigFile storage naturally supports table-level loading because reading one
table parses its complete `.cfg` file. A paged binary backend enables smaller
working sets, index-root loading, page eviction, and queries whose matching
rows do not require loading a complete table.

Database rows should also avoid eagerly retaining heavy assets when only their
identity is needed. Content may store resource paths or UIDs and let Godot load
textures, scenes, audio, and other large resources on demand.

## 4. Commit and checkpoint are different operations

A transaction commit establishes a new valid database state. A checkpoint
makes committed state durable on persistent storage.

```text
INSERT / UPDATE / DELETE
    ↓
StorageSession stages mutations
    ↓
Constraints are validated
    ↓
Transaction commits atomically to memory
    ↓
Changed rows, indexes, and metadata become dirty
    ↓
Checkpoint persists dirty state
```

This distinction allows gameplay to perform many small operations without
rewriting files after every query. It also means a successful in-memory commit
does not claim that data has reached disk.

A checkpoint should:

1. Take a stable view of committed dirty state.
2. Persist only affected tables or pages when the backend supports it.
3. Clear the corresponding dirty markers only after persistence succeeds.
4. Return structured diagnostics on failure.
5. Preserve dirty state after a failed checkpoint so the operation can retry.

ConfigFile persistence may need to rewrite an affected table file. A future
binary backend may write only dirty pages or use a journal.

## 5. Recommended persistence policy

The recommended default for a mutable game-state database is periodic
checkpointing combined with explicit checkpoints at meaningful game events.

Useful explicit save points include:

- Completing a level or quest.
- Reaching a checkpoint.
- Changing save slots.
- Returning to a title screen.
- Confirming an important purchase or irreversible action.
- Receiving an application pause or graceful shutdown notification.

An exit-only policy is not sufficient. A crash, forced termination, power
loss, or platform suspension may prevent shutdown code from running.

Planned policies are:

| Policy | Behavior | Recommended use |
|---|---|---|
| `IMMEDIATE` | Checkpoint after each committed mutation transaction. | Small tools or durability-first data. |
| `PERIODIC` | Checkpoint dirty databases on a configurable interval. | Default runtime game-state behavior. |
| `MANUAL` | Checkpoint only when game code requests it. | Explicit save systems and temporary sessions. |
| `ON_EXIT` | Attempt a checkpoint during graceful shutdown. | Supplemental protection, never the only policy. |

Periodic checkpointing should be configurable and should do nothing when the
database is clean. Games may combine `PERIODIC`, explicit event checkpoints,
and the best-effort exit checkpoint.

## 6. Runtime service and optional Node adapter

The database and persistence implementation should not itself extend `Node`.
Storage must remain usable in unit tests, headless tools, dedicated servers,
and code that is not attached to a scene tree.

The service split keeps database discovery separate from persistence policy:

```text
DatabaseRegistry (RefCounted service)
    ├── Registered database handles
    ├── Standard and project-defined logical role bindings
    ├── Effective-content database replacement
    └── Active save selection

PersistenceCoordinator (RefCounted service)
    ├── Persistence policies
    ├── Dirty-state inspection
    └── checkpoint() orchestration

GDSQLRuntimeNode (optional Node/autoload adapter)
    ├── Periodic Timer integration
    ├── Pause and shutdown notifications
    ├── User-facing signals
    └── Delegation to registry, content loader, and persistence coordinator
```

`DatabaseRegistry` answers which ordinary `GDSQLDatabase` currently
satisfies a logical role. `PersistenceCoordinator` answers when and how dirty
committed state becomes durable. Effective-content construction remains the
responsibility of `ContentOverlayLoader`; the top-level runtime service only
coordinates these focused components.

Durable database registration metadata lives in
`user://gdsql/databases.cfg`. Each registration records its public name,
logical database name, data root, and storage backend. Role bindings share the
same file. `GDSQLConfigFileDatabaseRegistryStore` exposes this data as a typed
snapshot for game startup, tests, and future editor management.

The registry is available as a standalone `RefCounted` service:

```gdscript
var registry := GDSQLDatabaseRegistry.new()
registry.register(&"effective_content", content_database)
registry.register(&"save_1", save_database)
registry.bind_role(&"content", &"effective_content")
registry.bind_role(&"save", &"save_1")

var active_content := registry.resolve_role(&"content").get_database()
var active_save := registry.resolve_role(&"save").get_database()
```

Calling `bind_role()` again changes the active handle while preserving every
registered database. `unregister()` clears role bindings that selected the
removed handle.

For an ordinary Godot game, the optional node can be installed as an autoload
and provide a small top-level API:

```gdscript
GDSQLRuntime.register_content_database(
	&"base_content",
	"res://data/game_content",
)

GDSQLRuntime.open_save(
	&"save_1",
	GDSQLCheckpointPolicy.periodic(30.0),
)

GDSQLRuntime.register_database(
	&"analytics",
	"user://gdsql/analytics",
	GDSQLCheckpointPolicy.periodic(60.0),
)

var content_database := GDSQLRuntime.database(&"content")
var save_database := GDSQLRuntime.database(&"save")
var analytics_database := GDSQLRuntime.database(&"analytics")

GDSQLRuntime.rebuild_content()
GDSQLRuntime.checkpoint_save()
```

The logical `content` binding resolves to the current effective content
database. The logical `save` binding resolves to the selected save slot.
Changing the enabled mod set rebuilds and replaces the `content` binding;
switching save slots replaces the `save` binding. Registration hides
composition details but still produces ordinary `GDSQLDatabase` handles that
use the canonical query pipeline.

Runtime configuration such as the selected save, enabled mods, and deterministic
mod load order may live in a small file outside the role-bound databases:

```text
user://gdsql/runtime.cfg
```

If enabled mods are save-specific, save metadata may declare the desired set.
The runtime service resolves that configuration before exposing the effective
`content` database. Query code should not repeatedly inspect an active-mods
table to decide which content rows exist.

## 7. ORM database roles

The future ORM should bind model classes to logical database roles rather than
physical paths or database arguments. `GDSQLModel` is the common abstract root;
the standard convenience hierarchy is:

```text
GDSQLModel
├── GDSQLContentModel
│   └── Read-only models from the effective content database
├── GDSQLSaveModel
│   └── Mutable models from the active save database
└── GDSQLSettingsModel
    └── Mutable models shared across save slots
```

`GDSQLContentModel` resolves through the `content` role. It exposes query and
refresh behavior, while `save()` and `delete()` return a read-only diagnostic.
Mod merging and cache construction happen before content models are
materialized.

```gdscript
class_name Hero
extends GDSQLContentModel

func table_name() -> StringName:
	return &"heroes"


static func query() -> GDSQLModelQuery:
	return GDSQLModels.query(Hero)


static func find(identity: Variant) -> GDSQLQueryResult:
	return GDSQLModels.find(Hero, identity)
```

`GDSQLSaveModel` resolves through the `save` role and exposes mutable row
operations. It does not manage save slots; the database registry determines
which save name currently satisfies that role.

```gdscript
class_name InventoryEntry
extends GDSQLSaveModel

func table_name() -> StringName:
	return &"inventory"
```

Runtime composition configures `GDSQLModels` once. Normal usage starts from the
model class:

```gdscript
var heroes := Hero.query() \
	.where(GDSQLExpr.column(&"level").greater_than(3)) \
	.all()

var inventory := InventoryEntry.query().all()
```

The model registry maps `Hero` to the active `content` database and
`InventoryEntry` to the active `save` database. Models remain unaware of
`res://`, `user://`, mod packages, cache manifests, save directories, and
storage formats. An explicit model context may replace the default registry for
tests or advanced multi-runtime use.

`GDSQLSettingsModel` resolves through a separate `settings` role for user data
that should survive save-slot changes:

```gdscript
class_name AudioSetting
extends GDSQLSettingsModel

func table_name() -> StringName:
	return &"audio"
```

Logical roles are extensible rather than limited to these three conveniences.
For example, analytics can use its own database and persistence policy:

```gdscript
class_name AnalyticsEvent
extends GDSQLModel

func database_role() -> StringName:
	return &"analytics"

func access_mode() -> GDSQLModelAccess.Mode:
	return GDSQLModelAccess.Mode.READ_WRITE

func table_name() -> StringName:
	return &"events"
```

The registry can bind `analytics` to local persistent storage, a temporary
in-memory database, or another supported composition without changing model
query code. A custom model declares its access mode explicitly;
`GDSQLContentModel`, `GDSQLSaveModel`, and `GDSQLSettingsModel` inherit their
standard policies.

Relationships inside one database role may compile to joins. A relationship
between content and save models resolves through separate role-scoped queries
and result composition; it does not turn the two databases into one transaction
or query-planning context.

## 8. Data-driven content packages and mods

The content overlay mechanism is specifically a way to manage data-driven game
content using ordinary GDSQL mechanics. A package can add database rows,
override base rows through stable identifiers, remove rows through an explicit
typed operation, and provide assets referenced by those rows.

This does not define an executable mod scripting system. If a game permits
packages to execute behavior, the game must provide and secure that API
separately from GDSQL's content loading.

### Content package layout

Both the base game and a mod can use the same portable content layout:

```text
content/
├── assets/
│   ├── icons/
│   ├── audio/
│   └── scenes/
├── data/
│   ├── databases.cfg
│   └── game_content/
│       ├── schema/
│       └── tables/
└── manifest.cfg
```

`manifest.cfg` identifies the package, its version, dependencies, and declared
load-order requirements. `data/` contains one or more GDSQL databases. Rows in
those databases may reference files under `assets/` through package-relative
asset identifiers, paths, or resolved Godot resource UIDs.

The base project may keep the simpler default `res://data/` layout or adopt a
`res://content/data/` root when treating its own content as a package. A mod
directory can mirror the complete structure:

```text
user://mods/
└── expanded_arsenal/
    └── content/
        ├── assets/
        ├── data/
        └── manifest.cfg
```

The package format is separate from query execution. A package may later be a
directory, archive, or Godot resource pack, but its database content remains an
immutable input to effective-content construction rather than independently
mutated save state.

### Effective content database

At startup or after the enabled package set changes, the content loader builds
one effective database and binds it to the logical `content` role:

```text
Immutable base content from res://
    ↓
Enabled immutable package layers in deterministic order
    ↓
Schema, data, and asset-reference validation
    ↓
Disposable user:// effective-content cache when enabled
    ↓
Active in-memory content working set
```

Normal game queries use this single effective database. They do not need to
know which package supplied each row, and the query planner still operates
inside one database context.

The optional generated cache uses an explicitly disposable location:

```text
user://gdsql/cache/effective_content/
├── manifest.cfg
├── databases.cfg
└── game_content/
    ├── schema/
    └── tables/
```

This cache is not save state. It can be deleted and rebuilt from the shipped
base package and enabled mods. If cache creation is disabled or fails, the
loader may construct the active working set directly from validated sources.

### Stable overrides and deterministic merging

An override keeps the stable identifier of the row it replaces. A mod changing
the base `iron_sword` definition still supplies the ID `iron_sword`:

```text
Base layer:      id = "iron_sword", damage = 12
Mod layer:       id = "iron_sword", damage = 18
Effective row:   id = "iron_sword", damage = 18
```

A different identifier adds a different definition. Disabling the mod then
removes that additional definition and reveals the unchanged base row. Removing
base content requires an explicit removal marker or equivalent typed operation;
it must not delete the authoritative base row.

The loader records package identifiers and versions, dependencies, deterministic
layer order, row provenance, conflicts, schema compatibility, and the base
content version. A simple initial precedence rule is `base → declared mod load
order`, where a later validated layer wins. Filesystem enumeration order must
never silently determine precedence.

The cache manifest fingerprints the base version, enabled package checksums or
versions, and their order. Any mismatch invalidates the cache. The cache must
never become the only copy of a base or mod definition.

### Save references to mod content

Save rows may reference effective content through stable IDs. If an ID exists
only in a disabled or removed mod, loading applies an explicit game policy:

- Report the missing dependency and ask the player to re-enable the mod.
- Substitute a declared fallback definition.
- Preserve the unresolved save row while hiding it from active gameplay.
- Refuse to load the save until the required content is available.

GDSQL reports the unresolved reference; it does not silently rewrite or delete
player state. Save metadata may record the enabled package set so the game can
explain incompatibilities.

## 9. Signals and diagnostics

The Node adapter is a natural place for Godot signals because it owns lifecycle
integration, not because persistence fundamentally requires a Node.

Potential signals include:

```gdscript
signal database_dirty_changed(database_name: StringName, dirty: bool)
signal checkpoint_started(database_name: StringName)
signal checkpoint_completed(database_name: StringName)
signal checkpoint_failed(
	database_name: StringName,
	diagnostics: GDSQLDiagnostics,
)
```

Signals notify game code and UI; they do not replace operation results. An
explicit `checkpoint()` call still returns a structured `CheckpointResult` so
callers can handle success or failure directly.

Checkpoint failures should not be printed automatically. A game may show a
save icon, retry later, display an error, disable quitting, or continue with
dirty in-memory state according to its own UX.

## 10. Suggested implementation order

This runtime persistence layer should follow the transactional API because it
depends on clear commit and rollback semantics:

1. Implement callback-scoped transactions with one shared storage session.
2. Add the database registry, durable registration metadata, and role bindings.
3. Add explicit checkpoint results, participants, policies, and coordination.
4. Implement an in-memory table storage backend for isolated behavior.
5. Implement buffered storage over a persistent backend with dirty tracking.
6. Add the optional Node/autoload adapter, timer, and signals.
7. Add model-registry integration.
8. Add memory limits, clean-table eviction, and binary page-level loading.

None of these stages changes `QuerySpec`, expression semantics, result
materialization, or frontend compilation. They extend storage composition and
runtime lifecycle management.

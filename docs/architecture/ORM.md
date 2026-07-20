# GDSQL ORM Proposal

## Purpose

GDSQL can support a code-first object-relational mapper with an API inspired by
Laravel's Eloquent models. The ORM would provide convenient model helpers,
typed relationship declarations, persistence methods, and model
materialization without creating a second query or execution system.

The ORM is a higher-level frontend:

```text
GDSQLModel hierarchy and ModelQuery
    ↓
ModelMapper
    ↓
QuerySpec
    ↓
Validation and binding
    ↓
QueryPlan
    ↓
QueryExecutor
    ↓
ResultMaterializer
    ↓
GDSQLModel instances
```

Model classes must not access ConfigFile, physical paths, storage sessions,
planners, or executors directly.

## Model hierarchy and database roles

`GDSQLModel` is the common abstract root. Standard subclasses associate common
game-data lifecycles with logical database roles:

```text
GDSQLModel
├── GDSQLContentModel
│   └── Logical database role: content
├── GDSQLSaveModel
│   └── Logical database role: save
└── GDSQLSettingsModel
    └── Logical database role: settings
```

The model registry resolves these roles to ordinary database handles:

```text
content → effective base-and-mod content database
save     → currently selected save database
settings → project-wide user settings database
```

Models declare tables but do not declare physical database paths or require a
database argument for normal queries.

### Content models

`GDSQLContentModel` represents authored content after base data and enabled mod
layers have produced the effective content database:

```gdscript
class_name Hero
extends GDSQLContentModel

var id: int
var name: String
var level: int


static func table_name() -> StringName:
	return &"heroes"


static func primary_key() -> StringName:
	return &"id"
```

Content models are read-only during ordinary gameplay:

```gdscript
var hero := Hero.find(1)

var veterans := Hero.query() \
	.where(GDSQLExpr.column(&"level").greater_than(10)) \
	.order_by(&"level", GDSQLOrderClause.SortDirection.DESCENDING) \
	.get()
```

Content creation, overrides, and removals belong to authoring or effective-
content construction. A content model does not expose runtime `save()` or
`delete()` operations.

### Save models

`GDSQLSaveModel` represents mutable state owned by the active save slot. It is
not responsible for selecting, loading, or checkpointing save slots:

```gdscript
class_name InventoryEntry
extends GDSQLSaveModel

var id: int
var item_id: StringName
var quantity: int


static func table_name() -> StringName:
	return &"inventory"
```

Save models expose row-persistence helpers:

```gdscript
var entry := InventoryEntry.find(1)

entry.quantity += 1
entry.save()
entry.delete()
```

The helpers translate into canonical operations:

| Model operation | Available to | Canonical operation |
|---|---|---|
| `find()`, `query()`, and `refresh()` | All model roles | `GDSQLSelectQuerySpec` |
| Creating and saving a new model | Mutable model roles | `GDSQLInsertQuerySpec` |
| Saving an existing model | Mutable model roles | `GDSQLUpdateQuerySpec` |
| `delete()` | Mutable model roles | `GDSQLDeleteQuerySpec` |

### Settings and custom model roles

`GDSQLSettingsModel` represents mutable user or installation state shared
across save slots, such as audio, input, accessibility, and profile-selection
settings. Projects may extend `GDSQLModel` directly for additional databases:

```gdscript
class_name AnalyticsEvent
extends GDSQLModel


static func database_role() -> StringName:
	return &"analytics"


static func access_mode() -> GDSQLModelAccessMode:
	return GDSQLModelAccessMode.READ_WRITE


static func table_name() -> StringName:
	return &"events"
```

The runtime registry may bind `analytics` to local persistent storage, a
temporary in-memory database, or another supported composition. Model code is
unchanged because it depends only on the logical role.

## Model responsibilities

`GDSQLModel` provides shared materialization, identity, query, and relationship
behavior without owning database infrastructure. Standard subclasses establish
default roles and mutation policies, while custom models may declare another
role.

Potential responsibilities:

- Declare the associated logical role, table, and primary key.
- Declare or inherit a read-only or read-write access mode.
- Hold materialized attributes.
- Track whether the model represents a persisted row.
- Expose shared `find()`, `query()`, and `refresh()` helpers.
- Expose mutations only when the model role permits them.
- Declare relationships.
- Retain a model context supplied during materialization.

The model should not:

- Construct storage paths.
- Select save slots or resolve mod packages.
- Load or save ConfigFile resources.
- Evaluate predicates.
- Select plans.
- Commit storage sessions directly.

## Model query frontend

`GDSQLModelQuery` would provide model-oriented query helpers while producing
the same `GDSQLQuerySpec` used by every other frontend.

For example:

```gdscript
Hero.query() \
	.where(GDSQLExpr.column(&"level").greater_than_or_equal(5)) \
	.limit(10) \
	.to_query_spec()
```

Normal model calls resolve the database from the model registry. An explicit
`GDSQLModelContext` remains available for tests and advanced multiple-runtime
scenarios.

The model query may internally delegate to the Fluent API or construct
canonical query objects directly. In both cases, model-specific concerns stop
at `QuerySpec`.

## Model mapping

`GDSQLModelMapper` translates between model metadata, canonical queries, and
result mappings.

Potential API:

```gdscript
func to_insert(model: GDSQLModel) -> GDSQLInsertQuerySpec
func to_update(model: GDSQLModel) -> GDSQLUpdateQuerySpec
func to_delete(model: GDSQLModel) -> GDSQLDeleteQuerySpec
func create_result_mapping(model_type: GDScript) -> GDSQLResultMapping
```

Stable mapping concepts should use typed classes. Dictionaries remain
appropriate only when reading dynamic external mapping formats or row data.

## Relationships

Relationships describe how model objects navigate between tables. They belong
to the model and mapping frontend, not to storage.

Proposed relationship kinds:

- `has_one`
- `has_many`
- `belongs_to`
- `many_to_many`

Relationship definitions should be typed:

```gdscript
static func relationships() -> Array[GDSQLRelationshipDefinition]:
	return [
		GDSQLRelationshipDefinition.has_many(
			&"skills",
			Skill,
			&"hero_id",
			&"id",
		),
	]
```

A relationship definition may contain:

- Relationship name.
- Relationship kind.
- Related model type.
- Local key.
- Foreign key.
- Pivot table and pivot keys for many-to-many relationships.

Relationship loading translates into ordinary canonical queries:

```text
has_many
    → SELECT related rows WHERE foreign_key = local_key

belongs_to
    → SELECT related row WHERE related_key = foreign_key

many_to_many
    → SELECT through a pivot-table join
```

Simple relationships can initially use separate queries. Efficient eager
loading and many-to-many relationships will benefit from complete join and
multi-source query support.

Relationships within one logical database role may compile into joins. A
relationship between a content model and a save model uses separate queries
resolved through `content` and `save`, followed by ORM-level composition. This
does not merge their transaction or planning contexts.

## Relationship loading

The ORM may eventually support:

- Explicit loading: `hero.load(&"skills")`
- Eager loading: `Hero.query().with(&"skills").get()`
- Constrained loading: relationships with an additional model query
- Relationship existence predicates

Lazy loading through ordinary property access should be treated cautiously in
GDScript because hidden database access makes execution and failure behavior
less visible. Explicit loading is a safer initial design.

## Result materialization

`GDSQLModelResultMaterializer` converts execution rows into model instances:

```text
GDSQLRowSet
    ↓
GDSQLResultMapping
    ↓
GDSQLModelResultMaterializer
    ↓
Hero, InventoryEntry, or another GDSQLModel
```

Materialization may:

- Instantiate the requested model type.
- Assign mapped columns to model properties.
- Record the model context, logical role, and persisted state.
- Attach explicitly loaded relationships.
- Preserve structured diagnostics for mapping failures.

The executor remains unaware of model classes.

## Relationships and foreign keys

Model relationships and catalog foreign keys are related but separate:

- A relationship describes object navigation and loading.
- A foreign key describes a database integrity constraint.

The ORM may infer a default relationship from catalog metadata or validate a
declared relationship against it, but the same class should not represent both
concepts.

## External mapper formats

XML or another external mapper format can remain an optional declaration
frontend:

```text
XML mapping document
    ↓
GDSQLMapperCompiler
    ↓
Typed model, relationship, and result mapping definitions
    ↓
GDSQLModelMapper
```

This allows code-first and external mapping styles to share the same typed ORM
layer. External formats must not create a separate execution path.

## Suggested implementation order

The ORM should follow the canonical query capabilities it consumes:

1. Complete `SELECT`, expression, join, and result-schema behavior.
2. Implement result mappings and model materialization.
3. Introduce `GDSQLModel`, `GDSQLContentModel`, `GDSQLSaveModel`, and
   `GDSQLSettingsModel`.
4. Add the role-aware model registry, context, query, mapper, and materializer.
5. Add `belongs_to`, `has_one`, and `has_many` using explicit loading.
6. Add eager loading and many-to-many relationships.
7. Optionally add external mapper compilation.

The ORM remains optional. Applications can continue using `GDSQLDatabase`, the
Fluent API, SQL, or query graphs directly.

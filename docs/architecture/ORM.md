# GDSQL ORM Proposal

## Purpose

GDSQL can support a code-first object-relational mapper with an API inspired by
Laravel's Eloquent models. The ORM would provide convenient model helpers,
typed relationship declarations, persistence methods, and model
materialization without creating a second query or execution system.

The ORM is a higher-level frontend:

```text
DatabaseModel and ModelQuery
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
DatabaseModel instances
```

Model classes must not access ConfigFile, physical paths, storage sessions,
planners, or executors directly.

## Proposed model API

A model associates one GDScript type with a database table:

```gdscript
class_name Hero
extends GDSQLDatabaseModel

var id: int
var name: String
var level: int


static func table_name() -> StringName:
	return &"heroes"


static func primary_key() -> StringName:
	return &"id"
```

Common helpers may include:

```gdscript
var hero := Hero.find(database, 1)

var veterans := Hero.query(database) \
	.where(&"level", GDSQLComparisonOperator.GREATER_THAN, 10) \
	.order_by(&"level", GDSQLSortDirection.DESCENDING) \
	.get()

hero.name = "Knight"
hero.save()
hero.delete()
```

The helpers translate into canonical operations:

| Model operation | Canonical operation |
|---|---|
| `find()` and `query()` | `GDSQLSelectQuerySpec` |
| Creating and saving a new model | `GDSQLInsertQuerySpec` |
| Saving an existing model | `GDSQLUpdateQuerySpec` |
| `delete()` | `GDSQLDeleteQuerySpec` |

## Model responsibilities

`GDSQLDatabaseModel` would provide model-oriented convenience without owning
database infrastructure.

Potential responsibilities:

- Declare the associated table and primary key.
- Hold materialized attributes.
- Track whether the model represents a persisted row.
- Expose `find()`, `query()`, `save()`, `delete()`, and `refresh()` helpers.
- Declare relationships.
- Retain a database handle or model session supplied during materialization.

The model should not:

- Construct storage paths.
- Load or save ConfigFile resources.
- Evaluate predicates.
- Select plans.
- Commit storage sessions directly.

## Model query frontend

`GDSQLModelQuery` would provide model-oriented query helpers while producing
the same `GDSQLQuerySpec` used by every other frontend.

For example:

```gdscript
Hero.query(database) \
	.where(&"level", GDSQLComparisonOperator.GREATER_THAN_OR_EQUAL, 5) \
	.limit(10) \
	.to_query_spec()
```

The model query may internally delegate to the Fluent API or construct
canonical query objects directly. In both cases, model-specific concerns stop
at `QuerySpec`.

## Model mapping

`GDSQLModelMapper` translates between model metadata, canonical queries, and
result mappings.

Potential API:

```gdscript
func to_insert(model: GDSQLDatabaseModel) -> GDSQLInsertQuerySpec
func to_update(model: GDSQLDatabaseModel) -> GDSQLUpdateQuerySpec
func to_delete(model: GDSQLDatabaseModel) -> GDSQLDeleteQuerySpec
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

## Relationship loading

The ORM may eventually support:

- Explicit loading: `hero.load(&"skills")`
- Eager loading: `Hero.query(database).with(&"skills").get()`
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
Hero, Skill, or another GDSQLDatabaseModel
```

Materialization may:

- Instantiate the requested model type.
- Assign mapped columns to model properties.
- Record the database handle and persisted state.
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
3. Introduce `GDSQLDatabaseModel`, `GDSQLModelQuery`, and `GDSQLModelMapper`.
4. Add `belongs_to`, `has_one`, and `has_many` using explicit loading.
5. Add eager loading and many-to-many relationships.
6. Optionally add external mapper compilation.

The ORM remains optional. Applications can continue using `GDSQLDatabase`, the
Fluent API, SQL, or query graphs directly.

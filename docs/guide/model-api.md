# Model API

Models are a typed frontend over the same canonical query pipeline. A model
binds code to an existing table and logical database role; it is never the
schema authority.

## Registration

Register every model class used directly or through relationships after runtime
startup:

```gdscript
for model_script in [HeroContent, SkillContent, HeroSave]:
    var registered := GDSQLRuntime.register_model(model_script)
    if not registered.is_successful():
        registered.diagnostics.print_to_debug()
        return
```

Registration validates table metadata, generated properties, access mode, and
relationship keys against the database currently bound to the model's role.

## Read models

Generated user models expose static `query()` and `find()` methods:

```gdscript
var found := HeroContent.find(hero_id)
if found.is_successful():
    var hero := found.get_value() as HeroContent
    if hero != null:
        print(hero.name)

var veterans := HeroContent.query() \
    .where(GDSQLExpr.column(&"level").greater_than_or_equal(10)) \
    .order_by(&"level", GDSQLOrderClause.SortDirection.DESCENDING) \
    .limit(20) \
    .all()
```

`GDSQLModelQuery` provides `where`, `order_by`, `limit`, `offset`, `distinct`,
and `with`. Terminal methods are:

| Method | Result value |
|---|---|
| `all()` | Array of materialized models |
| `first()` | First model or `null` |
| `find(identity)` | Model matching the registered primary key or `null` |
| `to_query_spec()` | Canonical select specification without executing it |

Like the lower-level query builders, a model query cannot be modified after
`to_query_spec()` builds its canonical query.

## Eager-load relationships

```gdscript
var result := HeroContent.query().with(&"skills").find(hero_id)
if result.is_successful():
    var hero := result.get_value() as HeroContent
    var skills: Array = hero.get_related(&"skills")
```

Use `is_relationship_loaded()` to distinguish an unloaded relationship from a
loaded relationship whose result is empty or `null`. See
[Relationships](./relationships) for inference and declaration rules.

## Mutate save and settings models

Materialized mutable models track their original values:

```gdscript
var found := HeroSave.find(save_hero_id)
if found.is_successful():
    var hero := found.get_value() as HeroSave
    hero.current_health -= 10
    var saved := hero.save()
```

- `save()` updates only changed non-primary-key fields.
- `refresh()` reloads the row into the same model object.
- `delete()` removes the persisted row and marks the object as no longer
  persisted.
- Changing a persisted model's primary key is rejected.
- Content models reject `save()` and `delete()` because normal gameplay content
  is read-only.

The current model helpers mutate materialized rows; creating a new row uses the
typed insert builder or editor table workflow.

## Save-slot changes

A materialized save model remains associated with the database from which it
was loaded. After changing the active save slot, query the model again. Mutating
an object loaded from the previous slot returns a database-changed diagnostic
instead of writing to the new slot.

Successful model mutation commits runtime state. Call
`GDSQLRuntime.checkpoint_now()` when the game needs an explicit durable save;
the runtime node also applies its configured periodic, pause, and exit policies.

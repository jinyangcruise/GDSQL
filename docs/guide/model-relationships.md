# Model Relationships

## Same-database relationships

Define foreign keys in the table designer and register every participating
model. GDSQL derives both navigation directions from the catalog:

| Catalog constraint | Foreign-key model | Referenced model |
|---|---|---|
| `something.hero_id -> heroes.id` | `belongs_to hero` | `has_many something` |
| unique `hero_thing.hero_id -> heroes.id` | `belongs_to hero` | `has_one hero_thing` |

The generated user scaffold keeps the relationship method empty for these
models because no manual declarations are required:

```gdscript
func relationships() -> Array[GDSQLRelationshipDefinition]:
    return []
```

An explicit declaration is allowed, but its direction and keys must match the
catalog constraint. `belongs_to()` receives the foreign-key model's local
column, such as `hero_id`, not the referenced model's `id` column. Runtime model
registration validates executable declarations; the editor assistant does not
execute project-owned model methods.

Register all participating user-owned classes after the runtime starts:

```gdscript
var model_types: Array[Script] = [
    HeroContent,
    HeroThingContent,
    SomethingContent,
]
for model_type in model_types:
    var registered := GDSQLRuntime.register_model(model_type)
    if not registered.is_successful():
        registered.diagnostics.print_to_debug()
        return
```

## Micro demo

The relationship names shown by the Model Assistant can be passed to `with()`:

```gdscript
var result := HeroContent.query() \
        .with(&"hero_thing") \
        .with(&"something") \
        .find(1)
if not result.is_successful():
    result.diagnostics.print_to_debug()
    return

var hero := result.get_value() as HeroContent
var hero_thing := hero.get_related(&"hero_thing") as HeroThingContent
var related_rows: Array = hero.get_related(&"something")
var summary := {
    "hero": hero.name,
    "coins": 0 if hero_thing == null else hero_thing.coins,
    "related_count": related_rows.size(),
}
print(summary)
```

`with()` performs model-level eager loading. The returned hero stores the
loaded `has_one` model and `has_many` array under their relationship names.

## Many-to-many through a junction model

Create models for the source, target, and junction tables. Declare the
relationship only in the user-owned model that needs the navigation:

```gdscript
func relationships() -> Array[GDSQLRelationshipDefinition]:
    return [
        GDSQLRelationshipDefinition.many_to_many(
            &"tags",
            TagContent,
            HeroTagContent,
            &"hero_id", # HeroTagContent property pointing to this hero
            &"tag_id",  # HeroTagContent property pointing to TagContent
        ),
    ]
```

Register all three models. `HeroContent.query().with(&"tags")` then returns a
typed `Array[TagContent]` from `get_related(&"tags")`. The optional final two
arguments select non-default source and target identity properties; both default
to `id`. The junction is a normal model, so relationship-specific fields such as
unlock time or equipment slot remain directly queryable instead of being hidden.

## Explicit cross-role relationships

Catalog inference is limited to models in the same logical database role. A
save model that stores a content identifier declares only its own direction:

```gdscript
func relationships() -> Array[GDSQLRelationshipDefinition]:
    return [
        GDSQLRelationshipDefinition.references_one(
            &"hero",
            HeroContent,
            &"hero_id", # local save-model column
        ),
    ]
```

The third argument to `references_one()` is the local stable-identifier
property, not the content model's primary key. `belongs_to()` remains the
conventional name for a database relationship where the declaring row owns the
foreign-key column; `references_one()` avoids implying domain ownership across
runtime roles. Neither declaration creates a cross-database constraint or an
inverse relationship from content back to save data. See
[Content and Save Models](./content-save-models) for the complete role-separated
example and guidance for choosing a model role.

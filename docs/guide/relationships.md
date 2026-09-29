# Model relationships

Relationships provide model navigation. A database foreign key provides
same-database integrity. These concepts cooperate but are not interchangeable.

## Same-database inference

When both model types are registered, GDSQL infers navigation from catalog
foreign keys:

- the model containing the foreign-key column receives `belongs_to`;
- the referenced model receives `has_one` when that foreign key is unique;
- otherwise the referenced model receives `has_many`.

No relationship code is written into generated scripts for these edges. The
catalog remains authoritative and avoids circular script dependencies. The
Model Assistant previews the inferred relationships.

## Cross-role references

A save row that stores a stable content identifier uses `references_one()`:

```gdscript
func relationships() -> Array[GDSQLRelationshipDefinition]:
    return [
        GDSQLRelationshipDefinition.references_one(
            &"hero_content",
            HeroContent,
            &"hero_content_id",
        ),
    ]
```

This declaration says that the local identifier resolves through the target
model's role. It does not claim that mutable save state is owned by immutable
content, and it does not create an impossible cross-database foreign-key
constraint.

The Model Assistant can match compatible save identifiers to registered content
model primary keys, copy the declaration, and register the mapping used by the
table cell picker. Registered mappings can be removed without editing the model
script.

## Many-to-many navigation

Many-to-many navigation requires an ordinary junction table and a registered
junction model:

```gdscript
func relationships() -> Array[GDSQLRelationshipDefinition]:
    return [
        GDSQLRelationshipDefinition.many_to_many(
            &"tags",
            TagContent,
            HeroTagContent,
            &"hero_id",
            &"tag_id",
        ),
    ]
```

The junction table is persisted like any other table. GDSQL does not create it
implicitly from the model declaration.

## Load related values

Relationship values are loaded by their declared name through model queries.
All related model classes, including a many-to-many junction model, must be
registered before the relationship can be validated or eager-loaded.

```gdscript
var result := HeroContent.query().with(&"skills").find(hero_id)
if result.is_successful():
    var hero := result.get_value() as HeroContent
    var skills: Array = hero.get_related(&"skills")
```

Keep custom `belongs_to`, `has_one`, and `has_many` declarations only when the
catalog cannot express the intended navigation. An explicit declaration with
the same name takes precedence over an inferred relationship.

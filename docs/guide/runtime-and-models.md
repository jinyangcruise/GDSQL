# Runtime and models

The supported bootstrap path is the `GDSQLRuntime` autoload installed from the
Welcome checklist. It opens editor-authored database registrations, binds their
logical roles, configures persistence, and activates Managed Content when that
profile is selected.

## Logical roles

| Role | Model base | Intended data |
|---|---|---|
| `content` | `GDSQLContentModel` | Authored definitions, read-only during normal gameplay |
| `save` | `GDSQLSaveModel` | Mutable state owned by the active save slot |
| `settings` | `GDSQLSettingsModel` | Mutable state shared across save slots |

Game code depends on roles instead of physical paths. In Direct Content, the
`content` role resolves the authored database. In Managed Content, it resolves
the generated effective database.

## Generate a model binding

Select **Model** from a table or its data document. Enter a singular class name,
for example `HeroContent`, and keep models under a project-owned `res://`
folder. Generation creates two scripts:

```text
res://models/generated/hero_content_model_generated.gd
res://models/hero_content.gd
```

The generated base owns schema properties and table metadata. Regeneration may
replace it. The child script owns custom behavior and `relationships()`; GDSQL
creates that file once and preserves it.

Nullable scalar columns generate `Variant` because GDScript has no nullable
scalar type. Required scalar columns use their concrete type.

## Register and query models

Register user-owned model scripts after the runtime has started:

```gdscript
func _ready() -> void:
    if not GDSQLRuntime.is_started():
        var startup := GDSQLRuntime.get_start_result()
        if startup != null:
            startup.diagnostics.print_to_debug()
        return

    var registered := GDSQLRuntime.register_model(HeroContent)
    if not registered.is_successful():
        registered.diagnostics.print_to_debug()
        return

    var found := HeroContent.find(1)
    if found.is_successful():
        var hero := found.get_value() as HeroContent
        print(hero.name)
```

Every model participating in navigation must be registered. Registration checks
its role, table, properties, and relationships against the active catalogs.

## Save state and checkpoints

Committed save-model mutations update the active runtime save database. For the
standard in-memory save registration, durable ConfigFile data is updated at a
checkpoint, not on every model mutation.

The runtime node checkpoints dirty data periodically by default and may also
checkpoint on application pause and exit. Call
`GDSQLRuntime.checkpoint_now()` at explicit save points. Switching save slots
checkpoints the previous slot before changing the `save` role; a failed
checkpoint leaves the previous slot active.

Editor table changes and runtime save checkpoints are separate workflows. The
table workbench's **Save** commits its editor transaction; runtime checkpointing
persists committed in-memory game state.

Continue with the [Model API](./model-api) or use the lower-level
[Typed query API](./query-api) when a model is not the right boundary.

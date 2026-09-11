# Content and Save Models

This example keeps permanent item definitions in the `content` database and
player-owned quantities in the active `save` database:

```text
content.items                         save.inventory
id = &"iron_sword"  <--------------  item_id = &"iron_sword"
display_name = "Iron Sword"           quantity = 1
```

The save stores a stable content identifier. It does not copy the item
definition or its Resource references.

## Model files

The complete model scripts are available under
`examples/runtime/content_save_models/`. They use the same generated-base and
user-owned split produced by the model assistant:

```text
generated/content_item_model_generated.gd
content_item.gd
generated/inventory_entry_model_generated.gd
inventory_entry.gd
```

Register the user-owned classes after `GDSQLRuntimeNode` has started:

```gdscript
var item_registration := GDSQLRuntime.register_model(GDSQLExampleContentItem)
var inventory_registration := GDSQLRuntime.register_model(
    GDSQLExampleInventoryEntry,
)
```

Check both operation results before continuing.

## Look up authored content

`GDSQLExampleContentItem` extends `GDSQLContentModel`, so its query resolves the
database currently bound to the `content` role:

```gdscript
var result := GDSQLExampleContentItem.find(&"iron_sword")
if result.is_successful():
    var item := result.get_value() as GDSQLExampleContentItem
    print(item.display_name)
```

Content models are read-only. Change permanent definitions through the authored
content database rather than calling `save()` on a materialized content model.

## Resolve content from save data

The user-owned inventory model declares that its `item_id` belongs to the
content item model:

```gdscript
func relationships() -> Array[GDSQLRelationshipDefinition]:
    return [
        GDSQLRelationshipDefinition.belongs_to(
            &"item",
            GDSQLExampleContentItem,
            &"item_id",
        ),
    ]
```

Load inventory and its content definitions together:

```gdscript
var result := GDSQLExampleInventoryEntry.query().with(&"item").all()
if result.is_successful():
    for entry: GDSQLExampleInventoryEntry in result.get_value():
        var item := entry.get_related(&"item") as GDSQLExampleContentItem
        print("%s × %d" % [item.display_name, entry.quantity])
```

This is two role-scoped queries coordinated by the model layer, not a storage
join or a transaction spanning two databases. The relationship target declares
its own `content` role, so `belongs_to()` does not need a physical database path.

Character customization follows the same pattern: store stable identifiers for
base class, body type, or equipped definitions, and keep player-specific colors,
sliders, names, and choices in save-model columns.

## Change save slots

Switch through the runtime rather than changing registry bindings directly:

```gdscript
var selected := GDSQLRuntime.select_save_slot(&"save_2")
if selected.is_successful():
    var new_inventory := GDSQLExampleInventoryEntry.query() \
            .with(&"item") \
            .all()
```

The runtime checkpoints the previous in-memory slot before rebinding the
`save` role. Query fresh save models after the switch. An instance materialized
from the previous slot rejects `save()`, `refresh()`, and `delete()` so it cannot
write into the newly active database.

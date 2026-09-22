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

## Choosing where data belongs

A table owns stored schema and rows. A model adds typed behavior and selects a
logical database role; it does not create, own, or synchronize a second copy of
the table.

| Data responsibility | Place it in | Model base |
|---|---|---|
| Authored definitions shared by every player, such as classes, items, base statistics, dialogue, and asset references | Content database | `GDSQLContentModel` |
| Mutable state that belongs to one playthrough and must survive restarting the game, such as progression, inventory, customization, and quest choices | Active save database | `GDSQLSaveModel` |
| Mutable preferences shared across save slots, such as audio, controls, accessibility, and language | Settings database | `GDSQLSettingsModel` |
| Short-lived state that can be rebuilt, such as velocity, current animation, navigation targets, open menus, and temporary combat calculations | Scene nodes, resources, or other in-memory runtime objects | No database model by default |

Use content when the answer is part of the game definition. Use a save model
when the answer can differ by playthrough and must be restored later. Persisted
state refers to content through stable identifiers; it does not duplicate the
content row or its assets.

For a character, `HeroContent` can contain the base class, allowed body types,
default statistics, and visual definitions. `HeroSave` can contain the chosen
body type ID, colors, progression, and equipped item IDs. The live character
node still owns transient movement, animation, and combat state.

`GDSQLSaveModel` is intentionally not named `StateModel`. Save data is one
specific kind of state: mutable, slot-scoped, and durable. “State” also includes
large amounts of transient runtime information that should not automatically be
written to a database. In user-facing explanations, **saved state** is the
clearest description; the API name preserves the persistence boundary.

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

The user-owned inventory model declares that its `item_id` references the
content item model:

```gdscript
func relationships() -> Array[GDSQLRelationshipDefinition]:
    return [
        GDSQLRelationshipDefinition.references_one(
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
its own `content` role, so `references_one()` does not need a physical database
path. Unlike `belongs_to`, the name describes stable navigation without implying
domain ownership or an inverse content-to-save relationship.

For a generated save model, the Model Assistant exposes a **Save → content
reference** helper. Choose the local identifier and a compatible content-model
binding, then copy the generated `references_one()` entry into the user-owned
`relationships()` array. Only `int`, `String`, and `StringName` identifiers with
matching target primary-key types are offered. The helper never creates a
cross-database foreign key. Reference names use snake_case, such as
`item_content`; dots and display paths are not relationship names.

Character customization follows the same pattern: store stable identifiers for
base class, body type, or equipped definitions, and keep player-specific colors,
sliders, names, and choices in save-model columns.

## Preview content in an authored scene

Add
`res://addons/gdsql/editor/content_preview/gdsql_content_preview_adapter.tscn`
to a scene when an authored content definition should be visible without
running the game. In its Inspector:

1. Assign a user-owned script that extends `GDSQLContentModel`.
2. Enter the row's stable primary-key value.
3. Assign the `PackedScene` used as the visual preview.
4. Add `GDSQLContentPreviewBinding` resources. Each binding maps a model
   property to a property on the preview root or one of its child nodes.
5. Press **Refresh Content Preview**.

The Inspector values have these sources:

| Adapter field | Value to provide |
|---|---|
| Content Model | User-owned content model, such as `HeroContent` |
| Stable Identifier | Primary-key **value**, such as `1`; do not enter the column name `id` |
| Preview Scene | Visual scene to instantiate temporarily |
| Preview Host | Scene node that receives the temporary instance; the path is relative to the adapter |
| Binding → Model Property | Property from the content model, such as `name`, `health`, or `texture` |
| Binding → Target Node | Node inside the preview scene, relative to its root; use `.` for the root |
| Binding → Target Property | Type-compatible property on that target, such as `hero_name` or `texture` |

Bindings copy values directly and do not convert types. For example, map a
model `float` to a preview `float`, then let the preview tool script format that
value for a Label.

The Model Assistant now places `@tool` on both new generated bases and new
user-owned models because Godot otherwise creates placeholder instances in the
editor. For an older model, add `@tool` to both scripts or regenerate the base
and add it to the preserved user script. This does not query automatically;
model construction occurs only after pressing the preview's Refresh button.

The adapter uses the project's selected Direct or Managed profile. It rejects
save and settings models and releases its temporary model context after the
lookup. The preview scene is added as an internal node with no owner, so the
fetched values are not serialized into the authored scene. Press **Clear
Content Preview** to remove it. The Inspector status and node warning expose the
first structured diagnostic when setup, model registration, or row lookup
fails.

This is a content-definition preview, not a simulation of a running character.
Saved customization and transient animation, physics, combat, or AI state still
belong to their normal runtime owners.

The development-only `local/examples/ContentPreview/main.tscn` example previews
`HeroContent` id `1` in the editor. At runtime, its `main.gd` loads `HeroSave`
row `1` with `with(&"hero_content")` and shows that its `hero_content_id`
resolves to the same content model. It can move into the distributed examples
later if this workflow becomes part of the supported onboarding path.

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

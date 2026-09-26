# Create your first GDSQL project

This path creates a Direct Content project with authored definitions, one save
slot, a typed model, and the runtime adapter.

## 1. Choose Direct Content

Open the **GDSQL** main screen and select **Choose Direct Content**. Confirm the
choice after reading the migration warning. The welcome checklist now becomes
the authoritative setup sequence for this project.

## 2. Create the content database

Select **Create Content** or **Create Database**, choose **Direct content**, and
keep the defaults for the first project:

- Database name: `content`
- Data root: `res://data`
- Runtime storage: `ConfigFile`
- Runtime role: `content`

The registration name and physical database name are separate concepts, even
when both initially use `content`.

## 3. Create a table and its first row

Open the content database and add a table named `items`:

| Column | Type | Rules |
|---|---|---|
| `id` | `StringName` | Primary key, required |
| `display_name` | `String` | Required |
| `base_value` | `int` | Required, default `0` |

Save the schema, open the table data view, and add one row such as
`iron_sword`, `Iron Sword`, `100`. Row edits remain drafts until **Save
Changes** succeeds.

## 4. Create a save slot

Return to Welcome and select **Save Slots**. Create `save_1`. The standard save
path uses `user://gdsql/saves/save_1`, the in-memory runtime backend, and the
logical `save` role. Committed runtime changes are transferred to durable
ConfigFile storage at checkpoints.

## 5. Generate the content model

Open `content / items` and select **Model**. Use a singular class name such as
`ItemContent`; the model root defaults to `res://models`.

Generation creates:

```text
res://models/generated/item_content_model_generated.gd
res://models/item_content.gd
```

The generated base can be replaced when the table changes. GDSQL creates the
user model once and preserves its custom functions.

## 6. Install the runtime adapter

Use the welcome checklist's **Install Runtime** action. It installs
`gdsql_runtime_node.tscn` as the `GDSQLRuntime` autoload. Register the user-owned
model after startup:

```gdscript
func _ready() -> void:
    if not GDSQLRuntime.is_started():
        var startup := GDSQLRuntime.get_start_result()
        if startup != null:
            startup.diagnostics.print_to_debug()
        return

    var registered := GDSQLRuntime.register_model(ItemContent)
    if not registered.is_successful():
        registered.diagnostics.print_to_debug()
        return

    var found := ItemContent.find(&"iron_sword")
    if found.is_successful():
        var item := found.get_value() as ItemContent
        print(item.display_name)
```

The welcome checklist should now be complete. Continue with
[Runtime and models](./runtime-and-models) before adding inventory,
progression, or character customization.

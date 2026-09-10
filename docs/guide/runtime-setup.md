# Runtime Setup

The editor writes database registrations and `content`, `save`, or `settings`
role selections to `user://gdsql/databases.cfg`. Bootstrap that configuration
once when the game starts:

```gdscript
var runtime: GDSQLRuntimeSession

func _ready() -> void:
    var started := GDSQLRuntimeFactory.bootstrap()
    if not started.is_successful():
        started.diagnostics.print_to_debug()
        return
    runtime = started.get_value()
```

Resolve databases by purpose rather than physical path:

```gdscript
var content := runtime.database(GDSQLDatabaseRegistry.CONTENT_ROLE).get_database()
var save := runtime.database(GDSQLDatabaseRegistry.SAVE_ROLE).get_database()
```

Change to another registered save slot through the guarded session API. It
checkpoints the current in-memory slot before changing the `save` role:

```gdscript
var selected := runtime.select_save_slot(&"save_2")
if not selected.is_successful():
    selected.diagnostics.print_to_debug()
```

Queries made after the switch automatically resolve `GDSQLSaveModel` classes
against `save_2`. Discard model instances loaded from the previous slot and
query them again; stale instances reject persistence instead of writing their
state into the newly selected save.

Register user-owned model scripts through the same session:

```gdscript
runtime.register_model(Hero)
var hero := Hero.find(1).get_value()
```

An in-memory save registration commits into its working set first. Transfer its
committed dirty rows to ConfigFile at an explicit game checkpoint:

```gdscript
var checkpointed := runtime.checkpoint_save()
```

ConfigFile-backed registrations are already durable after commit, so their
explicit checkpoint result succeeds without an additional write. Call
`runtime.shutdown()` during teardown to release the session's default model
context.

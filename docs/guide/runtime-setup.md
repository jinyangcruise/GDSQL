# Runtime Setup

The editor writes database registrations and `content`, `save`, or `settings`
role selections to `user://gdsql/databases.cfg`.

For the plug-and-play path, add
`res://addons/gdsql/runtime/gdsql_runtime_node.tscn` as a project autoload named
`GDSQLRuntime`. It starts automatically, checkpoints dirty in-memory databases
every 30 seconds, and checkpoints again when the application pauses or the node
exits. These values are editable on the scene when a different policy is
needed.

Check startup before using a role:

```gdscript
func _ready() -> void:
    if not GDSQLRuntime.is_started():
        var result := GDSQLRuntime.get_start_result()
        if result != null:
            result.diagnostics.print_to_debug()
        return

    var content := GDSQLRuntime.database(GDSQLDatabaseRegistry.CONTENT_ROLE) \
            .get_database()
    var save := GDSQLRuntime.database(GDSQLDatabaseRegistry.SAVE_ROLE) \
            .get_database()
```

The scene can also be added below a game-owned Node. Connect
`runtime_start_failed`, `checkpoint_finished`, or `runtime_stopped` when the
game needs save indicators, retries, or custom error presentation. The returned
operation results remain authoritative.

For code-owned composition without a scene tree, bootstrap the same
configuration directly:

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
context. When using `GDSQLRuntimeNode`, `checkpoint_now()` performs an explicit
dirty checkpoint and `stop()` checkpoints before releasing the session.

Continue with [Content and Save Models](./content-save-models) for the complete
role-separated model and save-slot example.

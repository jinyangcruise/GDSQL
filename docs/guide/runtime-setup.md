# Runtime Setup

The editor writes database registrations and `content`, `save`, or `settings`
role selections to `user://gdsql/databases.cfg`.

For the plug-and-play path, add
`res://addons/gdsql/runtime/gdsql_runtime_node.tscn` as a project autoload named
`GDSQLRuntime`. It starts automatically, checkpoints dirty in-memory databases
every 30 seconds, and checkpoints again when the application pauses or the node
exits. These values are editable on the scene when a different policy is
needed. The welcome checklist can install this autoload after the content and
save roles are configured.

When the selected profile is Managed Content, the autoload reads the package
roots and enabled IDs saved by the Managed Content document, resolves their
load order, rebuilds or reuses the cache, and binds `effective_content` to the
`content` role before emitting `runtime_started`. Inspect
`get_content_activation_result()` or connect `content_activation_finished` for
cache and package diagnostics. A failed activation does not expose a partial
runtime session.

Managed startup also compares the active save's recorded package set with the
active cache. Read `get_save_content_compatibility_report()` from
`runtime_started`, or connect `save_content_compatibility_checked`. A report
that requires a policy decision does not fail startup:

```gdscript
func _on_runtime_started(_runtime: GDSQLRuntimeSession) -> void:
    var report := GDSQLRuntime.get_save_content_compatibility_report()
    if report != null and report.requires_policy_decision():
        open_save_compatibility_dialog(report)
        return
    load_active_save()
```

The same report is refreshed after `select_save_slot()` succeeds. The game may
refuse the save, request packages, apply a fallback, or continue; GDSQL does not
choose among those policies.

Startup diagnostics include warnings when the direct profile is incomplete or
uses unsafe roots. Warnings preserve successful startup for projects that use
custom roles; errors still prevent a partial runtime session.

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

For code-owned direct-profile composition without a scene tree, bootstrap the
registry directly. Managed code-owned compositions can use
`activate_managed_content()` with their own discovery and cache services; the
autoload remains the supported plug-and-play composition root.

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

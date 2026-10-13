# Godot-AI tools

GDSQL can optionally register project inspection and bounded data-authoring
tools with the Godot-AI addon. GDSQL still loads normally when Godot-AI is
absent.

## Available tools

| Tool | Purpose |
|---|---|
| `gdsql_capabilities` | Reports the GDSQL inspection version, limits, and available features. |
| `gdsql_inspect_setup` | Reports Direct or Managed Content checklist readiness. |
| `gdsql_inspect_schema` | Lists registrations and tables or describes one table's columns and constraints. |
| `gdsql_inspect_models` | Lists model bindings or reports static compatibility and relationships for one binding. |
| `gdsql_query_rows` | Reads a bounded page of scalar row values using typed structured filters. |
| `gdsql_preview_row_mutation` | Validates up to 100 scalar inserts, updates, or deletes and returns a confirmation handle without writing. |
| `gdsql_commit_row_mutation` | Atomically commits one unchanged preview after explicit confirmation. |
| `gdsql_preview_schema_mutation` | Validates registered table creation, rename, drop, or typed alteration without writing. |
| `gdsql_commit_schema_mutation` | Applies one unchanged canonical table-schema preview. |
| `gdsql_preview_database_mutation` | Validates registered database create, rename, unregister, or destroy and reports its impact. |
| `gdsql_commit_database_mutation` | Applies one unchanged database lifecycle preview after explicit confirmation. |

Godot-AI normally exposes promoted tools with a `custom_` prefix. Enable or
disable them for the current project from Godot-AI's **Tools** panel.

## Safety boundary

Row reads and mutations are limited to registered tables and JSON-safe scalar
columns. Resource contents, arbitrary files, and host paths are never returned.
The integration does not instantiate user models, call user-owned
`relationships()` methods, control editor UI, or accept SQL text.

Every mutation is split into preview and commit. Preview changes nothing and
returns a one-use handle valid for two minutes. Commit requires `confirm: true`
and rejects the handle if its target changed. Database creation uses named
GDSQL locations, never arbitrary paths. Unregister preserves database files;
destroy removes them. The tools are not integrated with Godot Undo/Redo.

Model inspection covers catalog-inferred foreign-key relationships and
cross-role references registered through the Model Assistant. Explicit
many-to-many or other custom code remains outside static inspection.

The MCP transport, connection, discovery, and per-project enablement are owned
by Godot-AI. GDSQL owns its versioned domain results and mutation safeguards.

## Current scope and later extensions

The current `1.0.0` surface has eleven tools. Migration operations are next.
Model generation, profile/package/save-slot
management, and typed Resource locators follow as separate guarded families.
Late startup, registry replacement, repeated readiness, contract loss, and
teardown are covered by lifecycle tests. Live disable/re-enable and reload
still need a final Tools-panel acceptance pass with Godot-AI installed.

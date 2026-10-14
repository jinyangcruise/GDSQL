# Godot-AI tools

GDSQL can optionally register project inspection and bounded data-authoring
tools with the Godot-AI addon. GDSQL still loads normally when Godot-AI is
absent.

## Available tools

| Tool | Purpose |
|---|---|
| `gdsql_capabilities` | Reports the GDSQL version, limits, available features, and required onboarding action. |
| `gdsql_inspect_setup` | Reports setup readiness and, before initial selection, the Direct/Managed decision the agent must present to the user. |
| `gdsql_inspect_schema` | Lists registrations and tables or describes one table's columns and constraints. |
| `gdsql_inspect_models` | Lists model bindings or reports static compatibility and relationships for one binding. |
| `gdsql_query_rows` | Reads a bounded page of scalar row values using typed structured filters. |
| `gdsql_preview_row_mutation` | Validates up to 100 scalar inserts, updates, or deletes and returns a confirmation handle without writing. |
| `gdsql_commit_row_mutation` | Atomically commits one unchanged preview after explicit confirmation. |
| `gdsql_preview_schema_mutation` | Validates registered table creation, rename, drop, or typed alteration without writing. |
| `gdsql_commit_schema_mutation` | Applies one unchanged canonical table-schema preview. |
| `gdsql_preview_database_mutation` | Validates registered database create, rename, unregister, or destroy and reports its impact. |
| `gdsql_commit_database_mutation` | Applies one unchanged database lifecycle preview after explicit confirmation. |
| `gdsql_preview_migration` | Previews the next pending migration or validates a new ordered schema/data migration. |
| `gdsql_commit_migration` | Persists when needed and applies one unchanged migration preview. |
| `gdsql_preview_model_mutation` | Previews model generation or save-to-content reference registration/removal. |
| `gdsql_commit_model_mutation` | Generates sources or changes one unchanged cross-role reference after confirmation. |
| `gdsql_preview_setup_mutation` | Previews profile, role, runtime-adapter, save-slot, or Managed Content package/cache/save setup. |
| `gdsql_commit_setup_mutation` | Commits one unchanged profile, role-binding, or runtime-adapter preview. |

Godot-AI normally exposes promoted tools with a `custom_` prefix. Enable or
disable them for the current project from Godot-AI's **Tools** panel.

For a new project, ask the agent to inspect GDSQL setup. If no content profile
is selected, the result requires the agent to explain both options and obtain
an explicit choice before it previews any setup mutation.

## Safety boundary

Row reads and mutations are limited to registered tables and JSON-safe scalar
columns. Resource contents, arbitrary files, and host paths are never returned.
Model generation writes only generator-derived project paths under `res://`; it
replaces the generated base and preserves an existing user-owned model script.
The integration does not instantiate user models, call user-owned
`relationships()` methods, control editor UI, or accept SQL text.

Every mutation is split into preview and commit. Preview changes nothing and
returns a one-use handle valid for two minutes. Commit requires `confirm: true`
and rejects the handle if its target changed. Database creation uses named
GDSQL locations, never arbitrary paths. Unregister preserves database files;
destroy removes them. The tools are not integrated with Godot Undo/Redo.

Database and save-slot previews also explain storage policy. Omitting the
backend selects durable ConfigFile storage. In-memory storage hydrates from the
durable source at startup and requires periodic, pause, exit, or explicit
checkpoints before changes become durable.

Schema previews require an explicit storage mode for every Resource column and
return its decision context. Prefer `referenced` for existing meshes, textures,
audio, scenes, and other shared assets. Use `owned` only when the complete
Resource is independent row data. Referenced storage keeps the table compact,
but loading is eager when the Resource is projected unless the runtime query
explicitly requests deferred Resources.

Model inspection covers catalog-inferred foreign-key relationships and
cross-role references registered through the Model Assistant. Explicit
many-to-many or other custom code remains outside static inspection.

The MCP transport, connection, discovery, and per-project enablement are owned
by Godot-AI. GDSQL owns its versioned domain results and mutation safeguards.

## Current scope and later extensions

The current `1.0.0` surface has seventeen tools. Package/cache and save-slot
lifecycle management, plus typed Resource locators, remain separate guarded families.
Late startup, registry replacement, repeated readiness, contract loss, and
teardown are covered by lifecycle tests. Live disable/re-enable and reload
still need a final Tools-panel acceptance pass with Godot-AI installed.

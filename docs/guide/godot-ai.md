# Godot-AI tools

GDSQL can optionally register read-only project inspection tools with the
Godot-AI addon. GDSQL still loads normally when Godot-AI is absent.

## Available tools

| Tool | Purpose |
|---|---|
| `gdsql_capabilities` | Reports the GDSQL inspection version, limits, and available features. |
| `gdsql_inspect_setup` | Reports Direct or Managed Content checklist readiness. |
| `gdsql_inspect_schema` | Lists registrations and tables or describes one table's columns and constraints. |
| `gdsql_inspect_models` | Lists model bindings or reports static compatibility and relationships for one binding. |

Godot-AI normally exposes promoted tools with a `custom_` prefix. Enable or
disable them for the current project from Godot-AI's **Tools** panel.

## Safety boundary

The current integration does not return table row values, Resource contents,
arbitrary files, or host paths. It does not execute queries, mutate the project,
instantiate user models, or call user-owned `relationships()` methods.

Model inspection covers catalog-inferred foreign-key relationships and
cross-role references registered through the Model Assistant. Explicit
many-to-many or other custom code remains outside static inspection.

The MCP transport, connection, discovery, and per-project enablement are owned
by Godot-AI. GDSQL owns only its versioned inspection results.

## Current scope and later extensions

The four inspection tools are the complete `1.0.0` read-only surface. Remaining
work for this version is editor lifecycle verification: reload, disable, and
teardown behavior with Godot-AI installed.

Structured query drafting may follow after the inspection contract is stable.
Query execution and mutations require separate bounded contracts; mutations
must preview their exact effect and require an explicit confirmation handle.
They are not part of the current tool set.

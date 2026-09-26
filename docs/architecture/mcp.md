# GDSQL MCP Architecture

## Status and purpose

This document defines the implemented first GDSQL-aware Model Context Protocol
surface. The first delivery is read-only and editor-only: it lets an
agent understand the current project's setup and database schemas without
reading table rows, opening arbitrary files, or controlling editor UI.

GDSQL does not implement an MCP transport. The installed Godot-AI plugin owns
transport, protocol-version handling, client connectivity, tool discovery, and
tool dispatch. GDSQL optionally registers domain tools through Godot-AI's custom
tool registry.

The GDSQL plugin must continue to load and function when Godot-AI is absent.

## Boundary and dependency direction

```text
MCP client
    -> Godot-AI transport and custom-tool registry
    -> GDSQL MCP adapter
    -> GDSQL MCP inspection service
    -> Workbench inspections / setup inspectors / catalog definitions
```

The adapter is an editor composition boundary. It may translate JSON-compatible
arguments and results, but it must not:

- Access editor `Control` nodes or simulate user interaction.
- Read `ConfigFile` sections or construct storage paths.
- Execute SQL text or bypass `QuerySpec` for query operations.
- Return Godot objects, scripts, live resources, or mutable domain instances.
- Become a required dependency of runtime, catalog, query, or storage code.

The inspection service owns deterministic domain projection. It consumes typed
state supplied by existing GDSQL services and returns JSON-compatible data plus
structured diagnostics. The Godot-AI adapter owns only optional registration,
request validation, and transport-envelope translation.

## Project scope

The surface is restricted to the project open in the Godot editor and to
databases already registered with GDSQL.

Phase-one inspection may expose:

- Selected setup profile and ordered readiness checks.
- Logical registration names, database names, roles, and storage backend IDs.
- Project-relative `res://` or logical `user://` roots when useful for setup
  diagnosis; never expanded host paths.
- Table names, readiness, row counts from storage headers, column definitions,
  primary and secondary indexes, and foreign-key definitions.
- Persisted model bindings, static compatibility, catalog-inferred relationships,
  and registered cross-role content references.
- Stable GDSQL diagnostic codes, severities, messages, and bounded context.

Phase one does not expose:

- Table row values or query results.
- Resource contents, imported artifacts, binary blobs, or previews.
- User script source or relationships that require executing user model code.
- Arbitrary filesystem paths or files outside registered GDSQL roots.
- Credentials, environment variables, editor metadata owned by other plugins,
  or connection details.
- Mutations, query execution, project execution, or editor navigation.

## Version and capability negotiation

Godot-AI owns MCP protocol negotiation. GDSQL must not reproduce transport
capability logic or infer authorization from client or server display metadata.

GDSQL owns an independent `surface_version` for its tool and result contract.
The initial implementation started at `1.0.0`; model inspection extends the
current surface to `1.1.0`. Every successful GDSQL response
includes this version. Compatibility rules are:

- Patch: diagnostic text or additive implementation fixes without shape changes.
- Minor: additive fields, capabilities, enum values, or optional parameters.
- Major: removed or renamed fields, changed meanings, or tighter required input.

Clients discover the supported contract through `gdsql_capabilities`; they do
not assume support from the plugin version. The response includes tool names,
feature flags, limits, mutation availability, and the currently selected setup
profile. Capability entries are sorted by stable identifier.

## Read-only tools

All four tools are promoted through Godot-AI. Compatible MCP clients normally
see them as `custom_gdsql_*`; they remain available through `custom_manage` if a
bridge promotion limit is reached. The promotion prefix is a bridge detail and
is not part of the GDSQL surface version.

| Tool | Input | Result |
|---|---|---|
| `gdsql_capabilities` | Empty object | Surface version, project scope, supported features, limits, and tool inventory. |
| `gdsql_inspect_setup` | Optional `profile`: `selected`, `direct`, or `managed` | Selected profile, readiness, ordered checks, next semantic action, and diagnostics. |
| `gdsql_inspect_schema` | Optional `registration`, `table`, `cursor`, and bounded `limit` | Registration summaries, table summaries, or one full table definition. |
| `gdsql_inspect_models` | Optional `registration`, `table`, `cursor`, and bounded `limit` | Binding summaries or one binding's static compatibility, inferred relationships, and registered cross-role references. |

Input schemas reject unknown fields. Registration and table parameters are
logical identifiers, never paths. Lists use opaque cursors and bounded limits;
the default and maximum limits are declared by `gdsql_capabilities`.

`gdsql_inspect_setup` reporting an incomplete project is a successful
inspection, not a tool failure. Missing requested identifiers, malformed input,
or an unavailable inspection service are failures.

`gdsql_inspect_models` never instantiates a user model or calls
`relationships()`. It reports same-database relationships inferred from catalog
foreign keys and cross-role references registered by the editor. Explicit
many-to-many or custom relationships remain marked as not statically inspected.

All tools are read-only, idempotent, and closed to external systems. The adapter
sets the equivalent tool annotations when the active bridge supports them;
annotations are descriptive and do not replace enforcement in GDSQL.

## Godot-AI discovery

Godot-AI exposes enabled addon tools through `custom_manage` and its
`godot://custom-tools` resource. GDSQL therefore does not implement another MCP
transport or a GDSQL-specific resource namespace. Users enable or disable the
tools from Godot-AI's per-project Tools panel.

Native `gdsql://` resources are not part of the active roadmap. They should be
reconsidered only if a supported addon resource registry provides a concrete
workflow that the inspection tools and Godot-AI discovery cannot serve.

## Response and diagnostic contract

Successful adapter calls return their payload under Godot-AI's normal `data`
field. The GDSQL payload has this stable envelope:

```json
{
  "surface_version": "1.1.0",
  "ok": true,
  "data": {},
  "diagnostics": [],
  "meta": {
    "scope": "current_project",
    "truncated": false,
    "next_cursor": ""
  }
}
```

Each diagnostic contains:

```json
{
  "code": "GDSQL_SETUP_CONTENT_DATABASE",
  "severity": "warning",
  "message": "...",
  "context": {}
}
```

Diagnostic codes and severities are stable machine-facing fields. Messages are
human-facing and may improve without a surface-version change. Context is
optional, bounded, JSON-compatible, and must not contain row values or absolute
paths.

Completed inspections use `ok: true`, including setup reports with readiness
warnings. Invalid parameters, unknown logical identifiers, an unavailable
inspection service, and unexpected implementation failures use Godot-AI's
standard tool error envelope. Ordinary readiness warnings are never printed or
pushed as engine errors.

Results are deterministic: registrations, tables, columns, constraints,
checks, capabilities, and diagnostics have explicit stable ordering. Output is
bounded before serialization.

## Future query surface

Query drafting follows schema inspection and remains separate from execution.
A future draft tool may translate structured MCP input into a canonical
`QuerySpec` preview and return validation diagnostics. It must not accept raw
SQL as a privileged escape hatch.

Query execution is a separate future capability with explicit projection,
pagination, row and byte limits, and Resource-safe serialization. Read-only
SELECT execution is not implied by phase-one schema access.

## Future mutation confirmation

No mutation tool is included in phase one. Future editor or data mutations use
a two-step contract:

1. A preview call validates the requested action and returns its exact targets,
   expected effects, diagnostics, and an opaque confirmation handle.
2. A commit call requires the handle and an explicit confirmation value.

Confirmation handles are one-use, short-lived, stored only in editor memory,
and bound to the project, action, normalized arguments, and relevant catalog
fingerprint. They become invalid after use, expiry, plugin reload, editor
restart, or a conflicting catalog change. The caller must carry the handle
between calls; no hidden MCP connection state is authoritative.

The host must still present the operation to the user. A handle proves that the
same validated preview is being committed; it does not prove human consent.

Mutation adapters additionally:

- Declare Godot-AI `requires_writable` and accurate MCP risk annotations.
- Use GDSQL application services and canonical queries, never Controls or raw
  storage edits.
- Refuse arbitrary paths and unregistered databases.
- Report whether an operation actually participates in Godot Undo/Redo; they do
  not claim `undoable` merely because GDSQL has session row history.
- Keep destructive database, table, schema, and bulk-row actions behind preview
  plus confirmation even when a client requests batch execution.

## Registration lifecycle

The optional adapter dynamically resolves Godot-AI, registers all phase-one
specs atomically when both plugins are ready, and polls briefly so plugin load
order is irrelevant. It re-registers after Godot-AI emits `registry_ready` and
unregisters the GDSQL `plugin.cfg` source during teardown. Registration is
idempotent and uses GDSQL-owned names.

The adapter must resolve the Godot-AI integration dynamically at the editor
composition boundary so installing GDSQL alone does not create parser errors.
Handler scripts receive their inspection service through a GDSQL-owned
composition mechanism; they do not locate editor controls or construct concrete
ConfigFile services.

## Delivery slices

| Slice | State |
|---|---|
| Pure inspection projector and JSON contract tests | Tested |
| Optional Godot-AI handler, promoted specs, registration, and teardown | Implemented; specification contract tested |
| Live editor discovery, registration, and Tools-panel acceptance | Verified with Godot-AI |
| Live reload, disable, and teardown verification | Pending manual verification |
| Bounded model-binding and relationship inspection | Tested |
| Structured query drafting | Planned after the inspection contract is stable |
| Preview-and-confirm mutation families | Planned separately |

## Protocol references

- [MCP 2026-07-28 overview](https://modelcontextprotocol.io/specification/2026-07-28/basic)
- [MCP tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools)
- [MCP resources](https://modelcontextprotocol.io/specification/2026-07-28/server/resources)
- [Godot-AI custom tools](https://github.com/hi-godot/godot-ai/blob/main/docs/plugin-architecture.md#custom-tools-third-party-addons)
- [Godot-AI community addons](https://github.com/hi-godot/godot-ai/blob/main/docs/community-addons.md)

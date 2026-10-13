# GDSQL MCP Architecture

## Status and purpose

This document defines the editor-only GDSQL-aware Model Context Protocol
surface. Agents can inspect setup, schemas, and models; query bounded scalar
rows; and preview then commit bounded scalar row mutations. The integration
does not open arbitrary files or control editor UI.

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
    -> GDSQL MCP inspection or authoring service
    -> Workbench / canonical QuerySpec / EditorRowBatch
```

The adapter is an editor composition boundary. It may translate JSON-compatible
arguments and results, but it must not:

- Access editor `Control` nodes or simulate user interaction.
- Read `ConfigFile` sections or construct storage paths.
- Execute SQL text or bypass `QuerySpec` for query operations.
- Return Godot objects, scripts, live resources, or mutable domain instances.
- Become a required dependency of runtime, catalog, query, or storage code.

The inspection service owns deterministic domain projection. The authoring
service translates structured input into canonical queries and reuses the
atomic editor row-batch boundary. Both return JSON-compatible data and
structured diagnostics. The Godot-AI adapter owns only optional registration,
request validation, and transport-envelope translation.

## Project scope

The surface is restricted to the project open in the Godot editor and to
databases already registered with GDSQL.

Inspection may expose:

- Selected setup profile and ordered readiness checks.
- Logical registration names, database names, roles, and storage backend IDs.
- Project-relative `res://` or logical `user://` roots when useful for setup
  diagnosis; never expanded host paths.
- Table names, readiness, row counts from storage headers, column definitions,
  primary and secondary indexes, and foreign-key definitions.
- Persisted model bindings, static compatibility, catalog-inferred relationships,
  and registered cross-role content references.
- Stable GDSQL diagnostic codes, severities, messages, and bounded context.

Bounded row queries additionally expose scalar `bool`, `int`, `float`, `String`,
and `StringName` values from explicitly registered tables. They do not expose:

- Resource contents, imported artifacts, binary blobs, or previews.
- User script source or relationships that require executing user model code.
- Arbitrary filesystem paths or files outside registered GDSQL roots.
- Credentials, environment variables, editor metadata owned by other plugins,
  or connection details.
- Project execution, editor navigation, or mutation of Resource-valued fields.

## Version and capability negotiation

Godot-AI owns MCP protocol negotiation. GDSQL must not reproduce transport
capability logic or infer authorization from client or server display metadata.

GDSQL owns an independent `surface_version` for its tool and result contract.
The unpublished surface remains at `1.0.0`, including model inspection. Every
successful GDSQL response includes this version. Compatibility rules are:

- Patch: diagnostic text or additive implementation fixes without shape changes.
- Minor: additive fields, capabilities, enum values, or optional parameters.
- Major: removed or renamed fields, changed meanings, or tighter required input.

Clients discover the supported contract through `gdsql_capabilities`; they do
not assume support from the plugin version. The response includes tool names,
feature flags, limits, mutation availability, and the currently selected setup
profile. Capability entries are sorted by stable identifier.

## Tools

All seven tools are promoted through Godot-AI. Compatible MCP clients normally
see them as `custom_gdsql_*`; they remain available through `custom_manage` if a
bridge promotion limit is reached. The promotion prefix is a bridge detail and
is not part of the GDSQL surface version.

| Tool | Input | Result |
|---|---|---|
| `gdsql_capabilities` | Empty object | Surface version, project scope, supported features, limits, and tool inventory. |
| `gdsql_inspect_setup` | Optional `profile`: `selected`, `direct`, or `managed` | Selected profile, readiness, ordered checks, next semantic action, and diagnostics. |
| `gdsql_inspect_schema` | Optional `registration`, `table`, `cursor`, and bounded `limit` | Registration summaries, table summaries, or one full table definition. |
| `gdsql_inspect_models` | Optional `registration`, `table`, `cursor`, and bounded `limit` | Binding summaries or one binding's static compatibility, inferred relationships, and registered cross-role references. |
| `gdsql_query_rows` | Registration, table, optional scalar columns, structured `where`, ordering, cursor, and bounded limit | A deterministic scalar row window and opaque next cursor. |
| `gdsql_preview_row_mutation` | Operation, registration, table, and at most 100 scalar row changes or primary keys | Validated target summary and a short-lived one-use confirmation handle; no write occurs. |
| `gdsql_commit_row_mutation` | Confirmation handle and explicit `confirm: true` | Atomic commit summary after schema and target-row conflict checks. |

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

The first five tools are read-only. Both mutation tools declare Godot-AI
`requires_writable`; neither claims Godot Undo/Redo support. Adapter annotations
are descriptive and do not replace validation and confirmation in GDSQL.

## Structured row query

`gdsql_query_rows` accepts structured predicates rather than SQL. Leaf
operators are `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `is_null`, and
`is_not_null`; groups are `and`, `or`, and `not`. Nesting, condition count,
ordering, and result size are bounded. The primary key is appended as a stable
ordering tie-breaker. Cursors are bound to the normalized registration, table,
projection, predicate, and ordering and cannot be reused with another query.

Resource and other compound columns are omitted from default projections and
rejected when explicitly requested. A later Resource surface must use typed
locators and explicit materialization rather than JSON-serializing live Godot
objects.

## Row mutation confirmation

Scalar inserts, updates, and deletes use two calls:

1. Preview validates at most 100 changes through `EditorRowBatch`, prepares the
   canonical queries, fingerprints the schema and existing update/delete
   targets, and returns a handle without writing.
2. Commit requires the same handle and `confirm: true`, rechecks the
   fingerprints, and executes the batch in one database transaction.

Handles expire after two minutes, are one-use, and exist only in editor memory.
Plugin reload or editor restart invalidates them. A schema or target-row change
after preview produces `GDSQL_MCP_MUTATION_STALE`; the agent must preview again.

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
  "surface_version": "1.0.0",
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
optional, bounded, JSON-compatible, and must not contain absolute host paths.

Completed inspections use `ok: true`, including setup reports with readiness
warnings. Invalid parameters, unknown logical identifiers, an unavailable
inspection service, and unexpected implementation failures use Godot-AI's
standard tool error envelope. Ordinary readiness warnings are never printed or
pushed as engine errors.

Results are deterministic: registrations, tables, columns, constraints,
checks, capabilities, and diagnostics have explicit stable ordering. Output is
bounded before serialization.

## Mutation rules for later families

Schema, database, migration, setup, and model-generation mutations must retain
the row surface's preview/commit pattern. The host must still present the
operation to the user: a handle proves that the validated preview is being
committed, not that a person consented. Mutation adapters additionally:

- Declare Godot-AI `requires_writable` and accurate MCP risk annotations.
- Use GDSQL application services and canonical queries, never Controls or raw
  storage edits.
- Refuse arbitrary paths and unregistered databases.
- Report whether an operation actually participates in Godot Undo/Redo; they do
  not claim `undoable` merely because GDSQL has session row history.
- Keep destructive database, table, schema, and bulk-row actions behind preview
  plus confirmation even when a client requests batch execution.

The mutation boundary is a UI-independent application service. Godot-AI MCP is
one JSON adapter over that service; a future CLI may reuse it for headless or CI
work. The editor action hub remains a presentation and navigation layer and is
not a domain-mutation API.

Prefer a small set of composable operation families over one tool per editor
button:

- bounded structured SELECT execution;
- row mutation preview and commit, including bounded batch inserts (implemented);
- schema/database mutation preview and commit; and
- migration authoring, preview, and application.

Requests use logical registration, database, table, and column identifiers plus
typed JSON values. Responses use stable diagnostics, bounded result windows,
and opaque cursors or confirmation handles so agents do not need to consume UI
state or raw catalog files.

## Registration lifecycle

The optional adapter dynamically resolves Godot-AI, registers all current
specs atomically when both plugins are ready, and polls briefly so plugin load
order is irrelevant. It re-registers after Godot-AI emits `registry_ready` and
unregisters the GDSQL `plugin.cfg` source during teardown. When Godot-AI
replaces its registry during reload, GDSQL disconnects and unregisters from the
old instance before adopting the replacement. Contract disappearance follows
the same cleanup path. Repeated polling of one ready registry is idempotent;
another `registry_ready` signal intentionally replaces same-source specs.

The adapter must resolve the Godot-AI integration dynamically at the editor
composition boundary so installing GDSQL alone does not create parser errors.
Handler scripts receive their inspection service through a GDSQL-owned
composition mechanism; they do not locate editor controls or construct concrete
ConfigFile services.

## Editor capability coverage

| Editor capability | Agent surface | State |
|---|---|---|
| Setup, registration, schema, constraint, and model-binding inspection | Four inspection tools | Tested |
| Typed WHERE, scalar SELECT, ordering, and pagination | `gdsql_query_rows` | Tested |
| Scalar insert, update, and delete | Preview/commit row mutation | Tested |
| Database/table/column/index/foreign-key authoring | Schema mutation family | Planned next |
| Migration authoring, preview, apply, recovery status | Migration family | Planned after schema authoring |
| Model generation and cross-role content-reference registration | Model binding family | Planned |
| Direct/Managed profile setup, packages, cache, and save-slot management | Setup family with destructive guards | Planned |
| Resource-valued query and mutation | Typed locator/materialization family | Planned; scalar surface rejects it |
| Open editor documents, focus scripts, or run the project | Navigation commands only when useful | Backlog; never implemented by simulating UI input |

## Delivery slices

| Slice | State |
|---|---|
| Pure inspection projector and JSON contract tests | Tested |
| Optional Godot-AI handler, promoted specs, registration, and teardown | Tested |
| Live editor discovery, registration, and Tools-panel acceptance | Verified with Godot-AI |
| Late startup, registry reload/replacement, contract loss, and teardown transitions | Tested with deterministic registry lifecycle doubles |
| Live disable/re-enable and reload acceptance in the Tools panel | Pending manual verification |
| Bounded model-binding and relationship inspection | Tested |
| Bounded structured scalar SELECT execution | Tested |
| Scalar row mutation preview and commit | Tested |
| Schema/database preview and commit | Planned next |
| Migration preview and commit | Planned after schema/database authoring |
| Optional CLI adapter over the same application service | Backlog; not required for Godot-AI |

## Protocol references

- [MCP 2026-07-28 overview](https://modelcontextprotocol.io/specification/2026-07-28/basic)
- [MCP tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools)
- [MCP resources](https://modelcontextprotocol.io/specification/2026-07-28/server/resources)
- [Godot-AI custom tools](https://github.com/hi-godot/godot-ai/blob/main/docs/plugin-architecture.md#custom-tools-third-party-addons)
- [Godot-AI community addons](https://github.com/hi-godot/godot-ai/blob/main/docs/community-addons.md)

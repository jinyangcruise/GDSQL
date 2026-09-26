# Architecture overview

GDSQL is one data system with several ways to use it. The table editor, typed
GDScript builders, generated models, query graph, and optional agent tools do
not implement separate databases. They translate user intent into shared
services and structured results.

## The complete path

```text
Editor tables · Model API · Typed builders · Other frontends
                           │
                           ▼
                 Canonical QuerySpec
                           │
                           ▼
               Validate names and types
                           │
                           ▼
                  Build a query plan
                           │
                           ▼
             Execute through transactions
                           │
                           ▼
             Catalog and storage contracts
                           │
                           ▼
        ConfigFile or another compatible backend
                           │
                           ▼
             Rows, statistics, diagnostics
```

Every frontend reaches the same validation, planning, execution, and storage
rules. A feature added to the common pipeline therefore benefits editor and
runtime consumers without duplicating behavior.

## Five structural ideas

### 1. Tables own structure

The catalog defines databases, tables, columns, indexes, Resource constraints,
and same-database foreign keys. It is the schema authority.

Generated models reflect a table into typed GDScript. Regenerating a model does
not create or migrate that table. User-owned child scripts preserve game
behavior while the replaceable generated base follows schema changes.

### 2. Queries are descriptions before they are actions

The editor and public APIs build a `QuerySpec`: typed descriptive data for a
select, insert, update, or delete. A query object does not read files or mutate
rows by itself.

Validation resolves tables, columns, expressions, types, and constraints. A
planner then creates executable operations, and the executor applies them
through storage contracts. This keeps syntax, UI, and physical storage outside
the query meaning.

### 3. Runtime code uses roles

Game code normally asks for a logical role instead of a path:

```text
content  → authored definitions or generated effective content
save     → the currently selected save slot
settings → state shared across save slots
```

The runtime registry binds each role to an opened database registration. Models
declare a role and table; they do not construct `res://` or `user://` paths.
Changing a save slot or activating Managed Content replaces a role binding
through the runtime composition layer.

### 4. Content and state have different lifecycles

Content models represent definitions shipped with the game and are read-only
during ordinary gameplay. Save and settings models represent mutable state.

Direct Content binds authored project data to the `content` role. Managed
Content composes a base package with enabled DLC or mods, builds a disposable
effective cache, then binds that cache to the same role. Normal content queries
remain unchanged.

Save rows reference content through stable identifiers and model navigation.
GDSQL does not create foreign-key constraints across independently stored
databases.

### 5. Persistence is explicit

A transaction decides whether a set of row changes commits atomically. A
checkpoint decides when committed in-memory state is copied to durable storage.
These are separate operations.

The default runtime node can checkpoint periodically, on pause, on exit, or on
an explicit game save. Editor table edits use the same canonical mutation and
transaction rules but operate through the authoring workflow.

## Editor architecture

Editor Controls display state and collect intent. Workbench and controller
services open registrations, inspect catalogs, construct queries, apply schema
plans, and report diagnostics. Controls do not edit ConfigFile sections
directly.

Reusable editor components are scene-backed so their layout can be inspected
without running the full plugin. Programmatic content may include skeleton
preview data, but runtime or catalog state remains authoritative.

The GDSQL Logs dock records operation context and diagnostics. Ordinary
validation failures return structured results instead of throwing or printing
from deep runtime layers.

## Storage boundary

Catalog and table-storage contracts isolate the rest of GDSQL from physical
format details. ConfigFile is the current durable backend. In-memory storage is
used where runtime state benefits from explicit checkpoints. A future paged
binary backend should implement the same contracts rather than change query,
model, or editor semantics.

Only storage infrastructure knows ConfigFile section names and physical table
paths. Higher layers use typed definitions, registrations, and storage
operations.

## Where to go deeper

- [Project philosophy](./philosophy) explains the product and stability rules.
- [Core boundaries](./core) defines the complete canonical query architecture.
- [Glossary](./glossary) lists stable concepts, responsibilities, and status.
- [MCP integration](./mcp) defines the optional Godot-AI inspection boundary.
- [Database architecture](./databases) covers roles, storage, packages, and
  persistence in detail.
- [Editor architecture](./editor) covers actions, workbench ownership, and
  scene-backed documents.

<div align="center">

# GDSQL

### A Godot-native data layer for game content and saved state

Build typed tables, edit game data visually, connect content to runtime state,
and evolve released schemas without maintaining a separate database server or
an internal data platform.

[![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478CBF?logo=godot-engine&logoColor=white)](https://godotengine.org)
[![Tests](https://github.com/jinyangcruise/GDSQL/actions/workflows/test.yml/badge.svg)](https://github.com/jinyangcruise/GDSQL/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Status: pre-1.0](https://img.shields.io/badge/status-pre--1.0-f59e0b)](https://jinyangcruise.github.io/GDSQL/guide/compatibility)

[Documentation](https://jinyangcruise.github.io/GDSQL/) ·
[Getting started](https://jinyangcruise.github.io/GDSQL/guide/getting-started) ·
[Why GDSQL?](https://jinyangcruise.github.io/GDSQL/guide/why-gdsql) ·
[Roadmap](docs/development-roadmap.md)

</div>

---

Games usually have two kinds of durable data:

- **Content** shared by every player: characters, items, dialogue, abilities,
  balance values, and asset references.
- **State** owned by a playthrough: inventory, progression, customization,
  quest choices, settings, and other mutable data.

GDSQL gives both a common foundation inside Godot while keeping their
lifecycles separate. Designers work in a conventional table editor. Gameplay
code uses typed queries or generated models. Save slots, migrations, Resources,
and optional content packages use the same catalog and validation rules.

## What is included

### A table-first Godot workbench

- Create databases, tables, columns, defaults, indexes, and foreign keys.
- Browse paginated rows with typed nested filters and stable ordering.
- Edit, duplicate, batch-delete, and Undo/Redo changes during the editor session.
- Store Godot `Resource` values with concrete type validation and explicit
  referenced or database-owned policies.
- Navigate databases and tables from the dock or Godot command palette.

### One typed runtime pipeline

- Immutable query specifications for select, insert, update, and delete.
- Typed expressions, joins, grouping, aggregates, ordering, and projections.
- Schema, uniqueness, index, and foreign-key validation.
- Atomic transactions with rollback and structured diagnostics.
- Storage-independent public APIs with ConfigFile and in-memory backends today.
- Inspectable ConfigFile-authored content that fits ordinary version-control
  workflows.

GDSQL does not require SQL text. The editor and GDScript API build the same
canonical typed query model.

### Content, save slots, and models

- Logical `content`, `save`, and `settings` roles keep game code independent
  from physical database paths.
- Save slots can use fast in-memory runtime data with explicit durable
  checkpoints.
- Generated schema bases provide typed properties while user-owned child
  scripts preserve custom functions across regeneration.
- Catalog foreign keys generate same-database model navigation; stable content
  identifiers connect save state to authored definitions.

### Production-oriented foundations

- Ordered schema and data migrations with checksums and dry-run previews.
- Applied migration ledgers, schema fingerprints, backups, and recovery.
- Deferred Resource handles and bounded prefetch scopes for heavy assets.
- Structured diagnostics instead of UI-only errors or silent failures.
- Crash-safe table commits and recoverable save checkpoints.

### Optional AI-assisted workflows

When [Godot-AI](https://github.com/hi-godot/godot-ai) is installed, GDSQL
registers project-aware tools that can:

- inspect setup, schemas, constraints, and model bindings;
- query bounded scalar row windows with structured filters; and
- preview and explicitly confirm atomic scalar row mutations.

AI mutations use short-lived one-use handles and reject commits when their
schema or target rows changed after preview. Godot-AI remains optional; GDSQL
has no runtime dependency on it.

## Choose the workflow that fits the game

| Profile | Best fit | Content source |
|---|---|---|
| **Direct Content** | Small and medium games that want minimal setup | One project-authored database under `res://` |
| **Managed Content** | Games that need deterministic DLC, mod, or package overlays | A disposable effective database built from a base package and enabled additions |

The profile is chosen during onboarding and defines the content pipeline. It is
not a cosmetic option that should be switched casually after production data
has been created.

## Quick start

Requirements: **Godot 4.7 stable**. See the
[compatibility matrix](https://jinyangcruise.github.io/GDSQL/guide/compatibility)
before adopting a different engine version.

1. Copy `addons/gdsql` into the project's `addons` directory.
2. Enable **GDSQL** under **Project → Project Settings → Plugins**.
3. Open the **GDSQL** main screen and choose Direct or Managed Content.
4. Follow the welcome checklist to create content, a save slot, model bindings,
   and the optional runtime autoload.

The [first-project guide](https://jinyangcruise.github.io/GDSQL/guide/getting-started)
walks through the complete Direct Content setup.

## Typed query example

Gameplay code normally resolves a logical role and then builds a canonical
query:

```gdscript
var resolved := GDSQLRuntime.database(&"content")
if not resolved.is_successful():
    resolved.diagnostics.print_to_debug()
    return

var database := resolved.get_database()
var query := database.table(&"heroes") \
    .select() \
    .where(GDSQLExpr.column(&"health").greater_than(100.0)) \
    .order_by_column(&"health", GDSQLOrderClause.SortDirection.DESCENDING) \
    .limit(25) \
    .build()

var result := database.execute(query)
if result.is_successful():
    for row in result.get_rows():
        print(row.get_value(&"name"))
```

For higher-level access, generate and register a model binding, then query the
user-owned model class directly. See
[Runtime and models](https://jinyangcruise.github.io/GDSQL/guide/runtime-and-models)
and the [typed query API](https://jinyangcruise.github.io/GDSQL/guide/query-api).

## Documentation

| Topic | Start here |
|---|---|
| Installation and first project | [Installation](https://jinyangcruise.github.io/GDSQL/guide/installation) · [Getting started](https://jinyangcruise.github.io/GDSQL/guide/getting-started) |
| Tables and schema | [Table workbench](https://jinyangcruise.github.io/GDSQL/guide/table-workbench) · [Schemas and constraints](https://jinyangcruise.github.io/GDSQL/guide/schema-and-constraints) |
| Runtime data and relationships | [Runtime and models](https://jinyangcruise.github.io/GDSQL/guide/runtime-and-models) · [Relationships](https://jinyangcruise.github.io/GDSQL/guide/relationships) |
| Resources and performance | [Resource columns](https://jinyangcruise.github.io/GDSQL/guide/resource-columns) · [Benchmarks](https://jinyangcruise.github.io/GDSQL/guide/performance-benchmarks) |
| Releases and schema changes | [Migrations and recovery](https://jinyangcruise.github.io/GDSQL/guide/migrations-and-recovery) · [Compatibility](https://jinyangcruise.github.io/GDSQL/guide/compatibility) |
| Mods and content packages | [Content profiles](https://jinyangcruise.github.io/GDSQL/guide/content-profiles) · [Managed Content](https://jinyangcruise.github.io/GDSQL/guide/managed-content) |
| Design and internals | [Architecture overview](https://jinyangcruise.github.io/GDSQL/architecture/overview) · [Project philosophy](https://jinyangcruise.github.io/GDSQL/architecture/philosophy) |

## Scope and project status

GDSQL is an embedded local game-data layer, not an authoritative multiplayer
server, telemetry warehouse, or general-purpose network database. ConfigFile is
the current durable backend and is aimed at ordinary game-content and save-data
workloads rather than high-frequency, very large transactional datasets.

The architectural rewrite targets the first public **1.0** contract. Until it
is published, persisted-format corrections may still occur. Commit authored
content and migration definitions to version control, and review the
[roadmap](docs/development-roadmap.md) and
[compatibility policy](https://jinyangcruise.github.io/GDSQL/guide/compatibility)
before using a development build in a released game.

## Contributing

Issues, design discussion, and focused pull requests are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and
[AGENTS.md](AGENTS.md) before changing architectural code.

GDSQL is available under the [MIT License](LICENSE).

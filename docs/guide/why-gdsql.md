# Why GDSQL?

Game projects often begin with a few Resources, dictionaries, JSON files, or
spreadsheets. These approaches work well while the data is small and its
lifecycle is simple. The cost appears later, when authored definitions, player
state, asset references, validation, save compatibility, and content updates
start requiring separate conventions and tools.

GDSQL gives those responsibilities a shared structure inside Godot. Small teams
gain a supported path before custom data infrastructure becomes a project of
its own. Medium teams gain a common editor and runtime contract that designers
and programmers can inspect together.

## How existing approaches compare

| Approach | What it handles well | What a team usually adds |
|---|---|---|
| [Godot Resources](https://docs.godotengine.org/en/stable/classes/class_resource.html) and [ConfigFile](https://docs.godotengine.org/en/stable/classes/class_configfile.html) | Native types, asset references, reusable data objects, and simple Variant-compatible files | Table editing, constraints, relationships, query semantics, schema history, and save-slot coordination |
| [Unreal Data Tables](https://dev.epicgames.com/documentation/unreal-engine/data-driven-gameplay-elements-in-unreal-engine) and [Data Registries](https://dev.epicgames.com/documentation/unreal-engine/data-registries-in-unreal-engine) | Typed read-only rows, asset references, multiple data sources, lookup identifiers, caching, and asynchronous acquisition | Save state remains a separate system; project-specific serialization versions and conversions handle compatibility |
| [Unity ScriptableObjects](https://docs.unity3d.com/6000.1/Documentation/Manual/class-ScriptableObject.html) and [Addressables](https://docs.unity3d.com/Packages/com.unity.addressables@1.20/api/UnityEngine.AddressableAssets.Addressables.LoadAssetAsync.html) | Authored data assets, editor integration, asset identities, catalogs, and deferred loading | Runtime persistence, relational integrity, table workflows, and save-version upgrades |
| [CastleDB](https://github.com/ncannasse/castle) | Spreadsheet-style structured game content, typed sheets, row references, validation, and version-control-friendly files | Mutable runtime databases, transactions, save slots, engine-native Resources, and schema migration orchestration |
| SQLite and engine plugins | Mature relational queries, indexes, constraints, and transactions | Designer-facing authoring, engine asset types, generated game models, content/save roles, and mod composition |
| Spreadsheets with CSV or JSON export | Familiar bulk editing and easy collaboration | Import validation, stable identifiers, reference integrity, runtime APIs, merge policy, and version upgrades |

CastleDB is the closest comparison for authored content. Unreal's Data Registry
is a strong comparison for identifiers, layered sources, and caching. SQLite is
the closest comparison for relational execution. GDSQL draws from all three
areas while following Godot's project, Resource, and editor conventions.

## The integration gap

A complete game-data workflow usually crosses several boundaries:

1. Designers author shared definitions such as items, characters, dialogue,
   abilities, and balance values.
2. Runtime code reads those definitions through stable identifiers and typed
   interfaces.
3. Save files store mutable state while retaining references to shared content.
4. Project updates preserve existing player data as schemas evolve.
5. Optional DLC or mods extend content without modifying the shipped base.

Engine primitives generally address one or two of these boundaries. Teams then
write importers, registries, lookup helpers, custom inspectors, save serializers,
version switches, validation scripts, and recovery behavior around them. Each
piece may be reasonable on its own; inconsistencies between the pieces create
the expensive failures.

GDSQL centralizes the shared rules:

- A table owns its schema, constraints, indexes, and rows.
- The editor and runtime use the same query and validation pipeline.
- Generated models provide typed access while user scripts retain behavior.
- Logical roles separate authored `content`, per-playthrough `save`, and shared
  `settings` data.
- Godot Resource columns retain concrete type constraints and asset identity.
- Transactions protect related mutations.
- Migration history, checksums, previews, ledgers, backups, and recovery protect
  schema evolution.
- Managed Content composes a base package with optional packages into a
  disposable effective database.

This common foundation also leaves room for project-specific interfaces. A
studio can build a specialized quest editor, dialogue tool, or mod manager over
the same catalog and runtime services instead of introducing another storage
contract.

## Value for small teams

Small teams rarely want to maintain an internal data platform. They still need
stable answers to ordinary production questions:

- Where does permanent content live?
- Where does player state live?
- How does a save row refer to an authored definition?
- What happens when a column changes after release?
- How can a designer inspect and correct data without editing serialized text?
- How can failures be diagnosed without tracing several unrelated loaders?

The Direct Content profile keeps this path compact: one authored content
database, one or more save slots, generated model bindings, and an optional
runtime adapter. Projects can use the table editor without deploying or
administering a database server.

## Value for medium teams

As more people touch the same data, conventions need enforceable boundaries.
GDSQL provides:

- project-owned schemas and migration definitions suitable for version control;
- one visual workbench for tables, rows, constraints, and relationships;
- separation between generated schema bindings and user-owned model behavior;
- structured diagnostics for editor actions and runtime operations;
- deterministic content-package ordering and explicit save compatibility;
- storage contracts that allow future backends without replacing the public
  query and model APIs.

These boundaries reduce the number of implicit agreements carried only in team
knowledge. Code review can examine schema changes and migration history, while
content authors work through the Godot editor.

## When another tool fits better

Use a plain Resource when the project has a small number of independently
authored objects and does not need table-wide queries, constraints, or save
references. Use a dedicated level or dialogue editor when its domain-specific
canvas matters more than general tabular data. Use an authoritative server
database for multiplayer ownership, account data, matchmaking, telemetry, and
cross-player synchronization. Use a dedicated asset-delivery system when the
main problem is downloading and streaming large bundles.

These systems can coexist with GDSQL. A game may use GDSQL for local content and
save state, Addressables or an equivalent catalog for delivery, and a remote
service for authoritative multiplayer data.

## Current migration scope

The migration foundation currently includes ordered definitions, checksums,
dry-run previews, an applied ledger, schema fingerprints, backups, recovery,
runtime startup coordination, verified save baselines, and editor authoring for
one table change at a time. Table alteration, creation, rename, and drop are
supported. Typed single-table row updates use the same canonical expressions as
ordinary queries and participate in preview counts, backups, recovery, and the
applied ledger. Project content is verified at its trusted schema head without
runtime mutation.

Editor authoring for data steps, automatic fresh-save provisioning, multi-table
orchestration, and broader release/recovery verification remain active work.
Database creation, rename, unregister, and destruction are administrative
lifecycle operations rather than migration entries. Until the remaining work
is complete, released projects should treat migration support as pre-release
infrastructure rather than a finished compatibility promise.

Continue with [Create your first project](./getting-started), compare the
[content profiles](./content-profiles), or read the
[project philosophy](../architecture/philosophy).

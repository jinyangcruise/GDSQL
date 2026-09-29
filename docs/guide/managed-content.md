# Managed content packages

Managed Content builds one disposable `effective_content` database from an
immutable base package and explicitly enabled optional packages. Game code
continues to query the `content` role and does not need to know which packages
provided a row.

## Standard layout

```text
res://content/base/
├── manifest.cfg
├── data/
│   ├── databases.cfg
│   └── content/
│       ├── schema/
│       └── tables/
└── assets/

res://content/packages/<package-id>/
user://gdsql/mods/<package-id>/
user://gdsql/cache/effective_content/
```

Every package owns a `manifest.cfg`. Its `data_path` is a normal GDSQL data
root. The source database inside every contributing package is named `content`.
The effective cache is generated output and must not be edited as authored data.

## Create the base package

Choose Managed Content on the Welcome page, open **Managed content setup**, and
select **Create Base Database**. The scaffold creates the base manifest, `data`
and `assets` directories, and the `content` database.

Author base tables and rows through the database and table documents. The base
package defines the schemas consumed by optional layers.

## Package manifest

An optional package manifest can be written as:

```ini
[package]
id="example.cosmetics"
name="Example Cosmetics"
version="1.1.0"
kind="mod"
priority=20
data_path="data"
assets_path="assets"

[dependencies]
base.game=">=1.0.0"

[load_order]
after=PackedStringArray("base.game")
before=PackedStringArray()
```

Package IDs are stable identifiers. Versions use semantic-version syntax.
Supported kinds distinguish the base game from optional packages such as mods
or DLC. Paths are relative to the package root.

Dependencies require the named package to be enabled and version-compatible.
`after` and `before` add ordering edges. Among packages that are otherwise free
to load, lower priority loads first and package ID breaks ties. The base always
loads before optional packages. Cycles are rejected.

## Add and replace rows

An optional package may contain its own `content` database under its `data`
root. Rows are upserts keyed by the table primary key:

- a new identity adds a row;
- an existing identity replaces the earlier row;
- the later package is recorded as the effective row's provenance.

An override is a complete row, not a partial patch. It must satisfy every
required column. When a package supplies a schema for an existing table, that
schema must be equivalent to the earlier definition. A package may introduce a
new table by supplying its complete schema. Conflicting column, index, Resource,
or foreign-key metadata stops cache construction.

## Remove rows

A package can explicitly remove identities with `overlays.cfg` at its root:

```ini
[remove:content:items]
ids=PackedStringArray("deprecated_sword", "old_shield")
```

Integer identities may use a packed integer array. A removal-only package does
not need to duplicate the source database. Removing an identity that is not
present reports a warning.

## Discover and enable packages

In **Managed content setup** configure:

- the base package directory;
- package container directories, one per line;
- enabled optional package IDs, one per line.

Select **Validate** to inspect discovery, dependencies, versions, and the
deterministic load order. Discovery does not enable every package automatically;
the enabled-ID list is authoritative.

Select **Save & Build Cache** to persist the configuration and create or reuse
the effective cache. A package path, manifest, schema, row, asset reference, or
load-order change changes the fingerprint and causes a rebuild.

## Save compatibility

After selecting a save slot and building the cache, use **Record Current Package
Set…** to store the active package IDs, versions, hashes, and order beside that
save. Later startup compares the expectation with active content and reports:

- missing packages;
- changed packages;
- additional packages;
- changed load order.

GDSQL reports compatibility only. The game decides whether to block loading,
warn the player, continue with missing references, or run a project-specific
migration. Save rows are never silently deleted or rewritten.

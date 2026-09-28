# Resource columns

A Resource column requires a concrete Resource subtype and one storage mode.
The mode describes ownership; it is independent of whether the table belongs to
content, save data, or settings.

| Mode | Stored value | Use when |
|---|---|---|
| Owned | Independent Resource value serialized with the row | Each row owns editable Resource properties such as a generated mesh or configuration object |
| Referenced | Versioned UID/path locator to an existing asset | Rows point to imported textures, audio, scenes, or other project/package assets |

## Choose the mode

In the table schema, set the column type to **Resource**, choose its concrete
subtype, then choose **Owned** or **Referenced** under **Storage**.

Use Referenced for assets already saved in the filesystem. It avoids embedding
imported data in every table row and follows a Godot UID when available, with a
path fallback and expected-type check.

Use Owned when the Resource value itself is row data. Owned Resources use
Godot's native Resource serialization, so complex values can still be larger
than scalar columns.

## Runtime loading and memory

**Referenced describes persistence ownership; it does not currently guarantee
lazy loading.** The table stores only a compact UID/path locator, but GDSQL
resolves that locator with `ResourceLoader.load()` when the row is decoded.

Opening a ConfigFile database normally loads its catalog without reading every
row. However, a table scan currently decodes every stored column before query
projection, filtering, or pagination. A query that returns only NPC names can
therefore still load mesh, texture, audio, or scene references from every
scanned row. A primary-key or index lookup narrows the affected rows, but still
decodes every column in each matching row. In-memory hydration and a Managed
Content cache rebuild may decode complete tables.

For a large asset catalog, keep frequently queried metadata separate from heavy
assets:

```text
npc_definitions
- id
- name
- stats
- dialogue_id

npc_assets
- npc_id
- mesh
- texture
- voice
```

Browse or query `npc_definitions`, then look up one indexed `npc_assets` row
when the NPC is needed. This is the reliable lazy-loading boundary in the
current release; selecting fewer columns alone does not prevent referenced
Resources from loading.

Godot Resources are reference-counted. To make a loaded asset eligible for
release, clear it from scene properties and release every result, model, array,
or other object that still references it. An in-memory GDSQL table can itself
retain the Resource, so GDSQL does not currently provide a deterministic
per-table or per-row unload operation. See Godot's
[`Resource`](https://docs.godotengine.org/en/stable/classes/class_resource.html)
and
[`ResourceLoader`](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html)
documentation for engine caching and reference-count behavior.

Deferred Resource handles, selective column decoding, threaded materialization,
and explicit content loading/eviction policies are active roadmap work.

## Editing behavior

The table editor validates the selected Resource against the schema subtype.
Referenced values are replaced as assets. Owned values expose editable
Inspector properties and are duplicated when copied into a new-row draft.

Visual Resources may show a thumbnail. Other Resource types use their editor
icon and are not sent to incompatible preview plugins. Imported audio streams
must be selected from an existing asset rather than constructed as an empty
Resource.

## Paths and packages

Direct Content references normally use project assets under `res://`. Managed
Content packages may use package assets, but effective rows must still resolve
through valid package or project locators. Moving an asset is safest when its
Godot UID remains valid.

Missing or type-mismatched referenced assets currently resolve as unavailable.
More detailed row-and-column storage diagnostics are part of release QA.

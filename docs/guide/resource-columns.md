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

Referenced columns store a compact locator and use eager loading by default.
Queries only resolve Resource columns required by the plan; unrelated scalar
projections and counts do not load them. Asset-heavy code can explicitly return
deferred handles:

```gdscript
var result := database.execute(
    database.table(&"npc_assets").select().build(),
    GDSQLQueryExecutionOptions.deferred_resources(),
)
var scope := result.create_resource_prefetch_scope()
scope.request_load()

# Poll from a process loop until the snapshot is complete.
var snapshot := scope.poll_load().get_value() as GDSQLResourcePrefetchProgress
print(snapshot.progress)
```

`GDSQLResourceHandle.load()` loads synchronously. `request_load()` plus
`poll_load()` uses Godot's threaded loader. A prefetch scope coordinates all
handles returned for one bounded gameplay lifetime and reports aggregate loaded
and failed counts. A failure does not prevent the scope from finishing its
other requests.

Resource-dependent filters, ordering, grouping, joins, or derived expressions
require concrete Resources and therefore reject deferred execution. Run those
queries with the default eager policy.

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

Browse or query `npc_definitions`, then look up and prefetch the relevant
`npc_assets` rows when the NPC is needed. This remains useful because it keeps
the query and asset working sets bounded.

Call `scope.release()` when its scene, area, encounter, or menu ends. For a
deferred model, scope release also clears the concrete model properties loaded
through those handles. Godot Resources are reference-counted, so the asset is
only eligible for reclamation after scenes, caches, and every other consumer
also release it. Releasing a scope cannot cancel a native threaded request that
Godot already accepted. See Godot's
[`Resource`](https://docs.godotengine.org/en/stable/classes/class_resource.html)
and
[`ResourceLoader`](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html)
documentation for engine caching and reference-count behavior.

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

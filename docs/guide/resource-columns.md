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

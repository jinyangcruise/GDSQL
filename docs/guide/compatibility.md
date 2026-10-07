# Compatibility

## Godot support

| Godot version | Status | Reason |
|---|---|---|
| 4.7 stable | Supported and tested | GDSQL uses the 4.7 `EditorDock` API and CI runs the complete test suite on this line. |
| 4.6 and earlier | Unsupported | The editor plugin cannot provide its dock lifecycle through the older API. |
| Later 4.x releases | Unverified | Support begins after the test suite and isolated addon package check pass on that line. |
| Godot 3.x | Unsupported | GDSQL is built for Godot 4 and uses typed GDScript 2 features. |

The standard Godot build is the verified development target. Exported-game and
platform matrices remain release-QA work; do not infer a platform guarantee
from editor support alone.

## Package boundary

The release artifact contains only `addons/gdsql`. CI copies that directory
into an otherwise empty Godot 4.7 project, enables the plugin, and rejects
script parsing or loading failures. Development plugins such as GdUnit4 are not
package dependencies.

Godot-AI is optional. GDSQL discovers its custom-tool contract at editor time
and continues normally when Godot-AI is absent.

## Persisted data

Catalogs, tables, migration definitions, migration ledgers, recovery snapshots,
content manifests, and Resource locators have independent format versions.
Schema changes use project-owned migrations; copying a newer addon over a
project does not migrate databases implicitly.

GDSQL has not published its stable 1.0 data-format promise yet. Projects using
the development version should commit authored content and migration files so
format corrections remain reviewable. A supported release will document
whether an addon update is compatible directly, requires migrations, or
requires an explicit conversion tool.

See [Installation](./installation) for setup and
[Troubleshooting](./troubleshooting) for diagnostics.

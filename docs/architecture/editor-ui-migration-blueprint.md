# Editor UI Migration Blueprint

## Purpose

This document inventories the usable editor-facing structure in the legacy GDSQL workbench so that equivalent capabilities can be reassigned within the headless architecture.

The new branch cannot access or depend on the legacy scenes, scripts, or hierarchy. This document must therefore remain a self-contained product and UI map. Legacy code is evidence of behavior only and is not a source dependency or a constraint for the replacement.

### Feature scope

| Feature | Status in the new architecture |
| --- | --- |
| Database dock | Planned editor surface |
| Activity bottom panel | Planned editor surface |
| Major and contextual action hubs | Planned coordination surface |
| SQL graph | Planned and under development |
| Text SQL editor | Possible; not committed |
| XML editor | Out of scope |
| Mapper graph/editor | Out of scope |

Out-of-scope features are not parity requirements and should not appear in action configuration, navigation, or reusable-component planning for the new branch.

## Migration principles

- Keep database tooling in the editor and out of the game runtime.
- Preserve useful workflows and interaction patterns, not the legacy code structure.
- Do not require access to legacy files from the new branch.
- Treat visible labels, tooltips, icons, shortcuts, availability rules, and placement as UI configuration.
- Treat actions as stable capabilities that UI entries reference.
- Allow the same action to appear in a menu, toolbar, context menu, command search, or shortcut without redefining it.
- Route global actions through a major hub and delegate context-specific actions to child hubs.
- Prefer reusable editor components for repeated layouts and interaction states.
- Distinguish observed workflows from unfinished or placeholder controls.

## Proposed editor integration

The legacy workbench placed all controls inside one main screen. The replacement should distribute them across native Godot editor surfaces:

```text
Godot editor
├── Editor toolbar / GDSQL action entry
│   └── Major action hub
├── Database dock
│   ├── Schema tree
│   └── Selection-specific actions
├── Central editor workspace
│   ├── SQL graph
│   ├── Database task pages
│   └── Optional text SQL editor
└── Bottom panel
    └── GDSQL activity
```

This removes the permanent navigator and activity log from the central GDSQL workspace. The graph and task pages receive the central area, while persistent navigation and feedback use the same editor regions as other Godot tools.

### Godot terminology

- **Editor dock**: a movable editor panel such as Scene, FileSystem, or Inspector. The database tree should be a dock, with a side position as its default and user-controlled repositioning.
- **Bottom panel**: the lower editor region containing tools such as Output and Debugger. GDSQL activity should appear as another item in this region.
- **Main screen**: a central editor workspace selected alongside screens such as 2D, 3D, Script, and Game. The SQL graph may use this surface when it needs the full central area.

The project targets Godot 4.7, where `EditorDock` represents dockable editor content and can support side, bottom, or floating layouts. This terminology documents the intended editor placement; it does not prescribe the plugin implementation.

### Corresponding editor extension points

| Intended surface | Godot 4.7 extension point |
| --- | --- |
| Database dock | `EditorDock`, registered by the editor plugin as a dock |
| GDSQL activity beside Output and Debugger | Custom bottom-panel control |
| SQL graph in the central workspace | Main-screen editor plugin |
| GDSQL action entry in the editor toolbar | Main editor toolbar container |

These names are included so the same surfaces can be identified in the new branch and in Godot documentation. They are not an implementation sequence.

## Primary action area

The primary GDSQL action area should follow a familiar editor pattern: compact category buttons expose cards or menus beneath them, and entries may open nested choices to the side.

This pattern is a strong candidate for a reusable, configuration-driven component:

```text
Action strip
└── Category trigger
    └── Action card
        ├── Action entry
        ├── Toggle entry
        ├── Separator
        └── Nested action group
            └── Side card
```

Each configured entry may describe:

- stable action identifier
- translation key for its label
- translation key for its tooltip, when present
- icon reference
- shortcut reference
- entry kind: action, toggle, separator, or nested group
- display order and grouping
- context in which the entry is relevant

The configuration describes presentation and discovery. It does not contain feature behavior.

### Current action groups

| Group | User-facing capabilities found in the legacy workbench |
| --- | --- |
| File | New SQL graph, optional new text query, open, recent files, close tab, save, save as |
| Edit | Undo, redo, cut, copy, paste, delete, select all, autocomplete, format, settings |
| Search | Find, next/previous match, replace, find in files, replace in files |
| View | Welcome page, panel visibility, next/previous tab |
| Query | Execute all or selection, execute current statement, stop, continue after errors, row limit, auto-commit, commit, rollback, commit/discard result edits, export results |
| Database | Schema transfer and table-data search entry points |
| Help | Search help, documentation/community links, system information, feedback links, about, support |

The legacy source contains menu entries that are incomplete or placeholders. Presence in this table means the capability has a discoverable location; it does not confirm that the legacy action is fully operational.

Entries tied to the optional text SQL editor become available only if that feature is accepted. XML and mapper actions are excluded.

## Major and contextual action hubs

A major action hub should provide the common entry point for editor-wide GDSQL actions. It connects to smaller context hubs owned by surfaces such as the database dock, SQL graph, task page, data grid, or optional SQL editor.

```text
Major GDSQL action hub
├── Database dock action hub
├── SQL graph action hub
├── Active task action hub
├── Data grid action hub
└── Optional SQL editor action hub
```

The major hub represents:

- which actions exist
- their stable identities
- their user-facing metadata
- where they may be presented
- whether they are currently visible, enabled, or selected
- which context hub owns each action
- which context is currently active

Context hubs represent:

- actions belonging to one feature surface
- whether an action applies to the current selection or active page
- the action result
- feature-specific state and validation

This makes navigation traceable from one major hub while preventing it from becoming one oversized script. Menus, cards, shortcuts, context actions, and future command search share the same action identities, while each context remains independently assignable.

## Database dock

The database tree should be a native editor dock rather than a permanent section inside the GDSQL central workspace. It exposes the project data model as:

```text
Schema
└── Table
    └── Column
```

### Persistent interactions

- Open, close, move, or float the dock using normal editor layout behavior.
- Refresh all schemas.
- Expand and collapse the hierarchy.
- Preserve expansion state across refreshes.
- Select a default schema.
- Open a table by selecting it.
- Drag a table into graph-based tools.
- Surface encrypted/locked state.
- Open an entry's files in the file manager or an external program.
- Detect configuration files changed outside the editor and offer recovery choices.

### Context capabilities

| Context | Capabilities found in the legacy workbench |
| --- | --- |
| Empty navigator | Create schema, refresh |
| Schema | Set as default, copy schema information, optionally send creation content to the SQL editor, export/import, create or alter schema, password actions, drop, refresh |
| Tables group | Create table, create table based on another table, export/import, truncate all, refresh |
| Table | Select rows, inspect, copy table information or SQL statements, optionally send to SQL editor, export/import, create/clone/alter, password actions, drop, truncate, reveal/open files, refresh |
| Column | Select rows, copy column information or SQL statements, optionally send to SQL editor, refresh |

Views, stored procedures, and functions appear as reserved hierarchy groups with creation and refresh entries. They should remain tracked as possible extension points, not as confirmed parity requirements.

### Reusable component candidates

- Hierarchical resource navigator
- Context-action card generated for a selected resource type
- Database-dock context hub
- Inline status/action icon for locked, indexed, changed, or external-file states
- External-change review prompt
- Drag payload representation for database resources

## Central workspace and tab lifecycle

The central workspace is reserved for tools that benefit from editor space. The SQL graph is the confirmed planned tool. Database task pages may share a tab host, while a text SQL editor remains optional.

Tracked tab types:

- SQL graph: planned
- text query: possible
- create schema
- alter schema
- create table
- alter table
- table inspector
- table data export
- table data import
- selected-result export
- settings
- license/about

File-backed pages may track recent files and avoid opening duplicate views of the same file. Where tabs are used, context actions may cover closing the current tab, other tabs, tabs to the right, or all tabs.

### Reusable component candidates

- Editor workspace tab host
- File-backed tab lifecycle
- Dirty/saved state presentation
- Recent-resource list
- Tab context-action card
- Feature-page title and icon descriptor

## Usability inventory for reassignment

The entries below describe user-facing capability without requiring the new branch to resolve a legacy scene path.

### Welcome

Relevant features:

- product introduction
- documentation and getting-started links
- issue, community, showcase, credits, and support links
- settings entry point
- version/update status
- rotating usage tips with previous, next, and refresh controls

This page is a reusable workbench landing pattern. The exact promotional sections are content configuration rather than structural requirements.

### SQL graph

Hierarchy:

```text
SQL graph page
├── File and query action strip
└── Graph canvas
    └── Query nodes and links
```

Relevant features:

- open, save, and save as
- execute graph query
- execute focused/current statement
- continue after errors
- commit, rollback, and auto-commit
- add Select, Left Join, Insert, Update, Delete, raw SQL, and Link nodes
- drag tables from the database dock
- select, move, connect, inspect, enable/disable, and remove graph nodes
- display generated query details and results

Reusable candidates include the graph surface shell, graph action palette, selectable node card, connection affordances, and detail panel.

### Schema forms

Relevant fields and actions:

- schema name or display name
- data path
- path source choices for project resources, user data, installation data, or filesystem
- apply and cancel

### Table definition forms

Relevant fields and actions:

- schema
- table name
- comment
- optional password and confirmation for new tables
- valid-without-precreated-data-file option
- add, edit, reorder, and remove columns
- column name, type, default, comment, primary key, unique, auto-increment, and related constraints
- apply and cancel

Creating and altering tables are variants of the same table-definition workspace.

### Table inspector

Relevant features:

- schema and table identity
- comment
- data-file path and reveal action
- data-file size
- total row count
- locked-data prompt
- open configuration file
- column definition table

### Table data import

Relevant features:

- choose a source from project resources, user data, or filesystem
- CFG, CSV, and JSON source formats
- preview source data
- import into an existing table or create a new table
- select destination schema/table
- optional truncate or drop behavior
- select and map source columns
- choose inferred types and primary key when creating a table
- import and cancel

### Table and result export

Relevant features:

- source table or supplied result set
- data preview
- column selection
- row offset and count for table export
- CFG, CSV, and JSON output
- output path source choices
- CSV field separator, line separator, and string enclosure
- CFG section-key selection for result export
- open destination when finished
- export and cancel

These scenes are two contexts of one export workflow.

### Settings

Relevant settings:

- root schema/configuration path
- supplementary runtime configuration path
- game-configuration database
- default page opened by the new-tab control
- automatic update check

The settings page should expose only editor-side choices that remain relevant to the new architecture.

### Shared data grid

Relevant features:

- configurable columns and relative widths
- row and cell selection
- select all
- copy field or row
- paste and delete when permitted
- add/delete row when permitted
- inline editors appropriate to displayed values
- resizable columns
- scrolling and programmatic scroll-to-bottom
- optional checkbox and icon cells
- optional selection border
- context actions

The grid is used for table data, column definitions, query results, previews, and the activity log. These uses require distinct capability profiles rather than separate grid implementations.

### Activity bottom panel

GDSQL activity should be an editor bottom-panel item alongside Output, Debugger, and other editor tools. It records:

- status
- sequence
- time
- action
- message
- duration and cost

The panel should be collapsible and should not consume central workspace space while inactive. Errors may also be surfaced through editor notifications. Long-running or destructive workflows additionally use confirmation, password, and file-change prompts.

Reusable candidates include a structured activity feed, activity context hub, editor notification adapter, confirmation prompt, credential prompt, and external-change prompt.

## Reusable component catalog

| Component | Reused by |
| --- | --- |
| Configured action strip | Major editor actions, optional query editor, SQL graph |
| Action card / nested side card | Header categories, database dock, tab actions, graph controls |
| Major action hub | Editor-wide discovery, routing, and active context |
| Context action hub | Database dock, SQL graph, active task, data grid, optional SQL editor |
| Workspace tab host | SQL graph and database task pages |
| Hierarchical resource navigator | Database dock |
| Capability-based data grid | Table data, schema columns, results, previews, logs |
| File-backed editor page | SQL graph and optional text query |
| Query execution controls | SQL graph and optional text query |
| Graph workspace | SQL graph |
| Definition form | Create/alter schema and create/alter table |
| File/path selector | Schema paths, import, export, settings |
| Format and export options | Table export and selected-result export |
| Search/filter field | Database dock, data grid, optional text editor |
| Activity bottom panel | Operation history and feedback |
| Modal prompt family | Confirmation, password, missing file, external changes |
| Landing/information page | Welcome, about/license, future empty states |

## Configuration ownership

UI configuration should be organized by feature surface rather than by individual scene. A surface may contribute:

- top-level action categories
- action entries and nested groups
- context actions for resource types
- tab title and icon metadata
- field labels, descriptions, placeholders, and tooltips
- empty-state and informational content
- option labels and ordering

All user-facing strings should be represented by translation keys, including tooltips and prompt text. Runtime values such as schema names, paths, query output, and file names remain data rather than translated UI content.

Configuration does not determine:

- action behavior
- database or filesystem access
- feature state transitions
- validation outcomes
- destructive-operation policy
- transaction ownership

## Capability-to-surface map

| Capability | Primary surface | Additional access |
| --- | --- | --- |
| Create/open/save editor resources | Workspace tabs | File action card, new-tab card, recent files |
| Manage schemas and tables | Database dock | Major action hub, definition task pages |
| Inspect and edit table data | Table tab/grid | Schema/table context card |
| Write and run SQL | Optional text query page | Query action card, database context actions |
| Compose SQL visually | SQL graph main workspace | Major action hub, database-table drag |
| Import/export data | Import/export tabs | Schema/table/result context actions |
| Configure editor integration | Settings tab | Edit action card, welcome page |
| Review operation feedback | GDSQL bottom panel | Editor notifications and prompts |
| Discover help and project links | Welcome/help surfaces | Help action card |

## Legacy observations that should not become requirements

- Several controls are hard-coded directly in scenes or scripts.
- Similar toolbars and forms are duplicated.
- Menu identifiers depend on local numeric ordering.
- Some menu entries are placeholders, incomplete, or disconnected from a finished workflow.
- Translation coverage is inconsistent.
- The legacy layout embeds navigation and logs in the main screen; the replacement assigns them to an editor dock and bottom panel.
- Feature scripts combine UI state, file access, database operations, and coordination responsibilities.
- The shared data grid contains debug/model nodes and a broad set of conditional behaviors.

These observations explain why the legacy experience should be documented in a self-contained form rather than migrated structurally or referenced from the new branch.

## Godot editor references

- [EditorPlugin 4.7](https://docs.godotengine.org/en/4.7/classes/class_editorplugin.html)
- [EditorDock 4.7](https://docs.godotengine.org/en/4.7/classes/class_editordock.html)
- [Making main screen plugins](https://docs.godotengine.org/en/latest/tutorials/plugins/editor/making_main_screen_plugins.html)

## Reassignment checklist

For each feature moved to the new branch, record:

- capability owner in the new architecture
- editor surface where it appears
- action identifiers it contributes
- context required for availability
- reusable components it consumes
- translation keys and icons it needs
- file-backed or transient tab behavior
- feedback channel: inline, activity feed, notification, or prompt
- whether the legacy entry is confirmed, partial, placeholder, or intentionally retired

This checklist is the handoff boundary between the legacy UI inventory and later implementation planning.

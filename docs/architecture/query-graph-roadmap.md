# Query graph implementation roadmap

This document records the implementation order for visual query composition.
The ownership and dependency rules in [`editor.md`](editor.md) and
[`core.md`](core.md) remain authoritative.

## Implemented foundation: SELECT, predicate, and table result

The first executable graph path is one selected `SELECT` operation:

```text
SELECT source node
    database registration + logical database + table
    checked result columns + optional typed WHERE comparison
        ↓ GraphQueryCompiler
SelectQuerySpec (projection + optional predicate)
        ↓ Database.execute()
QueryResult + ResultSchema
        ↓
Table result node
```

The Query action lives inside each SELECT node. It compiles that visual source,
its checked columns, and its optional predicate into the canonical query model.
The editor controller executes the compiled query through the opened database
and returns the structured result to the originating graph document. Graph
controls and result controls do not access storage.

The Columns menu uses checkable popup items and preserves catalog order. Every
column checked compiles as implicit `SELECT *`; a subset compiles through
`SelectQueryBuilder.columns()`. An empty projection is rejected instead of
silently becoming `SELECT *`.

The reusable WHERE control supports ordered typed conditions composed with
`AND`, `OR`, and per-condition `NOT`. Each condition chooses a catalog column,
comparison or null-check operator, and a literal edited with the shared Variant
value field. It creates the canonical expression through `GDSQLExpr`.

Every query operation uses the shared `QueryGraphNode` titlebar. Its X button
emits removal intent to the graph editor, and its fit button resets the graph
to 100% zoom and resizes that node to the current viewport once. It is not a
toggle and does not continuously compensate for later zooming or scrolling.
Removing a SELECT also removes its connected derived result, while closing only
the result keeps the SELECT available. The titlebar action host is reserved for
operation-specific controls.

The table result derives mutation capabilities from the returned schema:

- Returned rows are editable only when the source table primary key is in the
  result. The primary key itself and generated values remain read-only.
- A changed row becomes dirty and enables the result-level Save Changes action.
- A row may be added only when every source-table column is present. Defaults,
  generated values, and auto-increment behavior continue to be applied by the
  canonical insert pipeline.
- Saving, inserting, or deleting reruns the graph query after a successful
  mutation so the displayed result remains authoritative.
- A result without the primary key is read-only. A projection may still be
  displayed even when it cannot safely identify a row for mutation.
- A native multi-column `Tree` renders pages of 10, 25, 50, or 100 rows with
  titled, scrollable columns. Selecting one row opens the shared typed editor
  below the table; dirty edits block selection and page changes until saved or
  discarded.
- The typed row component owns fields and validation only. Add, Save, Discard,
  and Delete controls belong to the result node, establishing one owner for
  dirty-state policy before multi-row batch mutation is introduced.
- Query refresh is blocked while the focused row is dirty, and closing its
  workspace document requires explicit discard confirmation.
- Transaction-backed multi-row batch saving remains the next lifecycle slice;
  the current controller refreshes the authoritative result after each single
  mutation.

Only one selected operation is an executable root at a time. Multiple visual
operations and their connections become executable after connection validation
and output-root selection are implemented.

## Implemented slice: selectable columns

Projection editing is stored on the typed graph SELECT node. Compilation maps
chosen columns to `SelectQueryBuilder.columns()` and therefore to
`SelectProjection` values.

Required presentation and behavior:

1. Load the selected table's ordered catalog columns without loading rows.
2. Provide Select all, Clear, and ordered column selection.
3. Treat every selected column as `SELECT *`, reject an empty selection, and
   otherwise preserve the selected projection order.
4. Display projection changes in the node summary before execution.
5. Derive result edit/insert capability from `ResultSchema`, never from the
   visual selection alone.
6. Preserve the primary-key capability rule: partial results are editable only
   when the primary key is returned; insertion still requires all columns.

Expression projections, aliases, aggregates, and calculated columns follow
named-column projection. They must use canonical `QueryExpression` and
`SelectProjection` objects rather than editor-only expression dictionaries.

## Implemented slice: composed WHERE expressions

The reusable visual WHERE editor creates the same immutable expression nodes
exposed by `GDSQLExpr`. It is embedded by SELECT and is the shared predicate
surface for the future UPDATE and DELETE nodes. INSERT does not use it because
an insert has no row-selection predicate.

Implemented operations:

- Column operand: choose a column from the selected source schema.
- Typed literal operand: reuse the editor Variant value field with the chosen
  column's catalog type and nullability.
- Comparisons: equals, not equals, greater than, greater than or equal, less
  than, and less than or equal.
- Null checks: is null and is not null; these do not show a value parameter.
- Append multiple conditions and compose them with `AND` or `OR`.
- Apply `NOT` to an individual condition.
- Remove and reorder conditions.
- Build mixed logical chains explicitly from top to bottom. The displayed
  summary includes parentheses so the left-associative meaning remains visible.
- Inline diagnostics for incompatible operands, incomplete expressions, and
  invalid typed values.

Operations still to create:

- Explicit nested groups with their own `AND`/`OR` composition and group-level
  `NOT`.
- Duplicate expression rows or groups.
- Column-to-column comparison and reusable expression-node inputs.

Compilation maps these controls to `GDSQLExpr.column()`, typed literals,
comparison combinators, null checks, and logical combinators, then assigns the
result through `SelectQueryBuilder.where()`. Controls never evaluate the
expression and never construct an execution plan.

## Implemented slice: standalone mutation operations

Result-table row actions emit canonical insert, update, and delete intents for
individual displayed records. Standalone mutation graph nodes are a separate
authoring surface and use the same canonical builders:

1. `INSERT` selects a registration and table, then presents one typed row with
   opt-in column values. Generated and auto-increment columns are unavailable.
   It has no WHERE component; batch rows remain future work.
2. `UPDATE` selects a registration and table, presents one or more typed
   assignments, and embeds `WhereExpressionEditor`. Primary-key, generated,
   and auto-increment assignments are unavailable. Updating every row requires
   an inline all-rows confirmation that resets when the source changes.
3. `DELETE` selects a registration and table and embeds
   `WhereExpressionEditor`. Deleting every row requires an inline destructive
   confirmation that resets when the source changes.
4. Mutation execution returns structured affected-row data and diagnostics,
   presents an affected-row result, and refreshes workbench inspection/catalog
   surfaces after success.

Graph controls compile to `InsertQuerySpec`, `UpdateQuerySpec`, or
`DeleteQuerySpec`; they do not stage storage changes themselves.

`QueryGraphSourceSelector` shares inspection-backed registration/table
selection across mutation nodes. `MutationValuesEditor` shares typed opt-in
column values between INSERT and UPDATE. SELECT still owns its established
source controls; migrating it to the shared selector is deferred until that
can be done without layout churn.

ConfigFile inspection decodes static column defaults through the same Godot
Variant codec used by catalog loading. Consequently, INSERT value controls can
present scalar, collection, Resource, and explicit-null defaults without
loading table rows. The canonical insert validator remains authoritative when
a defaulted column is omitted.

### Planned object-value constraints

`TYPE_OBJECT` currently means any `Resource` in catalog validation and the
editor picker. Restricting an object column to a specific Resource class is a
separate schema feature and should be implemented in this order:

1. Add a typed Resource-class constraint to `ColumnDefinition`, defaulting to
   the current unrestricted `Resource` behavior for existing schemas.
2. Persist and load that constraint through catalog administration, catalog
   loading, and lightweight inspection metadata.
3. Resolve built-in and project-global Resource classes and reject unknown or
   non-Resource constraints with structured catalog diagnostics.
4. Enforce inheritance compatibility in column/default validation, query
   binding, and decoded stored values; do not rely only on editor filtering.
5. Configure `EditorResourcePicker.base_type` from the constraint so graph,
   table-row, and column-default controls expose compatible resources.
6. Add backward-compatibility, inherited-class, custom-script Resource,
   invalid-default, and schema round-trip coverage before marking the feature
   implemented.

## Next slice: model-backed graph queries

A graph source may later select either a raw catalog table or a registered
model. The source-mode and model controls may live in the shared titlebar action
host, but model resolution remains in the model frontend:

- Registered model metadata resolves its logical role and backing table through
  `ModelRegistry` and `DatabaseRegistry`.
- Graph compilation still produces canonical `QuerySpec` objects.
- Model results use `ModelResultMaterializer` and a dedicated model-result view.
- Relationship operations inspect registered `RelationshipDefinition` values
  and issue related model queries without editing model scripts or deriving
  catalog structure from them.
- Raw tables remain fully supported when no model exists.

## Later graph operations

After projections and predicates are stable, implement operations in this
order:

1. `ORDER BY`, `LIMIT`, `OFFSET`, and `DISTINCT` on a single SELECT path.
2. `LEFT JOIN`, including typed ports, aliases, join predicates, and connection
   validation.
3. Multiple source paths and explicit output-root selection.
4. Graph asset save/load under `res://.gdsql/graphs/`, including node layout,
   stable node identities, connections, and a format version.
5. Result paging, rerun/cancel state, export, and reusable result views outside
   the graph surface.

Each increment must keep graph state descriptive, compile to `QuerySpec`, pass
structured diagnostics across the editor boundary, and execute only through
the public database runtime.

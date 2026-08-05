# Query graph implementation roadmap

This document records the implementation order for visual query composition.
The ownership and dependency rules in [`editor.md`](editor.md) and
[`core.md`](core.md) remain authoritative.

## Current slice: SELECT, projection, predicate, and table result

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

The initial WHERE control supports one typed expression. It chooses a catalog
column, comparison or null-check operator, and a literal edited with the shared
Variant value field. It creates the canonical expression through `GDSQLExpr`.
Supported operators are equals, not equal, greater than, greater than or equal,
less than, less than or equal, is null, and is not null.

Right-clicking a SELECT node exposes Remove node. Removing the operation also
removes its connected derived result, while unrelated SELECT nodes and results
remain available.

The table result derives mutation capabilities from the returned schema:

- Returned rows are editable only when the source table primary key is in the
  result. The primary key itself and generated values remain read-only.
- A changed row becomes dirty and exposes its row Save action.
- A row may be added only when every source-table column is present. Defaults,
  generated values, and auto-increment behavior continue to be applied by the
  canonical insert pipeline.
- Saving, inserting, or deleting reruns the graph query after a successful
  mutation so the displayed result remains authoritative.
- A result without the primary key is read-only. A projection may still be
  displayed even when it cannot safely identify a row for mutation.

Only the selected SELECT node is an executable root in this slice. Multiple
visual operations and their connections become executable after connection
validation and output-root selection are implemented.

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

## Next expression slice: composed WHERE expressions

The visual WHERE builder creates the same immutable expression nodes exposed by
`GDSQLExpr`. One typed comparison or null check is implemented. The next slice
adds multiple expression rows and logical composition.

Implemented operations:

- Column operand: choose a column from the selected source schema.
- Typed literal operand: reuse the editor Variant value field with the chosen
  column's catalog type and nullability.
- Comparisons: equals, not equals, greater than, greater than or equal, less
  than, and less than or equal.
- Null checks: is null and is not null; these do not show a value parameter.
- Inline diagnostics for incompatible operands, incomplete expressions, and
  invalid typed values.

Operations still to create:

- Logical composition: AND, OR, and NOT with explicit nested groups.
- Remove, duplicate, and reorder expression rows or groups.
- Column-to-column comparison and reusable expression-node inputs.

Compilation maps these controls to `GDSQLExpr.column()`, typed literals,
comparison combinators, null checks, and logical combinators, then assigns the
result through `SelectQueryBuilder.where()`. Controls never evaluate the
expression and never construct an execution plan.

## Later graph operations

After projections and predicates are stable, implement operations in this
order:

1. `ORDER BY`, `LIMIT`, `OFFSET`, and `DISTINCT` on a single SELECT path.
2. `LEFT JOIN`, including typed ports, aliases, join predicates, and connection
   validation.
3. Multiple source paths and explicit output-root selection.
4. `INSERT`, `UPDATE`, and `DELETE` operation nodes using canonical builders
   and confirmation appropriate to their mutation scope.
5. Graph asset save/load under `res://.gdsql/graphs/`, including node layout,
   stable node identities, connections, and a format version.
6. Result paging, rerun/cancel state, export, and reusable result views outside
   the graph surface.

Each increment must keep graph state descriptive, compile to `QuerySpec`, pass
structured diagnostics across the editor boundary, and execute only through
the public database runtime.

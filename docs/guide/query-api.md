# Typed query API

The typed API builds canonical query objects. It does not parse SQL strings;
`execute_sql()` currently returns a not-implemented diagnostic.

## Resolve a database

Runtime game code normally resolves a logical role:

```gdscript
var resolved := GDSQLRuntime.database(&"save")
if not resolved.is_successful():
    resolved.diagnostics.print_to_debug()
    return

var database := resolved.get_database()
```

Use `content`, `save`, or `settings` rather than constructing physical data
paths in gameplay code.

## Select rows

```gdscript
var spec := database.table(&"heroes") \
    .select() \
    .where(
        GDSQLExpr.column(&"health").greater_than(100).and_(
            GDSQLExpr.column(&"active").equals(true),
        ),
    ) \
    .order_by_column(&"health", GDSQLOrderClause.SortDirection.DESCENDING) \
    .limit(25) \
    .build()

var result := database.execute(spec)
if result.is_successful():
    for row in result.get_rows():
        print(row.get_value(&"name"))
```

Select builders support projections, aliases, inner and left joins, grouping,
HAVING, aggregates, distinct results, ordering, limits, and offsets. A builder
becomes immutable after `build()`.

For a qualified join projection, use expressions:

```gdscript
var spec := database.query() \
    .select() \
    .from_table(&"heroes", &"hero") \
    .project(GDSQLExpr.column(&"name", &"hero"), &"hero_name") \
    .inner_join(
        &"teams",
        GDSQLExpr.column(&"team_id", &"hero").equals(
            GDSQLExpr.column(&"id", &"team"),
        ),
        &"team",
    ) \
    .project(GDSQLExpr.column(&"name", &"team"), &"team_name") \
    .build()
```

## Expressions

`GDSQLExpr.column()` starts a typed expression. Comparisons accept literal
values or another expression.

| Category | Methods |
|---|---|
| Comparison | `equals`, `not_equals`, `greater_than`, `less_than`, `greater_than_or_equal`, `less_than_or_equal` |
| Logical | `and_`, `or_`, `not_` |
| Null | `is_null`, `is_not_null` |
| Arithmetic | `add`, `subtract`, `multiply`, `divide`, `modulo` |
| Functions | `GDSQLExpr.scalar()`, `GDSQLExpr.aggregate()` |

Use `GDSQLExpr.resource_property()` only for a schema-validated scalar leaf:

```gdscript
var wide_mesh := GDSQLExpr.resource_property(
    &"mesh",
    [&"size", &"x"],
).greater_than(2.0)
```

## Insert, update, and delete

```gdscript
var inserted := database.execute(
    database.table(&"inventory")
        .insert()
        .values({&"item_id": &"iron_sword", &"quantity": 1})
        .build(),
)

var updated := database.execute(
    database.table(&"inventory")
        .update()
        .set_expression(
            &"quantity",
            GDSQLExpr.column(&"quantity").add(1),
        )
        .where(GDSQLExpr.column(&"id").equals(entry_id))
        .build(),
)

var deleted := database.execute(
    database.table(&"inventory")
        .delete()
        .where(GDSQLExpr.column(&"id").equals(entry_id))
        .build(),
)
```

Mutations pass through schema, type, uniqueness, access-mode, and foreign-key
validation. Use an explicit predicate for targeted updates and deletes.

## Transactions

Queries executed through the supplied transaction share one storage session:

```gdscript
var committed := database.transaction(
    func(transaction: GDSQLTransaction) -> void:
        transaction.execute(first_spec)
        transaction.execute(second_spec)
)
```

The first failed query marks the transaction as failed. GDSQL rolls back the
complete session; later calls through that transaction return an aborted
diagnostic. The callback must not retain the transaction after it returns.

## Results and diagnostics

Every operation returns structured diagnostics. Errors make
`is_successful()` false; warnings and information remain available without
turning a successful result into a failure.

`GDSQLQueryResult` exposes:

- `get_rows()` and `get_returned_rows()` for selected rows;
- `get_affected_rows()` for mutations;
- `get_schema()` for result-column metadata;
- `get_diagnostics()` or `diagnostics` for structured failure details.

Rows are `GDSQLRowRecord` values. Read a column with `get_value(&"column")`.
Check the result before consuming rows or affected counts.

# Glossary

### Disclaimer
> Class names in this glossary are intentionally simplified for architectural readability. Publicly exposed Godot classes should use a GDSQL prefix, such as GDSQLDatabase or GDSQLQueryResult, to avoid conflicts with project and third-party classes. Internal classes may retain shorter names when they are not globally registered with class_name.

## State checklist

The checklist below is the implementation status for every glossary concept.
State is cumulative: an entry must pass each earlier state before moving to the
next one.

| Icon | State | Meaning |
|---|---|---|
| 📝 | `Planned` | Documented in the architecture, but no source contract exists yet. |
| 🚧 | `Scaffolded` | The organized source file and typed contract exist; behavior is still absent or intentionally stubbed. |
| 🛠️ | `Implemented` | The documented behavior exists without known placeholder logic. |
| 🧪 | `Tested` | Focused automated tests cover the contract and its expected behavior. |
| ✅ | `Verified` | Boundary/integration validation has passed with its real neighboring services. |

Each responsibility table includes the current implementation state. Update the
state in the same change as implementation or test work.

## Public API and query construction

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `Database` | Public API | Main user-facing entry point for opening a database, building queries, and executing canonical query specs. | `open()`, `query()`, `execute()`, `insert()`, `execute_sql()` | 🚧 |
| `DatabaseContext` | Runtime facade | Coordinates validation, binding, planning, execution, and result materialization. | `execute(query)`, `prepare(query)` | 🚧 |
| `Query` | Fluent API | User-facing fluent query entry point that creates operation-specific builders. | `select()`, `insert()`, `update()`, `delete()` | 🚧 |
| `SelectQueryBuilder` | Fluent API | Builds a `SelectQuerySpec` through a controlled fluent interface. | `from_table()`, `columns()`, `where()`, `join()`, `order_by()`, `limit()`, `offset()`, `build()` | 🚧 |
| `InsertQueryBuilder` | Fluent API | Builds an `InsertQuerySpec` from one or more named rows. | `into_table()`, `values()`, `build()` | 🛠️ |
| `QueryGraph` | Graph frontend | Frontend-owned representation of query nodes and their connections. | `get_nodes()`, `get_connections()`, `validate_structure()` | 🚧 |
| `GraphQueryCompiler` | Graph frontend | Converts a valid `QueryGraph` into a canonical `QuerySpec`. | `compile(graph)` | 🚧 |

## Canonical query model

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `QuerySpec` | Query model | Abstract base for canonical database-operation descriptions. | `accept(visitor)` | 🚧 |
| `SelectQuerySpec` | Query model | Describes a read operation, including sources, projections, predicates, joins, grouping, ordering, and limits. | `accept(visitor)` | 🛠️ |
| `InsertQuerySpec` | Query model | Describes rows to insert into a target table. | `accept(visitor)` | 🛠️ |
| `UpdateQuerySpec` | Query model | Describes assignments and selection criteria for an update operation. | `accept(visitor)` | 🚧 |
| `DeleteQuerySpec` | Query model | Describes the target and selection criteria for a delete operation. | `accept(visitor)` | 🚧 |
| `QuerySpecVisitor` | Query model | Defines type-specific operations over concrete `QuerySpec` classes. | `visit_select()`, `visit_insert()`, `visit_update()`, `visit_delete()` | 🚧 |
| `QuerySource` | Query model | Abstract representation of a source from which rows can be read. | Source-specific accessors | 🚧 |
| `TableReference` | Query model | Identifies a database table and optional alias without loading it. | `get_database_name()`, `get_table_name()`, `get_alias()` | 🛠️ |
| `JoinSpec` | Query model | Describes a join type, source, and condition. | `get_type()`, `get_source()`, `get_condition()` | 🚧 |
| `InsertRow` | Query model | Represents one ordered or named row of values for insertion. | `get_values()` | 🛠️ |
| `ColumnAssignment` | Query model | Associates a target column with an expression used during update. | `get_column()`, `get_expression()` | 🚧 |
| `OrderClause` | Query model | Associates an expression with a sort direction and optional null-ordering rule. | `get_expression()`, `get_direction()` | 🚧 |
| `SortDirection` | Query model | Enumerates ascending and descending ordering. | `ASCENDING`, `DESCENDING` | 🚧 |
| `ComparisonOperator` | Expression model | Enumerates comparison operations. | `EQUAL`, `NOT_EQUAL`, `GREATER_THAN`, `LESS_THAN`, and related values | 🛠️ |
| `LogicalOperator` | Expression model | Enumerates logical composition operations. | `AND`, `OR`, `NOT` | 🛠️ |

## Expression model

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `QueryExpression` | Expression model | Abstract base for canonical expressions used throughout queries. | `accept(visitor)` | 🚧 |
| `ExpressionVisitor` | Expression model | Performs type-specific operations over raw and bound expression nodes. | `visit_column()`, `visit_bound_column()`, `visit_literal()`, `visit_comparison()`, `visit_logical()` | 🚧 |
| `ColumnExpression` | Expression model | Refers to a column by name and optional source alias. | `accept(visitor)` | 🛠️ |
| `LiteralExpression` | Expression model | Holds a literal Godot `Variant` value. | `accept(visitor)` | 🛠️ |
| `ComparisonExpression` | Expression model | Compares two expressions through a `ComparisonOperator`. | `accept(visitor)` | 🛠️ |
| `LogicalExpression` | Expression model | Combines expressions through logical operators. | `accept(visitor)` | 🛠️ |
| `FunctionExpression` | Expression model | Describes a scalar or aggregate function invocation. | `get_name()`, `get_arguments()`, `accept(visitor)` | 🚧 |

## SQL lexical model

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `SqlLexer` | SQL lexer | Converts SQL source text into tokens and lexical diagnostics. | `tokenize(source)` | 🚧 |
| `SqlToken` | SQL lexer | Represents one recognized token with type, source text, value, and position. | `get_type()`, `get_value()`, `get_span()` | 🚧 |
| `TokenizationResult` | SQL lexer | Contains lexer output and diagnostics. | `is_successful()` | 🚧 |
| `SourceSpan` | Diagnostics | Identifies a range in source input. | `get_start()`, `get_end()` | 🚧 |

## SQL syntax model

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `SqlParser` | SQL parser | Converts SQL tokens into a SQL syntax tree. | `parse(tokens)` | 🚧 |
| `SqlParseResult` | SQL parser | Contains the parsed statement and syntax diagnostics. | `is_successful()` | 🚧 |
| `SqlStatement` | SQL AST | Abstract base for SQL statement syntax nodes. | Statement-specific accessors | 🚧 |
| `SqlSelectStatement` | SQL AST | Represents the syntax of a SQL `SELECT` statement. | Access to projections, source, predicates, grouping, ordering, limit, and offset | 🚧 |
| `SqlColumnNode` | SQL AST | Represents a column reference as written in SQL. | `get_name()`, `get_qualifier()` | 🚧 |
| `SqlTableNode` | SQL AST | Represents a table reference as written in SQL. | `get_name()`, `get_alias()` | 🚧 |
| `SqlBinaryExpressionNode` | SQL AST | Represents a SQL binary expression. | `get_left()`, `get_operator()`, `get_right()` | 🚧 |
| `SqlLiteralNode` | SQL AST | Represents a literal value as written in SQL. | `get_value()` | 🚧 |

## SQL compilation

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `SqlQueryCompiler` | SQL compiler | Converts a SQL AST into a canonical `QuerySpec`. | `compile(statement)` | 🚧 |
| `QueryCompilationResult` | SQL compiler | Contains the compiled query and compiler diagnostics. | `is_successful()`, `get_query()` | 🚧 |

## Diagnostics and operation results

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `QueryDiagnostic` | Diagnostics | Represents an informational message, warning, or error from a pipeline stage. | `get_code()`, `get_severity()`, `get_message()` | 🛠️ |
| `OperationResult` | Common results | Generic value-plus-diagnostics result for operations without a specialized result class. | `is_successful()` | 🛠️ |
| `QueryValidationResult` | Validation | Contains validation diagnostics and an optional bound query. | `is_valid()`, `get_bound_query()` | 🛠️ |
| `QueryBindingResult` | Binding | Contains binding diagnostics and an optional bound query. | `is_successful()`, `get_bound_query()` | 🚧 |
| `QueryPlanningResult` | Planning | Contains a generated plan and planning diagnostics. | `is_successful()`, `get_plan()` | 🛠️ |
| `QueryExecutionResult` | Execution | Contains execution output, diagnostics, and optional statistics. | `is_successful()`, `get_rows()` | 🛠️ |
| `StorageOperationResult` | Storage | Describes the outcome of a staged storage mutation. | `is_successful()` | 🛠️ |
| `StorageCommitResult` | Storage | Describes the outcome of persisting a storage session. | `is_successful()` | 🛠️ |

## Validation and binding

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `QueryValidator` | Validation | Abstract contract for validating query semantics against a catalog. | `validate(query)` | 🚧 |
| `DefaultQueryValidator` | Validation | Default implementation of semantic validation and initial binding. | `validate(query)` | 🚧 |
| `BoundQuery` | Binding | Catalog-resolved and type-checked representation of a query. | Access to root operation, referenced tables, and output schema | 🚧 |
| `BoundSelectQuery` | Binding | Bound representation of a select operation. | Access to resolved sources, expressions, and output schema | 🚧 |
| `BoundInsertQuery` | Binding | Bound insert operation containing a resolved target table and validated rows. | Access to target and rows | 🛠️ |
| `BoundQueryOperation` | Binding | Abstract base for resolved query operations. | Operation-specific accessors | 🚧 |
| `BoundColumnExpression` | Binding | Column expression resolved to stable table and column identifiers and a data type. | `get_table_id()`, `get_column_id()`, `get_data_type()` | 🛠️ |
| `TableId` | Identifiers | Stable identifier for a catalog table. | Equality and string representation | 🚧 |
| `ColumnId` | Identifiers | Stable identifier for a catalog column. | Equality and string representation | 🚧 |

## Planning

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `QueryPlanner` | Planning | Converts a bound query into a `QueryPlan`. | `create_plan(query)` | 🚧 |
| `DefaultQueryPlanner` | Planning | Produces deterministic plans for currently supported bound operations. | `create_plan(query)` | 🚧 |
| `QueryPlan` | Planning | Owns the root executable plan node and associated metadata. | `get_root()` | 🚧 |
| `PlanNode` | Planning | Abstract base for executable relational operations. | `accept(visitor)` | 🚧 |
| `PlanNodeVisitor` | Planning | Performs operations over concrete plan node types. | `visit_table_scan()`, `visit_filter()`, `visit_sort()`, and related methods | 🚧 |
| `TableScanPlan` | Planning | Reads all rows available from a table source. | `accept(visitor)` | 🛠️ |
| `PrimaryKeyLookupPlan` | Planning | Retrieves a row through a primary-key lookup. | `accept(visitor)` | 🛠️ |
| `FilterPlan` | Planning | Filters rows from its input according to a predicate. | `accept(visitor)` | 🛠️ |
| `ProjectionPlan` | Planning | Produces selected or calculated output columns. | `accept(visitor)` | 🛠️ |
| `AggregatePlan` | Planning | Groups rows and evaluates aggregate expressions. | `accept(visitor)` | 🚧 |
| `SortPlan` | Planning | Orders rows from its input. | `accept(visitor)` | 🚧 |
| `LimitPlan` | Planning | Applies offset and row-count limits. | `accept(visitor)` | 🛠️ |
| `InsertPlan` | Planning | Stages validated rows for insertion into one resolved table. | `accept(visitor)` | 🛠️ |
| `ResultSchema` | Planning and results | Describes the columns and types produced by a query or plan node. | `get_columns()`, `get_column()` | 🚧 |

## Execution

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `QueryExecutor` | Execution | Abstract contract for executing query plans. | `execute(plan, context)` | 🚧 |
| `DefaultQueryExecutor` | Execution | Default GDScript implementation of query-plan execution. | `execute(plan, context)` | 🚧 |
| `ExecutionContext` | Execution | Groups runtime services and per-execution state. | Service accessors | 🚧 |
| `ExpressionEvaluator` | Execution | Evaluates canonical or bound expressions against a row context. | `evaluate(expression, row_context)` | 🚧 |
| `QueryFunctionRegistry` | Execution | Registers and resolves scalar and aggregate query functions. | `register_function()`, `resolve()` | 🚧 |
| `QueryCancellationToken` | Execution | Communicates cancellation requests to long-running operations. | `cancel()`, `is_cancelled()` | 🚧 |
| `TransactionManager` | Execution | Coordinates storage sessions, commits, and rollbacks. | `begin()`, `commit()`, `rollback()` | 🚧 |

## Catalog

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `CatalogService` | Catalog | Abstract access to database, table, column, and index definitions. | `get_database()`, `get_table()`, `has_table()`, `create_snapshot()` | 🚧 |
| `ConfigFileCatalogService` | Catalog backend | Catalog implementation backed by GDSQL configuration files. | CatalogService implementation | 🛠️ |
| `CatalogSnapshot` | Catalog | Stable catalog view used during validation, binding, and planning. | `get_database()`, `get_table()` | 🚧 |
| `DatabaseDefinition` | Catalog | Typed definition of a logical database. | Access to name and tables | 🛠️ |
| `TableDefinition` | Catalog | Typed definition of a table, its columns, primary key, and indexes. | `get_column()`, `get_primary_key()` | 🛠️ |
| `ColumnDefinition` | Catalog | Typed definition of one table column. | Access to name, type, nullability, uniqueness, and default | 🛠️ |
| `IndexDefinition` | Catalog | Describes an index and the columns it covers. | `get_columns()`, `is_unique()` | 🚧 |

## Storage

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `TableStorage` | Storage | Abstract row-level storage contract used by the runtime. | `read_table()`, `find_by_primary_key()`, `stage_insert()`, `stage_update()`, `stage_delete()`, `commit()`, `rollback()` | 🚧 |
| `ConfigFileTableStorage` | Storage backend | Implements `TableStorage` using ConfigFile-backed `.gsql` files. | TableStorage implementation | 🚧 |
| `StorageSession` | Storage | Tracks loaded data, staged changes, and dirty state for one unit of work. | Session-specific state access | 🛠️ |
| `TableSnapshot` | Storage | Stable collection of rows read from a table for an operation. | `get_rows()`, `find_by_primary_key()` | 🛠️ |
| `RowRecord` | Storage and execution | Typed runtime representation of one row. | `get_value()`, `set_value()`, `has_column()` | 🛠️ |
| `DatabasePathResolver` | Storage infrastructure | Resolves logical database and table identifiers into physical paths. | `resolve_catalog_path()`, `resolve_table_path()` | 🛠️ |
| `ConfigFileCache` | Storage infrastructure | Manages loaded ConfigFile objects and their lifecycle. | `get_or_load()`, `invalidate()`, `flush()` | 🛠️ |
| `GodotVariantCodec` | Serialization | Encodes and decodes Godot-native values at the storage boundary. | `encode()`, `decode()` | 🛠️ |

## Results and materialization

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `RowSet` | Execution results | Internal collection of rows and their result schema. | `get_rows()`, `get_schema()` | 🚧 |
| `QueryResult` | Public results | Stable public representation of query output and diagnostics. | `is_successful()`, `get_rows()`, `get_diagnostics()`, `get_affected_rows()`, `get_returned_rows()` | 🛠️ |
| `ResultMapping` | Mapping | Describes how result columns map into an output representation. | Mapping accessors | 🚧 |
| `ResultMaterializer` | Mapping | Abstract contract for converting a `RowSet` into a user-facing result. | `materialize(rows, mapping)` | 🚧 |
| `DictionaryResultMaterializer` | Mapping | Converts rows into dictionaries. | `materialize()` | 🚧 |
| `ResourceResultMaterializer` | Mapping | Converts rows into Godot resource instances. | `materialize()` | 🚧 |
| `ModelResultMaterializer` | Mapping | Converts rows into optional database model objects. | `materialize()` | 🚧 |
| `EditorTableMaterializer` | Editor mapping | Converts rows into data appropriate for the editor table interface. | `materialize()` | 🚧 |
| `CsvExportMaterializer` | Export mapping | Converts rows into CSV output. | `materialize()` | 🚧 |

## Optional extension concepts

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `DatabaseModel` | Optional model API | Provides convenient model-oriented persistence operations above the canonical query pipeline. | `find()`, `query()`, `save()`, `delete()` | 🚧 |
| `ModelMapper` | Optional model API | Maps model metadata and operations to `QuerySpec` and result mappings. | `to_insert()`, `to_update()`, `materialize()` | 🚧 |
| `MapperCompiler` | Optional mapping extension | Converts an external mapping definition into `QuerySpec` and `ResultMapping`. | `compile()` | 🚧 |

Optional extensions remain above the canonical runtime and do not define its internal architecture.

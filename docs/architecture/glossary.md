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
| `Database` | Public API | Main user-facing entry point for creating, opening, renaming, and dropping a database; managing its tables; executing canonical query specs; and running callback-scoped transactions. | `create()`, `open()`, `rename()`, `drop()`, table administration, `query()`, `execute()`, `transaction()` | 🧪 |
| `DatabaseContext` | Runtime facade | Coordinates catalog administration, validation, binding, planning, execution, shared-session transactions, and result materialization. | Database and table administration methods, `execute(query)`, `transaction(callback)`, `prepare(query)` | 🚧 |
| `Query` | Fluent API | User-facing fluent query entry point that optionally captures a table and creates operation-specific builders. | `table()`, `select()`, `insert()`, `update()`, `delete()` | 🧪 |
| `SelectQueryBuilder` | Fluent API | Builds a `SelectQuerySpec` with projections, aliases, joins, predicates, grouping, aggregate functions, ordering, distinct selection, limits, and offsets. | `from_table()`, joins, projection, `group_by()`, `having()`, aggregate helpers, ordering, pagination, and `build()` | 🧪 |
| `InsertQueryBuilder` | Fluent API | Builds an `InsertQuerySpec` from one or more named rows. | `into_table()`, `values()`, `build()` | 🧪 |
| `UpdateQueryBuilder` | Fluent API | Builds a single-table `UpdateQuerySpec` from typed assignments and an optional predicate. | `table()`, `set_value()`, `set_expression()`, `where()`, `build()` | 🧪 |
| `DeleteQueryBuilder` | Fluent API | Builds a single-table `DeleteQuerySpec` with an optional predicate. | `from_table()`, `where()`, `build()` | 🧪 |
| `Expr` | Expression convenience frontend | Creates the existing canonical typed expressions through compact factories, literal coercion, and immutable fluent combinators without parsing strings. | `column()`, `literal()`, `and_()`, `or_()`, `not_()`, `scalar()`, `aggregate()`, comparison, arithmetic, logical, and null-check helpers | 🧪 |
| `QueryGraph` | Graph frontend | Frontend-owned representation of query nodes and their connections. | `get_nodes()`, `get_connections()`, `validate_structure()` | 🚧 |
| `GraphQueryCompiler` | Graph frontend | Converts a valid `QueryGraph` into a canonical `QuerySpec`. | `compile(graph)` | 🚧 |

## Canonical query model

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `QuerySpec` | Query model | Abstract base for canonical database-operation descriptions. | `accept(visitor)` | 🚧 |
| `SelectQuerySpec` | Query model | Describes a read operation, including sources, projections, predicates, joins, grouping, ordering, distinct selection, and limits. | `accept(visitor)` | 🧪 |
| `InsertQuerySpec` | Query model | Describes rows to insert into a target table. | `accept(visitor)` | 🧪 |
| `UpdateQuerySpec` | Query model | Describes assignments and selection criteria for an update operation. | `accept(visitor)` | 🧪 |
| `DeleteQuerySpec` | Query model | Describes the target and selection criteria for a delete operation. | `accept(visitor)` | 🧪 |
| `QuerySpecVisitor` | Query model | Defines type-specific operations over concrete `QuerySpec` classes. | `visit_select()`, `visit_insert()`, `visit_update()`, `visit_delete()` | 🚧 |
| `QuerySource` | Query model | Abstract representation of a source from which rows can be read. | Source-specific accessors | 🚧 |
| `TableReference` | Query model | Identifies a database table and optional alias without loading it. | `get_database_name()`, `get_table_name()`, `get_alias()` | 🛠️ |
| `JoinSpec` | Query model | Describes an inner, left, right, or full join source and condition; right and full execution remain scaffolded. | Constructor and access to type, source, and condition | 🧪 |
| `InsertRow` | Query model | Represents one ordered or named row of values for insertion. | `get_values()` | 🛠️ |
| `SelectProjection` | Query model | Associates a selected expression with an optional public result alias. | Access to expression and alias | 🧪 |
| `ColumnAssignment` | Query model | Associates a target column with an expression used during update. | Access to column and expression | 🧪 |
| `OrderClause` | Query model | Associates an expression with a sort direction. | Access to expression and direction | 🧪 |
| `SortDirection` | Query model | Enumerates ascending and descending ordering. | `ASCENDING`, `DESCENDING` | 🧪 |
| `ComparisonOperator` | Expression model | Enumerates comparison operations. | `EQUAL`, `NOT_EQUAL`, `GREATER_THAN`, `LESS_THAN`, and related values | 🛠️ |
| `LogicalOperator` | Expression model | Enumerates logical composition operations. | `AND`, `OR`, `NOT` | 🛠️ |
| `ArithmeticOperator` | Expression model | Enumerates scalar arithmetic operations. | `ADD`, `SUBTRACT`, `MULTIPLY`, `DIVIDE`, `MODULO` | 🧪 |
| `NullCheckOperator` | Expression model | Enumerates explicit null checks. | `IS_NULL`, `IS_NOT_NULL` | 🧪 |

## Expression model

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `QueryExpression` | Expression model | Abstract base for canonical expressions used throughout queries and shared host for immutable fluent expression combinators. | `accept(visitor)`, comparison, arithmetic, logical, and null-check combinators | 🚧 |
| `ExpressionVisitor` | Expression model | Performs type-specific operations over raw and bound expression nodes. | Visit methods for column, literal, comparison, logical, arithmetic, null-check, and function expressions | 🚧 |
| `ColumnExpression` | Expression model | Refers to a column by name and optional source alias. | `accept(visitor)` | 🛠️ |
| `LiteralExpression` | Expression model | Holds a literal Godot `Variant` value. | `accept(visitor)` | 🛠️ |
| `ComparisonExpression` | Expression model | Compares compatible expressions through a `ComparisonOperator`, propagating null as unknown. | `accept(visitor)` | 🧪 |
| `LogicalExpression` | Expression model | Combines boolean or unknown expressions through three-valued logical operators. | `accept(visitor)` | 🧪 |
| `ArithmeticExpression` | Expression model | Applies numeric arithmetic or string addition to two scalar expressions. | `accept(visitor)` | 🧪 |
| `NullCheckExpression` | Expression model | Tests whether an expression evaluates to null. | `accept(visitor)` | 🧪 |
| `FunctionExpression` | Expression model | Describes a validated scalar or aggregate function invocation. | Access to name and arguments, `accept(visitor)` | 🧪 |
| `QueryFunctionDefinition` | Expression model | Describes a function name, arity, return type, and aggregate classification without execution behavior. | `accepts_argument_count()` and definition fields | 🧪 |
| `QueryFunctionCatalog` | Expression model | Resolves function definitions for frontend construction and query validation. | `register_function()`, `resolve()`, `contains()` | 🧪 |

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
| `Diagnostics` | Diagnostics | Reusable diagnostic collection that inspects severity and performs explicitly requested debug reporting. | `add()`, `merge()`, `has_errors()`, `is_successful()`, `print_to_debug()` | 🛠️ |
| `OperationResult` | Common results | Generic value-plus-result that composes `Diagnostics` for operations without a specialized result class. | `is_successful()`, `get_value()` | 🛠️ |
| `CatalogOperationResult` | Catalog results | Contains the value and structured diagnostics produced by a catalog structure mutation. | `is_successful()`, `get_value()` | 🛠️ |
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
| `DefaultQueryValidator` | Validation | Default implementation of semantic validation and initial binding. | `validate(query)` | 🧪 |
| `BoundQuery` | Binding | Catalog-resolved and type-checked representation of a query. | Access to root operation, referenced tables, and output schema | 🚧 |
| `BoundSelectQuery` | Binding | Bound representation of a select operation, including its primary source, joins, projections, ordering, distinct selection, limit, and offset. | Access to resolved sources and select clauses | 🧪 |
| `BoundTableSource` | Binding | Associates a resolved table with its query alias and join-derived nullability. | `get_qualifier()` and source metadata | 🧪 |
| `BoundJoin` | Binding | Associates a supported join type with its resolved source and bound condition. | Access to type, source, and condition | 🧪 |
| `BoundInsertQuery` | Binding | Bound insert operation containing a resolved target table and validated rows. | Access to target and rows | 🛠️ |
| `BoundUpdateQuery` | Binding | Bound update operation containing a resolved target, assignments, and predicate. | Access to target, assignments, and predicate | 🧪 |
| `BoundDeleteQuery` | Binding | Bound delete operation containing a resolved target and predicate. | Access to target and predicate | 🧪 |
| `BoundQueryOperation` | Binding | Abstract base for resolved query operations. | Operation-specific accessors | 🚧 |
| `BoundColumnExpression` | Binding | Column expression resolved to stable table and column identifiers, source occurrence qualifier, data type, and nullability. | Access to table ID, column ID, source qualifier, data type, and nullability | 🧪 |
| `TableId` | Identifiers | Stable identifier for a catalog table. | Equality and string representation | 🚧 |
| `ColumnId` | Identifiers | Stable identifier for a catalog column. | Equality and string representation | 🚧 |

## Planning

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `QueryPlanner` | Planning | Converts a bound query into a `QueryPlan`. | `create_plan(query)` | 🚧 |
| `DefaultQueryPlanner` | Planning | Produces deterministic plans for currently supported bound operations. | `create_plan(query)` | 🧪 |
| `QueryPlan` | Planning | Owns the root executable plan node and associated metadata. | `get_root()` | 🚧 |
| `PlanNode` | Planning | Abstract base for executable relational operations. | `accept(visitor)` | 🚧 |
| `PlanNodeVisitor` | Planning | Performs operations over concrete plan node types. | `visit_table_scan()`, `visit_filter()`, `visit_sort()`, and related methods | 🚧 |
| `TableScanPlan` | Planning | Reads all rows available from a table source. | `accept(visitor)` | 🛠️ |
| `PrimaryKeyLookupPlan` | Planning | Retrieves a row through a primary-key lookup. | `accept(visitor)` | 🛠️ |
| `IndexLookupPlan` | Planning | Retrieves rows through an exact single-column lookup on a catalog index when supported by storage. | `accept(visitor)` | 🧪 |
| `RangeLookupPlan` | Planning | Retrieves rows through a bounded single-column index lookup when supported by storage. | `accept(visitor)` | 🧪 |
| `FilterPlan` | Planning | Filters rows from its input according to a predicate. | `accept(visitor)` | 🛠️ |
| `NestedLoopJoinPlan` | Planning | Joins two plan inputs by evaluating a bound condition for each candidate row pair. | `accept(visitor)` | 🧪 |
| `ProjectionPlan` | Planning | Produces selected or calculated output columns. | `accept(visitor)` | 🛠️ |
| `AggregatePlan` | Planning | Groups rows and evaluates registered aggregate expressions before HAVING, ordering, and projection. | `accept(visitor)` | 🧪 |
| `SortPlan` | Planning | Orders rows from its input using one or more bound order clauses. | `accept(visitor)` | 🧪 |
| `DistinctPlan` | Planning | Removes duplicate rows after projection and before limit or offset. | `accept(visitor)` | 🧪 |
| `LimitPlan` | Planning | Applies offset and row-count limits. | `accept(visitor)` | 🛠️ |
| `InsertPlan` | Planning | Stages validated rows for insertion into one resolved table. | `accept(visitor)` | 🛠️ |
| `UpdatePlan` | Planning | Applies validated assignments to matching rows in one resolved table. | `accept(visitor)` | 🧪 |
| `DeletePlan` | Planning | Deletes matching rows from one resolved table. | `accept(visitor)` | 🧪 |
| `ResultSchema` | Planning and results | Describes the names and types produced by a query or plan node, including projection aliases. | `get_columns()`, `get_column()` | 🧪 |

## Execution

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `QueryExecutor` | Execution | Abstract contract for executing query plans. | `execute(plan, context)` | 🚧 |
| `DefaultQueryExecutor` | Execution | Default GDScript implementation of query-plan execution. | `execute(plan, context)` | 🧪 |
| `ExecutionContext` | Execution | Groups runtime services and per-execution state. | Service accessors | 🚧 |
| `ExpressionEvaluator` | Execution | Evaluates canonical or bound scalar expressions against a row context with null propagation. | `evaluate(expression, row_context)` | 🧪 |
| `QueryFunctionRegistry` | Execution | Associates query-function definitions with executable scalar and aggregate callables. | `register_function()`, `register_aggregate_function()`, `resolve()`, `resolve_aggregate()` | 🧪 |
| `QueryCancellationToken` | Execution | Communicates cancellation requests to long-running operations. | `cancel()`, `is_cancelled()` | 🚧 |
| `TransactionManager` | Execution | Coordinates storage sessions, commits, and rollbacks. | `begin()`, `commit()`, `rollback()` | 🧪 |
| `Transaction` | Public transaction scope | Executes multiple queries through one storage session, observes earlier staged writes, and automatically commits or rolls back when its callback exits. The scope cannot be reused afterward. | `execute()` within `Database.transaction(callback)` | 🧪 |

## Catalog

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `CatalogService` | Catalog | Abstract access to database, table, column, and index definitions. | `get_database()`, `get_table()`, `has_table()`, `create_snapshot()` | 🚧 |
| `ConfigFileCatalogService` | Catalog backend | Catalog implementation backed by GDSQL configuration files. | CatalogService implementation | 🛠️ |
| `CatalogAdministrationService` | Catalog | Abstract contract for database and table lifecycle changes without exposing storage formats to the public API. | `create_database()`, `rename_database()`, `drop_database()`, `create_table()`, `rename_table()`, `alter_table()`, `drop_table()` | 🧪 |
| `ConfigFileCatalogAdministrationService` | Catalog backend | Persists database registrations and synchronizes ConfigFile-backed schemas and row storage during lifecycle changes. | CatalogAdministrationService implementation | 🧪 |
| `CatalogSnapshot` | Catalog | Stable catalog view used during validation, binding, and planning. | `get_database()`, `get_table()` | 🚧 |
| `DatabaseDefinition` | Catalog | Typed definition of a logical database. | Access to name and tables | 🛠️ |
| `TableDefinition` | Catalog | Typed definition of a table, its columns, primary key, indexes, and common timestamp helpers. | `add_column()`, `add_index()`, `add_timestamps()`, `get_column()`, `get_primary_key()`, `get_index()` | 🧪 |
| `ColumnDefinition` | Catalog | Typed definition of one table column, including an optional static default, generated-value policy, integer primary-key auto-increment, and the rule that `TYPE_OBJECT` accepts Resources only. | `set_default()`, `clear_default()`, `has_default()`, `get_default_value()`, `accepts_value()`, `created_at()`, `updated_at()` | 🧪 |
| `ColumnDefault` | Catalog | Wraps a declared static default so an explicit null value remains distinct from no default and future default metadata can evolve without parallel column state. | `value` | 🧪 |
| `TableAlteration` | Catalog | Typed intent for adding, renaming, or dropping one table column. | `add_column()`, `rename_column()`, `drop_column()` | 🧪 |
| `IndexDefinition` | Catalog | Describes a named index, its ordered columns, and whether its complete value must be unique. | `get_columns()`, `is_unique()` | 🧪 |

## Storage

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `TableStorage` | Storage | Abstract row-level storage contract used by the runtime. | `get_capabilities()`, `read_table()`, primary-key/index/range lookup, staged mutations, `commit()`, `rollback()` | 🚧 |
| `StorageCapabilities` | Storage | Reports optional exact-index and range-index lookup operations supported by a storage backend without exposing its implementation. | `supports_exact_index_lookup()`, `supports_range_index_lookup()` | 🧪 |
| `StorageBackendIds` | Storage metadata | Defines stable storage backend identifiers and their UI-facing labels. | `get_all()`, `is_valid()`, `get_display_name()` | 🧪 |
| `ConfigFileTableStorage` | Storage backend | Implements `TableStorage` using ConfigFile-backed `.cfg` files, with atomic query commits, maintained index entries, final-state uniqueness validation, table metadata, and transactional auto-increment generation. | TableStorage implementation | 🧪 |
| `PagedBinaryTableStorage` | Storage backend | Future backend that stores each logical table in one paged binary file and loads row or index pages independently through the shared `TableStorage` contract. | TableStorage implementation | 📝 |
| `BinaryTableHeader` | Binary storage metadata | Future per-table header containing format version, schema fingerprint, page layout, row metadata, generated-key state, and page roots. | Header encoding and validation | 📝 |
| `StorageSession` | Storage | Tracks staged changes, dirty state, and uncommitted table metadata reservations for one unit of work. | Session-specific state access | 🧪 |
| `TableSnapshot` | Storage | Stable collection of rows read from a table for an operation. | `get_rows()`, `find_by_primary_key()` | 🛠️ |
| `RowRecord` | Storage and execution | Typed runtime representation of one row, including source-qualified values for multi-table evaluation. | `get_value()`, `get_source_value()`, `set_source_values()`, mutation and lookup helpers | 🧪 |
| `DatabasePathResolver` | Storage infrastructure | Resolves logical database and table identifiers into physical paths. | `resolve_catalog_path()`, `resolve_table_path()` | 🛠️ |
| `ConfigFileCache` | Storage infrastructure | Manages loaded ConfigFile objects and their lifecycle. | `get_or_load()`, `invalidate()`, `flush()` | 🛠️ |
| `GodotVariantCodec` | Serialization | Encodes and decodes Godot-native values at the storage boundary, including explicit nulls and native or custom Resources. | `encode()`, `decode()` | 🧪 |

## Runtime persistence

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `BufferedTableStorage` | Storage composition | Keeps lazily loaded tables and indexes in memory, tracks committed dirty state, and delegates durable persistence to another storage backend. | TableStorage implementation and checkpoint participation | 📝 |
| `InMemoryTableStorage` | Storage backend | Provides authoritative temporary table storage without requiring a persistent source. | TableStorage implementation | 📝 |
| `DatabaseRegistry` | Database lifecycle | Registers open database handles, resolves replaceable logical roles, and delegates durable registration snapshots for runtime and editor composition. | `register()`, `resolve()`, role binding, `load_snapshot()`, `save_snapshot()` | 🧪 |
| `DatabaseRegistration` | Database lifecycle metadata | Describes one durable registration through its public name, logical database name, data root, and validated storage backend identifier. | Typed registration fields | 🧪 |
| `DatabaseRegistryStore` | Database lifecycle persistence | Abstract persistence boundary for complete typed registration and role-binding snapshots. | `load_snapshot()`, `save_snapshot()` | 🚧 |
| `ConfigFileDatabaseRegistryStore` | Database lifecycle persistence | Stores editor-visible database registrations and role bindings in `user://gdsql/databases.cfg`. | DatabaseRegistryStore implementation | 🧪 |
| `CheckpointTarget` | Runtime persistence | Contract for a storage composition that reports committed dirty state and transfers it to durable storage. | `is_dirty()`, `checkpoint()` | 🧪 |
| `PersistenceCoordinator` | Runtime persistence | Applies persistence policies, inspects committed dirty state, and coordinates explicit or commit-triggered checkpoints. | `register()`, `checkpoint()`, `checkpoint_dirty()`, `transaction_committed()` | 🧪 |
| `ContentOverlayLoader` | Runtime content loading | Validates and deterministically combines immutable base content with enabled mod layers into one reproducible effective content database. | `build_effective_database()`, cache invalidation and provenance diagnostics | 📝 |
| `ContentCacheManifest` | Runtime content loading | Fingerprints the base content version, enabled mod versions or checksums, and deterministic load order for a disposable effective-content cache. | Compatibility inspection and cache fingerprint metadata | 📝 |
| `ContentLoadingPolicy` | Runtime content loading | Selects complete, lazy-table, paged, or manual loading for the active effective-content working set. | `LOAD_ALL`, `LAZY_TABLES`, `PAGED`, `MANUAL` | 📝 |
| `CheckpointPolicy` | Runtime persistence | Describes immediate, periodic, manual, or exit-time persistence behavior independently from transaction semantics. | `immediate()`, `periodic()`, `manual()`, `on_exit()`, interval metadata | 🧪 |
| `CheckpointResult` | Runtime persistence | Reports checkpointed databases, remaining dirty databases, and structured persistence diagnostics. | `is_successful()`, `mark_checkpointed()`, `mark_dirty()` | 🧪 |
| `RuntimeNode` | Godot runtime adapter | Optional Node or autoload that supplies a top-level runtime API, timers, lifecycle notifications, and signals while delegating to the database registry, content loader, and persistence coordinator. | Database registration, role selection, rebuild/checkpoint delegation, runtime signals | 📝 |

## Results and materialization

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `RowSet` | Execution results | Internal collection of rows and their result schema. | `get_rows()`, `get_schema()` | 🚧 |
| `DatabaseResult` | Public results | Contains a database handle or structured diagnostics from `Database.create()` and `Database.open()`. | `is_successful()`, `get_database()` | 🧪 |
| `QueryResult` | Public results | Stable public representation of query output and schema that inherits the composed diagnostics behavior from `OperationResult`. | `is_successful()`, `get_rows()`, `get_schema()`, `get_diagnostics()`, `get_affected_rows()`, `get_returned_rows()`, `materialize()` | 🧪 |
| `ResultMapping` | Mapping | Selects result columns, assigns output names, and optionally identifies a target Resource script. | `map_column()`, `get_target_name()`, `get_source_columns()`, `for_resource()` | 🧪 |
| `ResultMaterializer` | Mapping | Abstract contract for converting a `RowSet` into a user-facing value while retaining result diagnostics and metadata. | `materialize(rows, mapping)` | 🧪 |
| `DictionaryResultMaterializer` | Mapping | Converts each selected row into an independent dictionary using optional column renaming. | `materialize()` | 🧪 |
| `ResourceResultMaterializer` | Mapping | Instantiates one custom Resource per row and assigns mapped columns to declared properties. | `materialize()` | 🧪 |
| `ModelResultMaterializer` | Mapping | Converts rows into registered model objects and attaches their model context and persisted state. | `materialize()` | 🧪 |
| `EditorTableMaterializer` | Editor mapping | Converts rows into data appropriate for the editor table interface. | `materialize()` | 🚧 |
| `CsvExportMaterializer` | Export mapping | Converts rows into CSV output. | `materialize()` | 🚧 |

## Model API and relationships

| Name | Domain | Responsibility | Principal API | State |
|---|---|---|---|---|
| `Model` | Model API | Shared base for role-scoped metadata, materialized identity, change tracking, context retention, and persisted-row operations. | metadata, `is_persisted()`, `save()`, `refresh()`, `delete()` | 🧪 |
| `ContentModel` | Model API | Read-only model bound through the model registry to the effective `content` database role. | Query and refresh; mutation diagnostics | 🧪 |
| `SaveModel` | Model API | Mutable model bound through the model registry to the active save-slot database; save-slot management remains in the database registry. | Query, refresh, save, and delete | 🧪 |
| `SettingsModel` | Model API | Mutable model bound to project-wide user settings that remain independent from the selected save slot. | Query, refresh, save, and delete | 🧪 |
| `ModelAccess` | Model metadata | Declares whether a standard or project-defined model role permits reads or canonical mutations. | `READ_ONLY`, `READ_WRITE` | 🧪 |
| `ModelDefinition` | Model metadata | Captures a registered model script, logical role, table, primary key, and access mode. | Typed definition fields | 🧪 |
| `ModelRegistry` | Model API | Registers model classes and resolves their typed metadata and logical roles through `DatabaseRegistry`. | `register()`, `resolve_model()`, `resolve_role()` | 🧪 |
| `Models` | Model API | Holds the configured default model context and supplies static model query and find forwarding. | `configure()`, `query()`, `find()`, `clear_context()` | 🧪 |
| `ModelContext` | Model API | Supplies an injectable model registry for default runtime composition, tests, and isolated runtimes. | `register_model()`, `query()`, `find()` | 🧪 |
| `ModelQuery` | Model API | Model-oriented SELECT frontend that translates filters, ordering, limits, offsets, and distinct selection into canonical `QuerySpec`. | `where()`, `order_by()`, `all()`, `first()`, `find()`, `to_query_spec()` | 🧪 |
| `RelationshipDefinition` | Optional model API | Typed model-level declaration of a has-one, has-many, belongs-to, or many-to-many relationship that supports eager loading and editor display of related identifiers. | Relationship constructors, key accessors, and eager-loading metadata | 📝 |

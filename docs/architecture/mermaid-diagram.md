flowchart TD

%% =========================================================
%% VISUAL THEME
%% =========================================================

classDef frontend fill:#E8F1FF,stroke:#3B82F6,stroke-width:2px,color:#172554;
classDef translation fill:#F3E8FF,stroke:#8B5CF6,stroke-width:2px,color:#3B0764;
classDef canonical fill:#FFF7D6,stroke:#D97706,stroke-width:2px,color:#451A03;
classDef validation fill:#FCE7F3,stroke:#DB2777,stroke-width:2px,color:#500724;
classDef planning fill:#FFEDD5,stroke:#EA580C,stroke-width:2px,color:#431407;
classDef execution fill:#DCFCE7,stroke:#16A34A,stroke-width:2px,color:#052E16;
classDef catalog fill:#E0F2FE,stroke:#0284C7,stroke-width:2px,color:#082F49;
classDef storage fill:#CCFBF1,stroke:#0F766E,stroke-width:2px,color:#042F2E;
classDef result fill:#F1F5F9,stroke:#475569,stroke-width:2px,color:#0F172A;
classDef runtime fill:#EDE9FE,stroke:#7C3AED,stroke-width:3px,color:#2E1065;
classDef implementation fill:#FFFFFF,stroke:#64748B,stroke-width:2px,color:#0F172A;

Code("`**Code API**

-
*Purpose:* Describe and execute database operations from GDScript
*API:* GDSQLDatabase and GDSQLQuery
*Routes through:* Fluent query builders`")

GraphInterface("`**Graph Interface**

-
*Purpose:* Describe queries through graph nodes and connections
*API:* GDSQLQueryGraph and GDSQLGraphQueryCompiler
*Produces:* GDSQLQuerySpec`")

SQLText("`**SQL Text**

-
*Purpose:* Describe queries using SQL syntax
*API:* tokenize(), parse(), compile()
*Produces:* GDSQLQuerySpec`")

Database("`**GDSQLDatabase**

-
*Purpose:* Public database-scoped facade
*API:* create(), open(), rename(), drop(), query(), table(), execute(), transaction()
*Table API:* create_table(), rename_table(), alter_table(), drop_table()
*Delegates to:* GDSQLDatabaseContext and query frontends`")

Transaction("`**GDSQLTransaction**

-
*Purpose:* Scope multiple canonical queries to one storage session
*API:* execute(query) inside Database.transaction(callback)
*Lifecycle:* One callback; commit on success, rollback on failure
*Visibility:* Reads observe earlier staged writes`")

RuntimeRegistry("`**GDSQLDatabaseRegistry**

-
*Purpose:* Register database handles and select active logical roles
*Lifecycle API:* register(), unregister(), resolve()
*Role API:* bind_role(), resolve_role(), unbind_role()
*Standard roles:* content, save and settings
*Durable metadata:* user://gdsql/databases.cfg through DatabaseRegistryStore
*Returns:* GDSQLDatabaseResult with structured diagnostics`")

Models("`**Model API**

-
*Purpose:* Query role-scoped tables and materialize typed model objects
*Types:* Model, ContentModel, SaveModel, SettingsModel
*Static API:* Model.query(), Model.find(identity)
*Query API:* where(), with(), order_by(), all(), first(), to_query_spec()
*Instance API:* get_related(), is_relationship_loaded(), save(), refresh(), delete()
*Relationships:* Typed belongs-to, has-one and has-many definitions
*Configuration:* GDSQLModels receives one default ModelContext
*Resolution:* ModelRegistry to DatabaseRegistry roles
*Returns:* QueryResult containing model objects in value`")

Persistence("`**Runtime Persistence**

-
*Purpose:* Transfer committed dirty state to durable storage
*Coordinator API:* register(), checkpoint(), checkpoint_dirty(), transaction_committed()
*Policy API:* immediate(), periodic(), manual(), on_exit()
*Target API:* is_dirty(), checkpoint()
*Returns:* GDSQLCheckpointResult with durable and remaining-dirty databases`")

Factory("`**GDSQLRuntimeFactory**

-
*Purpose:* Assemble one compatible runtime object graph
*API:* create_default(data_root)
*Creates:* GDSQLDatabaseContext
*Injects:* Catalog, storage, validation, planning and execution services`")

Frontends("`**Query Frontends**

-
*Purpose:* Translate frontend-specific input into the canonical model
*Fluent API:* select(), insert(), update(), delete(), build()
*Compiler API:* compile(input)
*Produces:* GDSQLQuerySpec`")

Expr("`**GDSQLExpr**

-
*Purpose:* Build canonical expressions with compact typed GDScript
*Factory API:* column(), literal(), scalar(), aggregate()
*Logical API:* and_(), or_(), not_()
*Fluent API:* Comparison, arithmetic, logical and null-check combinators
*Produces:* Existing GDSQLQueryExpression nodes`")

QuerySpec("`**GDSQLQuerySpec**

-
*Purpose:* Canonical and frontend-independent query description
*API:* accept(visitor)
*Parent of:* SelectQuerySpec, InsertQuerySpec, UpdateQuerySpec, DeleteQuerySpec
*Contains:* Projections, joins, ordering, sources, expressions, rows and assignments`")

Expression("`**GDSQLQueryExpression**

-
*Purpose:* Describe values, references and predicates without evaluating them
*API:* accept(visitor)
*Parent of:* Column, literal, comparison, logical and function expressions
*Resolved form:* GDSQLBoundColumnExpression`")

Context("`**GDSQLDatabaseContext**

-
*Purpose:* Coordinate query and catalog operations through injected contracts
*API:* execute(query), transaction(callback), prepare(query), database and table lifecycle methods
*Calls:* Validator → planner → executor
*Depends on:* Abstract catalog, storage, validation, planning and execution services`")

Validator("`**GDSQLQueryValidator**

-
*Purpose:* Validate query meaning and resolve single or multi-source catalog references
*API:* validate(query)
*Returns:* GDSQLQueryValidationResult containing GDSQLBoundQuery
*Extended by:* GDSQLDefaultQueryValidator`")

BoundQuery("`**GDSQLBoundQueryOperation**

-
*Purpose:* Represent a catalog-resolved operation ready for planning
*Owned by:* GDSQLBoundQuery
*Parent of:* BoundSelect, BoundInsert, BoundUpdate and BoundDelete
*Uses:* Stable table and column identifiers`")

Planner("`**GDSQLQueryPlanner**

-
*Purpose:* Choose executable operations for a bound query
*API:* create_plan(bound_query)
*Returns:* GDSQLQueryPlanningResult containing GDSQLQueryPlan
*Extended by:* GDSQLDefaultQueryPlanner`")

PlanNode("`**GDSQLPlanNode**

-
*Purpose:* Represent one executable operation in a query plan
*API:* accept(visitor)
*Read nodes:* Scan, primary-key, exact-index, range-index, join, filter, aggregate, sort, projection, distinct and limit
*Mutation nodes:* Insert, update and delete`")

Executor("`**GDSQLQueryExecutor**

-
*Purpose:* Execute a query plan using runtime service contracts
*API:* execute(plan, execution_context)
*Returns:* GDSQLQueryExecutionResult
*Extended by:* GDSQLDefaultQueryExecutor`")

CatalogService("`**GDSQLCatalogService**

-
*Purpose:* Provide read-only access to typed database structure
*API:* get_database(), get_table(), has_table(), create_snapshot()
*Returns:* Database, table and column definitions
*Extension point:* Catalog backend implementations`")

CatalogAdministration("`**GDSQLCatalogAdministrationService**

-
*Purpose:* Manage database and table lifecycle without exposing storage format
*Database API:* create_database(), rename_database(), drop_database()
*Table API:* create_table(), rename_table(), alter_table(), drop_table()
*Extension point:* Catalog administration backend implementations`")

TableStorage("`**GDSQLTableStorage**

-
*Purpose:* Isolate row persistence from query execution
*Read API:* read_table(), primary-key/index/range lookup, get_capabilities()
*Mutation API:* stage_insert(), stage_update(), stage_delete()
*Transaction API:* commit(), rollback()
*Extension point:* Table storage backend implementations`")

subgraph ConfigFileBackend["ConfigFile backend"]
ConfigCatalog("`**GDSQLConfigFileCatalogService**

-
*Purpose:* Read typed catalog metadata from ConfigFile resources
*API:* get_database(), get_table(), has_table(), create_snapshot()
*Extends:* GDSQLCatalogService
*Uses:* GDSQLDatabasePathResolver`")

ConfigAdministration("`**GDSQLConfigFileCatalogAdministrationService**

-
*Purpose:* Persist database and table lifecycle operations using ConfigFile resources
*API:* create, rename, alter and drop database or table structures
*Extends:* GDSQLCatalogAdministrationService
*Uses:* Catalog reader, path resolver and ConfigFile cache`")

ConfigStorage("`**GDSQLConfigFileTableStorage**

-
*Purpose:* Persist table rows as ConfigFile sections and values
*API:* Read, primary-key/index/range lookup, staged mutations, commit and rollback
*Maintains:* Reserved index entries during committed mutations
*Extends:* GDSQLTableStorage
*Uses:* Path resolver, ConfigFile cache and Variant codec`")

ConfigInfrastructure("`**ConfigFile Infrastructure**

-
*Purpose:* Contain ConfigFile-specific paths, caching and serialization
*Path API:* resolve_catalog_path(), resolve_schema_path(), resolve_table_path()
*Cache API:* get_or_load(), invalidate(), flush()
*Types:* GDSQLDatabasePathResolver, GDSQLConfigFileCache, GDSQLGodotVariantCodec`")
end

subgraph InMemoryBackend["In-memory backend"]
MemoryStorage("`**GDSQLInMemoryTableStorage**

-
*Purpose:* Keep authoritative table rows in memory
*API:* Read, lookup, staged mutations, commit and rollback
*State:* Committed rows, table metadata and dirty versions
*Extends:* GDSQLTableStorage`")

MemoryCheckpoint("`**GDSQLInMemoryCheckpointTarget**

-
*Purpose:* Transfer dirty in-memory tables to durable storage
*API:* is_dirty(), checkpoint()
*Uses:* In-memory source and injected durable GDSQLTableStorage
*Extends:* GDSQLCheckpointTarget`")
end

Results("`**GDSQLOperationResult**

-
*Purpose:* Carry operation values and structured diagnostics across boundaries
*API:* is_successful(), get_value()
*Composes:* GDSQLDiagnostics and GDSQLQueryDiagnostic
*Parent of:* Database, query, validation, planning, execution and storage results`")

Materialization("`**Result Materialization**

-
*Purpose:* Convert execution rows into user-facing values
*API:* QueryResult.materialize(), ResultMaterializer.materialize()
*Types:* ResultMapping, DictionaryResultMaterializer, ResourceResultMaterializer
*Returns:* QueryResult with materialized OperationResult.value`")

Code -->|"create() · open() · query() · execute() · transaction()"| Database
GraphInterface -->|"compile(graph)"| Frontends
SQLText -->|"tokenize() · parse() · compile()"| Frontends
Database -->|"query() · table()"| Frontends
Frontends -->|"build() / compile()"| QuerySpec
Code -->|"column() · literal() · logical and function factories"| Expr
Expr -->|"creates canonical nodes"| Expression
Expression -->|"contained by"| QuerySpec

Database -->|"execute(query) · lifecycle methods"| Context
Database -->|"transaction(callback)"| Transaction
Code -->|"register handles · select roles"| RuntimeRegistry
RuntimeRegistry -->|"resolve() · resolve_role()"| Database
Code -->|"Model.query() · Model.find(identity)"| Models
Models -->|"resolve_role(model)"| RuntimeRegistry
Models -->|"to_query_spec()"| QuerySpec
Models -->|"ModelResultMaterializer"| Materialization
Code -->|"checkpoint() · checkpoint_dirty()"| Persistence
Persistence -->|"target.checkpoint()"| MemoryCheckpoint
Transaction -->|"execute(query, shared session)"| Context
QuerySpec -->|"execute(query) / prepare(query)"| Context
Context -->|"validate(query)"| Validator
Validator -->|"GDSQLQueryValidationResult"| BoundQuery
BoundQuery -->|"create_plan(bound_query)"| Planner
Planner -->|"GDSQLQueryPlan(root)"| PlanNode
PlanNode -->|"execute(plan, execution_context)"| Executor
Executor -->|"GDSQLQueryExecutionResult"| Results
Results -->|"materialize(materializer, mapping)"| Materialization
Context -->|"GDSQLDatabaseResult / GDSQLQueryResult"| Results

Context -->|"catalog lifecycle API"| CatalogAdministration
Validator -->|"get_table() · create_snapshot()"| CatalogService
Executor -->|"read_table() · find_by_primary_key()"| TableStorage
Executor -->|"stage_*() · commit() · rollback()"| TableStorage

CatalogService -->|"extended by"| ConfigCatalog
CatalogAdministration -->|"extended by"| ConfigAdministration
TableStorage -->|"extended by"| ConfigStorage
TableStorage -->|"extended by"| MemoryStorage

MemoryCheckpoint -->|"reads dirty table versions"| MemoryStorage
MemoryCheckpoint -->|"stages and commits durable changes"| TableStorage

ConfigCatalog -->|"path resolution"| ConfigInfrastructure
ConfigAdministration -->|"paths · cache"| ConfigInfrastructure
ConfigStorage -->|"paths · cache · codec"| ConfigInfrastructure

Factory -.->|"create_default(data_root)"| Context
Factory -.->|"constructs and injects"| ConfigInfrastructure
Factory -.->|"create_in_memory(data_root)"| MemoryStorage

class Code,GraphInterface,SQLText,Expr,Models frontend;
class Database,Context,Factory,Transaction,RuntimeRegistry,Persistence runtime;
class Frontends translation;
class QuerySpec,Expression canonical;
class Validator,BoundQuery validation;
class Planner,PlanNode planning;
class Executor execution;
class CatalogService,CatalogAdministration catalog;
class TableStorage storage;
class ConfigCatalog,ConfigAdministration,ConfigStorage,ConfigInfrastructure,MemoryStorage,MemoryCheckpoint implementation;
class Results,Materialization result;

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

subgraph FrontendLayer["Front ends"]
direction LR

Code("`**Direct Code API**

-
*Purpose:* Manage databases and execute canonical operations from GDScript
*Database API:* GDSQLDatabase create, open, rename, drop and table administration
*Query API:* GDSQLQuery, fluent builders and GDSQLExpr
*Produces:* GDSQLQuerySpec through fluent builders`")

Models("`**Model API**

-
*Purpose:* Query role-scoped tables and materialize typed model objects
*Types:* Model, ContentModel, SaveModel, SettingsModel
*Static API:* Model.query(), Model.find(identity)
*Query API:* where(), with(), order_by(), all(), first(), to_query_spec()
*Instance API:* get_related(), save(), refresh(), delete()
*Resolution:* ModelRegistry to DatabaseRegistry roles`")

subgraph EditorFrontends["Editor workbench"]
direction TB

Workbench("`**GDSQLWorkbench**

-
*Purpose:* Explore and manipulate registered databases, tables and rows
*Collection API:* load(), discover_root(), discover_children(), select_registration()
*Session API:* select_table(), load_rows(), preview_table_change(), apply_pending_change()
*Metadata:* Lightweight catalog, schema and table-header inspections
*Schema UI:* Scene-backed fixed header and reusable rows over typed column drafts
*Rows:* Loaded only for the selected table`")

ModelAssistant("`**Model Assistant**

-
*Purpose:* Preview one-way catalog-to-model bindings
*Input:* GDSQLTableDefinition and logical database role
*Output:* Generated schema base plus user-owned model source
*Inspection:* Role, table, key, property types and relationship target roles
*Safety:* Confirms generated replacement and never overwrites user behavior`")

GraphEditor("`**Graph Editor**

-
*Purpose:* Describe canonical queries through typed nodes and connections
*Document API:* GDSQLQueryGraph
*Node base:* Native titlebar close and one-shot 100% viewport-fit intents
*Predicate UI:* Reusable composed WHERE editor for select, update and delete
*Operations:* Select, insert, update and delete selected roots
*Mutation UI:* Shared source selector and typed values editor
*Result UI:* Paginated Tree, focused typed row editor and parent-owned actions
*Translation:* GDSQLGraphQueryCompiler.compile(graph)
*Produces:* GDSQLQuerySpec`")

SQLEditor("`**SQL Editor**

-
*Purpose:* Describe and inspect queries using SQL text
*Translation:* tokenize(), parse(), compile()
*Produces:* GDSQLQuerySpec
*Presentation:* Owned by editor tooling`")
end

end

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

RuntimeSession("`**GDSQLRuntimeSession**

-
*Purpose:* Expose one bootstrapped database, model and persistence context
*Database API:* database(), select_role(), get_active_save_slot(), select_save_slot()
*Model API:* register_model()
*Persistence API:* checkpoint_role(), checkpoint_save(), checkpoint_dirty()
*Created by:* GDSQLRuntimeFactory.bootstrap()`")

RuntimeNode("`**GDSQLRuntimeNode**

-
*Purpose:* Optional scene-tree/autoload adapter over RuntimeSession
*Lifecycle:* Bootstrap, periodic Timer, application-pause and tree-exit checkpoints
*API:* database(), register_model(), select_save_slot(), checkpoint_now(), stop()
*Signals:* Startup, checkpoint and shutdown results`")

DirectSetup("`**Direct Setup Diagnostics**

-
*Purpose:* Evaluate the supported content plus active-save profile
*Runtime input:* DatabaseRegistrySnapshot
*Editor input:* Inspections, model count and runtime-autoload status
*Returns:* Ordered typed checks plus structured warning diagnostics
*Boundary:* No file or Control access`")

PackageManifest("`**Content Package Manifest**

-
*Purpose:* Describe one immutable base-game, DLC or mod package
*Metadata:* Semantic version, priority, dependencies and before/after order
*Paths:* Package-relative data and asset roots
*Validation:* Manifest-local invariants with structured diagnostics`")

PackageResolution("`**Content Package Discovery and Resolution**

-
*Purpose:* Select one base plus explicitly enabled DLC/mod packages
*Compatibility:* Semantic-version constraints and required dependencies
*Ordering:* Dependency and before/after graph, then priority and package ID
*Returns:* Deterministically ordered package sources or structured diagnostics`")

ContentOverlay("`**Content Overlay Loader**

-
*Purpose:* Build one deterministic effective-content snapshot
*Input:* Resolved package order and typed package layers
*Operations:* Stable-ID upsert and explicit removal
*Returns:* Copied schemas, sorted rows, provenance, typed conflicts and diagnostics`")

ContentCache("`**Effective Content Cache**

-
*Purpose:* Reuse or rebuild disposable effective content
*Identity:* Package order, versions, content hashes and database names
*Flow:* Cache hit or overlay build followed by staged replacement
*Returns:* Typed hit/rebuilt result and diagnostics`")

ContentActivation("`**Effective Content Activation**

-
*Purpose:* Open a prepared effective database before changing runtime state
*Mutation:* Replace the effective_content registration and content role together
*Failure:* Preserve the previously active content database
*Returns:* Typed activation result, cache status and diagnostics`")

SaveCompatibility("`**Save Content Compatibility**

-
*Purpose:* Compare save-owned package expectations with active content
*Differences:* Missing, changed, reordered and additional packages
*Policy:* Report only; never rewrite save rows or choose load behavior
*Returns:* Typed status, package differences and diagnostics`")

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
*API:* create_default(), create_in_memory(), open_registration(), bootstrap()
*Creates:* GDSQLDatabaseContext and GDSQLRuntimeSession
*Injects:* Catalog, storage, validation, planning and execution services`")

Translators("`**Frontend Translators**

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

ResourceConstraint("`**GDSQLResourceTypeConstraint**

-
*Purpose:* Identify and validate the concrete Resource family of a TYPE_OBJECT column
*Identity:* Derived from a Resource prototype as native ClassDB name or project script path
*Used by:* Column defaults, query validation, storage validation and typed editor pickers`")

CatalogAdministration("`**GDSQLCatalogAdministrationService**

-
*Purpose:* Manage database and table lifecycle without exposing storage format
*Database API:* create_database(), rename_database(), drop_database()
*Table API:* create_table(), rename_table(), alter_table(), drop_table()
*Plan API:* preview_alter_table(), apply_change_plan()
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

ConfigPackageManifest("`**ConfigFile Package Manifest Store**

-
*Purpose:* Decode manifest.cfg at the external-data boundary
*Extends:* GDSQLContentPackageManifestStore
*Returns:* Typed GDSQLContentPackageManifest and diagnostics`")

ConfigPackageDiscovery("`**ConfigFile Package Discovery**

-
*Purpose:* Enumerate direct and nested content package directories
*Input:* Explicit base root and optional package-container roots
*Uses:* Injected content-package manifest store`")

ConfigPackageLayer("`**ConfigFile Package Layer Reader**

-
*Purpose:* Decode one selected package database into a typed layer
*Reads:* Catalog schemas, table rows and overlays.cfg removals
*Extends:* GDSQLContentPackageLayerReader`")

ConfigContentCache("`**ConfigFile Content Cache Store**

-
*Purpose:* Materialize snapshots and typed cache manifests
*Safety:* Bounded staging and previous-cache directories
*Fingerprint:* Sorted package paths and bytes through SHA-256`")

ConfigSaveContent("`**ConfigFile Save Content Manifest Store**

-
*Purpose:* Persist one save's expected package set
*Location:* content_manifest.cfg beside the save catalog
*Boundary:* Validated ConfigFile translation only`")
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
GraphEditor -->|"compile(graph)"| Translators
SQLEditor -->|"tokenize() · parse() · compile()"| Translators
Database -->|"query() · table()"| Translators
Translators -->|"build() / compile()"| QuerySpec
Code -->|"column() · literal() · logical and function factories"| Expr
Expr -->|"creates canonical nodes"| Expression
Expression -->|"contained by"| QuerySpec

Database -->|"execute(query) · lifecycle methods"| Context
Database -->|"transaction(callback)"| Transaction
Code -->|"register handles · select roles"| RuntimeRegistry
Code -->|"bootstrap · role databases · checkpoints"| RuntimeSession
Code -->|"optional autoload API"| RuntimeNode
RuntimeNode -->|"bootstrap, delegate and schedule checkpoints"| RuntimeSession
Factory -->|"inspect direct setup before opening"| DirectSetup
Workbench -->|"augment setup with editor-known status"| DirectSetup
Code -->|"declare managed content packages"| PackageManifest
PackageManifest -->|"validated package sources"| PackageResolution
PackageResolution -->|"ordered immutable packages"| ContentOverlay
ContentOverlay -->|"rebuild snapshot"| ContentCache
ContentCache -->|"compatible cache database"| ContentActivation
ContentActivation -->|"atomic runtime-local replacement"| RuntimeRegistry
ContentCache -->|"active manifest"| SaveCompatibility
RuntimeSession -->|"resolve roles"| RuntimeRegistry
RuntimeSession -->|"default model context"| Models
RuntimeSession -->|"checkpoint operations"| Persistence
RuntimeRegistry -->|"resolve() · resolve_role()"| Database
Models -->|"resolve_role(model)"| RuntimeRegistry
Models -->|"to_query_spec()"| QuerySpec
Models -->|"ModelResultMaterializer"| Materialization
Code -->|"checkpoint() · checkpoint_dirty()"| Persistence
Workbench -->|"open_registration()"| Factory
Workbench -->|"load and save registration snapshot"| RuntimeRegistry
Workbench -->|"select · load rows"| Database
Workbench -->|"preview · apply change plan"| CatalogAdministration
Workbench -->|"selected table definition"| ModelAssistant
ModelAssistant -.->|"generates project model scripts"| Models
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
CatalogService -->|"object-column metadata"| ResourceConstraint
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
ConfigPackageManifest -->|"decodes typed metadata"| PackageManifest
ConfigPackageDiscovery -->|"discover package sources"| PackageResolution
ConfigPackageDiscovery -->|"load manifest"| ConfigPackageManifest
ConfigPackageLayer -->|"typed schemas and row operations"| ContentOverlay
ConfigContentCache -->|"manifest and cached database"| ContentCache
ConfigSaveContent -->|"saved package expectations"| SaveCompatibility

Factory -.->|"create_default(data_root)"| Context
Factory -.->|"constructs and injects"| ConfigInfrastructure
Factory -.->|"bootstrap()"| RuntimeSession
Factory -.->|"activate_effective_content()"| ContentActivation
Factory -.->|"create_in_memory(data_root)"| MemoryStorage

class Code,Models,Workbench,ModelAssistant,GraphEditor,SQLEditor,Expr frontend;
class Database,Context,Factory,Transaction,RuntimeRegistry,RuntimeSession,RuntimeNode,DirectSetup,PackageManifest,PackageResolution,ContentOverlay,ContentCache,ContentActivation,SaveCompatibility,Persistence runtime;
class Translators translation;
class QuerySpec,Expression canonical;
class Validator,BoundQuery validation;
class Planner,PlanNode planning;
class Executor execution;
class CatalogService,CatalogAdministration,ResourceConstraint catalog;
class TableStorage storage;
class ConfigCatalog,ConfigAdministration,ConfigStorage,ConfigInfrastructure,ConfigPackageManifest,ConfigPackageDiscovery,ConfigPackageLayer,ConfigContentCache,ConfigSaveContent,MemoryStorage,MemoryCheckpoint implementation;
class Results,Materialization result;

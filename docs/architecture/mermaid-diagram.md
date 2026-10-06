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
*Resolution:* ModelRegistry to DatabaseRegistry roles
*Relationships:* Same-database foreign keys infer default navigation`")

subgraph EditorFrontends["Editor workbench"]
direction TB

Workbench("`**GDSQLWorkbench**

-
*Purpose:* Explore and manipulate registered databases, tables and rows
*Collection API:* load(), discover_root(), discover_children(), select_registration()
*Session API:* select_table(), load_rows(), preview_table_change(), apply_pending_change()
*Metadata:* Lightweight catalog, schema and table-header inspections
*Schema UI:* Scene-backed fixed header and reusable rows over typed column drafts; row context actions preview removal dependencies; compact table actions stage rename/drop
*Reference UI:* Bounded canonical target-row lookup and searchable key picker
*Rows:* Loaded only for the selected table`")

MigrationAuthoring("`**Editor Migration Authoring**

-
*Purpose:* Turn one table alteration, lifecycle change, or typed row update into immutable project history
*Data UI:* Typed literal assignments plus nested WHERE; explicit all-row confirmation
*Preview:* Affected rows, step summaries and destructive classification
*Safety:* Explicit confirmation, stale-count append and stale-safe application
*Recovery:* A persisted failure remains pending and retryable`")

ForeignKeyAuthoring("`**Foreign Key Authoring**

-
*Purpose:* Draft same-database references in the table designer
*Input:* Local table plus database catalog definitions
*Filtering:* Supported local types and exact-type unique targets in other tables
*Output:* ForeignKeyDefinition and typed table alterations`")

RowBatch("`**GDSQLEditorRowBatch**

-
*Purpose:* Validate and execute table-scoped row batches
*Input:* Edited values or selected primary keys
*Output:* Canonical update or delete queries
*Safety:* One public database transaction; reject empty, duplicate or read-only mutations`")

MutationHistory("`**Editor Mutation History**

-
*Purpose:* Keep bounded session-only row Undo/Redo state
*Entry:* One committed batch with target and before/after snapshots
*Safety:* Move stacks only after successful inverse execution
*Scope:* Scalar updates first; controller owns execution`")

ModelAssistant("`**Model Assistant**

-
*Purpose:* Preview one-way catalog-to-model bindings
*Input:* GDSQLTableDefinition and logical database role
*Output:* Generated schema base plus user-owned model source
*Inspection:* Role, table, key, property types and relationship target roles
*Safety:* Confirms generated replacement and never overwrites user behavior`")

ContentReference("`**Editor Content Reference**

-
*Purpose:* Bind one save identifier cell to a content-role row picker
*Storage:* Project tool settings
*Safety:* Editor lookup metadata only; never a catalog foreign key`")

McpAdapter("`**Optional Godot-AI MCP Adapter**

-
*Purpose:* Register project-scoped GDSQL inspection tools
*Transport:* Owned by Godot-AI; optional to GDSQL
*Tools:* Promoted capabilities, setup, schema and model-binding inspection
*Discovery:* Godot-AI custom tools resource and `custom_manage`
*Safety:* No rows, Controls, arbitrary paths or ConfigFile access
*Future writes:* Separate preview and confirmation calls`")

GraphEditor("`**Graph Editor**

-
*Purpose:* Describe canonical queries through typed nodes and connections
*Document API:* GDSQLQueryGraph
*Node base:* Native titlebar close and one-shot 100% viewport-fit intents
*Predicate UI:* Reusable WHERE editor with recursive typed groups, explicit precedence, group-level NOT and compact summaries for table filters, select, update and delete
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
*Lifecycle:* Bootstrap selected profile, activate managed content, periodic Timer, pause and exit checkpoints
*API:* get_content_activation_result(), get_save_content_compatibility_report(), database(), register_model(), select_save_slot(), checkpoint_now(), stop()
*Signals:* Startup, content activation, save compatibility, checkpoint and shutdown results`")

DirectSetup("`**Direct Setup Diagnostics**

-
*Purpose:* Evaluate the supported content plus active-save profile
*Runtime input:* DatabaseRegistrySnapshot
*Editor input:* Inspections, model count and runtime-autoload status
*Returns:* Ordered typed checks plus structured warning diagnostics
*Boundary:* No file or Control access`")

SetupProfile("`**Setup Profile and Checks**

-
*Selection:* Unselected, direct content or managed content
*Reports:* Shared typed ordered checks and next actions
*Safety:* Selection never migrates project data`")

ManagedConfiguration("`**Managed Content Configuration**

-
*Purpose:* Share package roots and enabled IDs between editor and runtime
*Boundary:* Typed data plus storage-independent load/save contract
*Default:* res://content/base with project and user package containers`")

ManagedSetup("`**Managed Setup Diagnostics**

-
*Purpose:* Evaluate the independent managed-content workflow
*Checks:* Base package, source data, cache, save, model and runtime
*Boundary:* Consumes supplied typed state without Controls`")

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
*API:* create_default(), create_in_memory(), open_registration(), open_authoring_registration(), bootstrap(), activate_managed_content()
*Creates:* GDSQLDatabaseContext and GDSQLRuntimeSession
*Injects:* Catalog, storage, validation, planning and execution services`")

MigrationStartup("`**GDSQLMigrationStartupCoordinator**

-
*Purpose:* Reach a trusted durable schema before hydration and models
*Project flow:* Verify trusted head without ledger or mutation; fail when outdated
*Writable flow:* Recover, conditionally baseline, apply sequentially, verify
*Policy:* No history and state is unconfigured; history without state fails closed
*Returns:* GDSQLMigrationStartupResult with baseline, recovered and applied IDs`")

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
*Derives:* Required columns and concrete Resource evaluation requirements
*Optimizes:* Safe single-table OFFSET/LIMIT table or ordered-index windows
*Extended by:* GDSQLDefaultQueryPlanner`")

PlanNode("`**GDSQLPlanNode**

-
*Purpose:* Represent one executable operation in a query plan
*API:* accept(visitor)
*Read nodes:* Scan, ordered-index scan, primary-key, exact-index, range-index, join, filter, aggregate, sort, projection, distinct and limit
*Mutation nodes:* Insert, update and delete`")

Executor("`**GDSQLQueryExecutor**

-
*Purpose:* Execute a query plan using runtime service contracts
*API:* execute(plan, execution_context)
*Returns:* GDSQLQueryExecutionResult
*Resources:* Materializes only required references through an injected resolver
*Extended by:* GDSQLDefaultQueryExecutor`")

ForeignKeyValidation("`**GDSQLForeignKeyConstraintValidator**

-
*Purpose:* Validate same-database references against final transactional rows
*Timing:* Before storage commit
*Policy:* Atomic insert/update enforcement and RESTRICT target changes
*Depends on:* CatalogService and TableStorage contracts`")

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

ResourceProperties("`**GDSQLResourcePropertyCatalog**

-
*Purpose:* Resolve Inspector-visible scalar leaves for constrained Resource columns
*Compound values:* Expose supported scalar components, never the container
*Used by:* WHERE authoring and semantic validation`")

ForeignKeys("`**GDSQLForeignKeyDefinition**

-
*Purpose:* Describe one same-database, single-column integrity reference
*Identity:* Name, local column, referenced table and referenced unique column
*Boundary:* Separate from model navigation and cross-role references
*Initial policy:* int/String/StringName, unique resolved targets, existing-row validation, transactional RESTRICT enforcement`")

CatalogAdministration("`**GDSQLCatalogAdministrationService**

-
*Purpose:* Manage database and table lifecycle without exposing storage format
*Database API:* create_database(), rename_database(), drop_database()
*Table API:* create_table(), rename_table(), alter_table(), drop_table()
*Plan API:* create/alter/rename/drop previews and apply_change_plan()
*Integrity:* Reject incoming-reference-breaking schema changes
*Extension point:* Catalog administration backend implementations`")

MigrationHistory("`**Schema Migration History**

-
*Input:* Ordered GDSQLMigrationDefinition values with typed schema or data steps
*Integrity:* Deterministic checksums; applied history must be an exact prefix
*Plan:* GDSQLMigrationPlanner returns pending definitions and destructive status
*Boundary:* Models never create or infer migrations`")

MigrationHistoryStore("`**GDSQLMigrationHistoryStore**

-
*Purpose:* Persist project-owned authored history by stable stream
*API:* load(), append() with expected definition count
*Boundary:* Shared source definitions, never per-database applied state`")

MigrationSchemaState("`**GDSQLMigrationSchemaState**

-
*Purpose:* Bind one stable stream and logical database to a verified history prefix
*Evidence:* History count/head, prefix checksum and whole-schema fingerprint
*Boundary:* Project-owned trust input for baseline adoption`")

MigrationSchemaStateStore("`**GDSQLMigrationSchemaStateStore**

-
*Purpose:* Load and advance project-owned schema evidence
*API:* load(), save() with expected previous history checksum
*Safety:* Stale protection and monotonic established history positions`")

MigrationStepPlanning("`**Migration Step Planning**

-
*Input:* Target database and next pending migration
*API:* GDSQLMigrationStepPlanner.preview_next()
*Output:* GDSQLMigrationStepPlan wrapping one schema preview or a distinct-table data batch
*Scope:* Per-table counts without mutation; dependent schema/mixed batches are rejected`")

MigrationLedger("`**GDSQLMigrationLedger**

-
*Purpose:* Persist append-only applied migration evidence
*Baseline:* One verified adopted history prefix for a pre-existing schema
*Records:* ID, checksum, application time and resulting schema fingerprint
*Concurrency:* Adoption and append require the expected ledger revision
*Extension point:* Migration ledger backend implementations`")

MigrationRecovery("`**GDSQLMigrationRecoveryStore**

-
*Purpose:* Preserve and restore complete pre-migration database state
*Evidence:* GDSQLMigrationBackup identity, creation time and SHA-256 fingerprint
*API:* list_backups(), create_backup(), load_backup(), restore(), discard()
*Boundary:* Durable recovery, not query transactions or long-term archives`")

MigrationRunner("`**GDSQLMigrationRunner**

-
*Input:* One validated GDSQLMigrationStepPlan
*Preconditions:* Current ledger revision and whole-schema fingerprint
*Success:* Apply one schema step or ordered data batch, then append one ledger record
*Failure:* Restore complete backup and retain structured diagnostics`")

MigrationService("`**GDSQLMigrationService**

-
*Purpose:* Supported baseline, preview, apply and interruption-recovery orchestration
*API:* adopt_baseline(), adopt_baseline_if_current(), preview(), apply(), recover_interrupted(), recover_pending()
*Results:* Up-to-date or next plan; applied record; restored or cleanup-only recovery
*Composition:* Durable ConfigFile authoring contexts only`")

FreshProvisioning("`**GDSQLEditorFreshSaveProvisioner**

-
*Purpose:* Create a new writable database at a trusted current schema head
*Input:* Verified template catalog, authored history, schema state and empty target
*Mutation:* Copy schema without rows, add foreign keys after tables, adopt baseline
*Safety:* Verify source and target fingerprints; roll back created catalog on failure`")

TableStorage("`**GDSQLTableStorage**

-
*Purpose:* Isolate row persistence from query execution
*Read API:* read_table(), read_batch(), read_index_batch(), primary-key/index/range lookup, get_capabilities()
*Read input:* GDSQLStorageReadRequest with required columns, reference policy and optional batch continuation
*Mutation API:* stage_insert(), stage_update(), stage_delete()
*Transaction API:* commit(), rollback()
*Extension point:* Table storage backend implementations`")

StorageBatches("`**Bounded Storage Reads**

-
*Request:* Positive batch size plus backend/source-bound opaque GDSQLStorageReadCursor
*Result:* GDSQLStorageReadBatch with rows, continuation, diagnostics and statistics
*Ordered index:* Cursor also binds the catalog index and traversal direction
*Metrics:* Rows scanned/returned, optional bytes/pages and physical-bound flag
*Window:* Safe scan offsets/limits are applied before Resource materialization
*Boundary:* Execution passes cursors back without inspecting backend tokens`")

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

ConfigMigrationLedger("`**GDSQLConfigFileMigrationLedger**

-
*Purpose:* Validate and persist one database's baseline and ordered applied history
*Location:* &lt;data_root&gt;/&lt;database&gt;/migrations.cfg
*Extends:* GDSQLMigrationLedger
*Uses:* GDSQLDatabasePathResolver`")

ConfigMigrationHistory("`**GDSQLConfigFileMigrationHistoryStore**

-
*Purpose:* Persist one immutable authored definition per ConfigFile
*Location:* res://.gdsql/migrations/&lt;stream&gt;/&lt;migration_id&gt;.cfg
*Integrity:* Filename identity, strict order and recorded checksum
*Extends:* GDSQLMigrationHistoryStore`")

ConfigMigrationSchemaState("`**GDSQLConfigFileMigrationSchemaStateStore**

-
*Purpose:* Persist trusted stream/head schema evidence
*Location:* res://.gdsql/migration_states/&lt;stream&gt;.cfg
*Safety:* Staged activation, previous-file recovery and stale checks
*Extends:* GDSQLMigrationSchemaStateStore`")

ConfigMigrationRecovery("`**GDSQLConfigFileMigrationRecoveryStore**

-
*Purpose:* Fingerprint and restore whole ConfigFile database directories
*Location:* &lt;data_root&gt;/.gdsql_migration_recovery/&lt;database&gt;/&lt;migration&gt;
*Safety:* Verified staging copy, directory swap, rollback and cache invalidation
*Extends:* GDSQLMigrationRecoveryStore`")

ConfigStorage("`**GDSQLConfigFileTableStorage**

-
*Purpose:* Persist table rows as ConfigFile sections and values
*API:* Snapshot/scan/ordered-index batches, lookup, staged mutations, commit and rollback
*Batch behavior:* Bounds decoded rows after ConfigFile has parsed table and index metadata
*Maintains:* Reserved index entries during committed mutations
*Extends:* GDSQLTableStorage
*Uses:* Path resolver, ConfigFile cache and Variant codec`")

ConfigInfrastructure("`**ConfigFile Infrastructure**

-
*Purpose:* Contain ConfigFile-specific paths, caching and serialization
*Path API:* resolve_catalog_path(), resolve_schema_path(), resolve_table_path()
*Cache API:* get_or_load(), invalidate(), flush()
*Types:* GDSQLDatabasePathResolver, GDSQLConfigFileCache, GDSQLGodotVariantCodec`")

ResourceMaterialization("`**Resource Materialization**

-
*Purpose:* Preserve inert referenced-asset identity and materialize it only through explicit policy
*Identity:* GDSQLResourceReference
*Deferred state:* GDSQLResourceHandle with sync/threaded load, progress, signals and release
*Bounded lifetime:* GDSQLResourcePrefetchScope with aggregate progress and release
*Opt-in:* GDSQLQueryExecutionOptions and ModelQuery.defer_resources()
*Contract:* GDSQLResourceResolver sync plus optional request/poll
*Default:* GDSQLGodotResourceResolver`")

ConfigPackageManifest("`**ConfigFile Package Manifest Store**

-
*Purpose:* Decode manifest.cfg at the external-data boundary
*Extends:* GDSQLContentPackageManifestStore
*Returns:* Typed GDSQLContentPackageManifest and diagnostics`")

ConfigPackageScaffolder("`**ConfigFile Package Scaffolder**

-
*Purpose:* Create editable base-package data and asset roots
*Safety:* Fill absent manifest fields without replacing authored values
*Returns:* Validated typed package source and diagnostics`")

ConfigPackageDiscovery("`**ConfigFile Package Discovery**

-
*Purpose:* Enumerate direct and nested content package directories
*Input:* Explicit base root and optional package-container roots
*Uses:* Injected content-package manifest store`")

ConfigManagedConfiguration("`**ConfigFile Managed Configuration Store**

-
*Purpose:* Persist typed managed package roots and enabled IDs
*Location:* res://.gdsql/settings.cfg
*Safety:* Preserve setup profile and unrelated settings`")

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
*API:* Snapshot/scan/ordered-index batches, lookup, staged mutations, commit and rollback
*Batch behavior:* Bounds returned rows after assembling and ordering the effective in-memory set
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
Code -->|"author ordered forward schema history"| MigrationHistory
Expr -->|"creates canonical nodes"| Expression
Expression -->|"contained by"| QuerySpec

Database -->|"execute(query) · lifecycle methods"| Context
Context -->|"baseline · preview · apply · recover migration"| MigrationService
Database -->|"transaction(callback)"| Transaction
Code -->|"register handles · select roles"| RuntimeRegistry
Code -->|"bootstrap · role databases · checkpoints"| RuntimeSession
Code -->|"optional autoload API"| RuntimeNode
RuntimeNode -->|"bootstrap, delegate and schedule checkpoints"| RuntimeSession
RuntimeNode -->|"load selected package inputs"| ManagedConfiguration
RuntimeNode -->|"automatic managed activation"| ContentActivation
RuntimeNode -->|"active-save policy handoff"| SaveCompatibility
Factory -->|"inspect direct or unselected setup before opening"| DirectSetup
Workbench -->|"augment setup with editor-known status"| DirectSetup
Workbench -->|"persist profile selection"| SetupProfile
Workbench -->|"edit package inputs"| ManagedConfiguration
Workbench -->|"supply managed setup state"| ManagedSetup
ManagedSetup -->|"ordered profile checks"| SetupProfile
DirectSetup -->|"ordered profile checks"| SetupProfile
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
Workbench -->|"open_authoring_registration()"| Factory
Workbench -->|"load and save registration snapshot"| RuntimeRegistry
Workbench -->|"select · load rows"| Database
McpAdapter -.->|"read-only inspection state"| Workbench
McpAdapter -.->|"profile readiness"| DirectSetup
McpAdapter -.->|"managed readiness"| ManagedSetup
Workbench -->|"preview · apply change plan"| CatalogAdministration
MigrationAuthoring -->|"append immutable definition"| MigrationHistoryStore
MigrationAuthoring -->|"preview_migrations() · apply_migration()"| Database
MigrationAuthoring -->|"record verified authored head"| MigrationSchemaStateStore
MigrationHistory -->|"compare authored and applied prefix"| MigrationLedger
MigrationHistory -->|"loaded from project stream"| MigrationHistoryStore
MigrationSchemaState -->|"verify exact authored prefix"| MigrationHistory
MigrationService -->|"validate complete authored history"| MigrationHistory
MigrationService -->|"adopt trusted baseline"| MigrationSchemaState
MigrationService -->|"preview next pending entry"| MigrationStepPlanning
MigrationService -->|"apply one validated plan"| MigrationRunner
MigrationService -->|"resolve leftover backup against ledger"| MigrationRecovery
MigrationService -->|"detect committed migration"| MigrationLedger
MigrationService -->|"verify baseline and drift fingerprints"| CatalogService
FreshProvisioning -->|"create schema without rows"| CatalogAdministration
FreshProvisioning -->|"verify source and target"| MigrationSchemaState
FreshProvisioning -->|"adopt trusted prefix"| MigrationService
Workbench -->|"provision new save slot"| FreshProvisioning
MigrationHistory -->|"preview next pending entry"| MigrationStepPlanning
MigrationStepPlanning -->|"preview typed table lifecycle"| CatalogAdministration
MigrationStepPlanning -->|"validate and count canonical update"| Validator
MigrationStepPlanning -->|"validated next plan"| MigrationRunner
MigrationRunner -->|"create · restore · discard"| MigrationRecovery
MigrationRunner -->|"apply_change_plan()"| CatalogAdministration
MigrationRunner -->|"execute canonical row update"| Executor
MigrationRunner -->|"load · append applied record"| MigrationLedger
MigrationRunner -->|"read schema for drift and result fingerprints"| CatalogService
Workbench -->|"table designer context"| ForeignKeyAuthoring
ForeignKeyAuthoring -->|"typed add/drop intent"| CatalogAdministration
ForeignKeyAuthoring -.->|"candidate metadata"| ForeignKeys
Workbench -->|"selected table definition"| ModelAssistant
Workbench -->|"build row mutations"| RowBatch
RowBatch -->|"canonical queries in one transaction"| Database
Workbench -->|"record successful batches"| MutationHistory
MutationHistory -->|"next inverse mutation"| RowBatch
ModelAssistant -.->|"generates scripts · previews inferred relationships"| Models
ModelAssistant -->|"register picker metadata"| ContentReference
ContentReference -.->|"bounded target-role row lookup"| Workbench
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
ResourceConstraint -->|"static property metadata"| ResourceProperties
Validator -->|"validate scalar leaf path"| ResourceProperties
Workbench -.->|"Resource WHERE field choices"| ResourceProperties
CatalogService -->|"table integrity metadata"| ForeignKeys
Executor -->|"read_batch() · read_index_batch() · lookup reads"| TableStorage
Executor -->|"consume bounded scan/index continuations"| StorageBatches
TableStorage -->|"read_batch(request) · read_index_batch(request)"| StorageBatches
Executor -->|"materialize required references"| ResourceMaterialization
Executor -->|"stage_*() · commit() · rollback()"| TableStorage
Context -->|"validate final transaction state"| ForeignKeyValidation
ForeignKeyValidation -->|"discover same-database constraints"| CatalogService
ForeignKeyValidation -->|"read effective session rows"| TableStorage

CatalogService -->|"extended by"| ConfigCatalog
CatalogAdministration -->|"extended by"| ConfigAdministration
MigrationLedger -->|"extended by"| ConfigMigrationLedger
MigrationHistoryStore -->|"extended by"| ConfigMigrationHistory
MigrationSchemaStateStore -->|"extended by"| ConfigMigrationSchemaState
MigrationRecovery -->|"extended by"| ConfigMigrationRecovery
TableStorage -->|"extended by"| ConfigStorage
TableStorage -->|"extended by"| MemoryStorage

MemoryCheckpoint -->|"reads dirty table versions"| MemoryStorage
MemoryCheckpoint -->|"stages and commits durable changes"| TableStorage

ConfigCatalog -->|"path resolution"| ConfigInfrastructure
ConfigAdministration -->|"paths · cache"| ConfigInfrastructure
ConfigMigrationLedger -->|"ledger path"| ConfigInfrastructure
ConfigMigrationRecovery -->|"recovery paths · cache invalidation"| ConfigInfrastructure
ConfigStorage -->|"paths · cache · codec"| ConfigInfrastructure
ConfigInfrastructure -->|"reference identity · resolver"| ResourceMaterialization
ConfigPackageManifest -->|"decodes typed metadata"| PackageManifest
ConfigPackageScaffolder -->|"validates typed metadata"| PackageManifest
ConfigPackageDiscovery -->|"discover package sources"| PackageResolution
ConfigPackageDiscovery -->|"load manifest"| ConfigPackageManifest
ConfigManagedConfiguration -->|"implements store"| ManagedConfiguration
ConfigPackageLayer -->|"typed schemas and row operations"| ContentOverlay
ConfigContentCache -->|"manifest and cached database"| ContentCache
ConfigSaveContent -->|"saved package expectations"| SaveCompatibility

Factory -.->|"create_default(data_root)"| Context
Factory -.->|"constructs and injects"| ConfigInfrastructure
Factory -.->|"bootstrap()"| RuntimeSession
Factory -->|"prepare durable registrations before hydration"| MigrationStartup
MigrationStartup -->|"load trusted prefix"| MigrationHistoryStore
MigrationStartup -->|"load trusted target schema"| MigrationSchemaStateStore
MigrationStartup -->|"baseline · recover · preview · apply"| MigrationService
Factory -.->|"activate_effective_content()"| ContentActivation
Factory -.->|"create_in_memory(data_root)"| MemoryStorage

class Code,Models,Workbench,MigrationAuthoring,ForeignKeyAuthoring,RowBatch,MutationHistory,ModelAssistant,ContentReference,McpAdapter,GraphEditor,SQLEditor,Expr frontend;
class Database,Context,Factory,MigrationStartup,Transaction,RuntimeRegistry,RuntimeSession,RuntimeNode,SetupProfile,ManagedConfiguration,DirectSetup,ManagedSetup,PackageManifest,PackageResolution,ContentOverlay,ContentCache,ContentActivation,SaveCompatibility,Persistence runtime;
class Translators translation;
class QuerySpec,Expression canonical;
class Validator,BoundQuery validation;
class Planner,PlanNode planning;
class Executor,ForeignKeyValidation,MigrationRunner,MigrationService,FreshProvisioning execution;
class CatalogService,CatalogAdministration,ResourceConstraint,ResourceProperties,ForeignKeys,MigrationHistory,MigrationHistoryStore,MigrationSchemaState,MigrationSchemaStateStore,MigrationStepPlanning,MigrationLedger,MigrationRecovery catalog;
class TableStorage storage;
class ConfigCatalog,ConfigAdministration,ConfigMigrationHistory,ConfigMigrationSchemaState,ConfigMigrationLedger,ConfigMigrationRecovery,ConfigStorage,ConfigInfrastructure,ConfigPackageManifest,ConfigPackageScaffolder,ConfigPackageDiscovery,ConfigManagedConfiguration,ConfigPackageLayer,ConfigContentCache,ConfigSaveContent,MemoryStorage,MemoryCheckpoint implementation;
class ResourceMaterialization storage;
class Results,Materialization result;

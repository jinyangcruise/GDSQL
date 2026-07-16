flowchart TB

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

Callers["<b>Callers</b><br/>Game code · Editor tools · Future integrations"]

Runtime["<b>Public Runtime</b><br/>GDSQLDatabase · GDSQLDatabaseContext<br/>GDSQLRuntimeFactory<br/><i>Public access and pipeline orchestration</i>"]

Frontends["<b>Query Frontends</b><br/>Fluent builders · SQL translation · Query graph<br/><i>Frontend concerns end after translation</i>"]

Canonical["<b>Canonical Query Model</b><br/>Select · Insert · Update · Delete QuerySpec<br/>Expressions · Sources · Clauses<br/><i>Descriptive data only</i>"]

Validation["<b>Validation and Binding</b><br/>QueryValidator · BoundQuery<br/>Resolved tables, columns, types and diagnostics"]

Planning["<b>Query Planning</b><br/>QueryPlanner · QueryPlan<br/>Scan · Primary-key lookup · Filter · Projection<br/>Insert · Update · Delete plan nodes"]

Execution["<b>Query Execution</b><br/>QueryExecutor · ExecutionContext<br/>ExpressionEvaluator · TransactionManager<br/><i>Executes plans through runtime contracts</i>"]

Results["<b>Structured Results</b><br/>QueryResult · DatabaseResult · RowSet<br/>Affected rows · Returned rows · Diagnostics"]

Catalog["<b>Catalog Contracts</b><br/>CatalogService<br/>get_database() · get_table() · has_table() · create_snapshot()<br/>CatalogAdministrationService<br/>create_database() · create_table() · rename_*() · alter_table() · drop_*()"]

Storage["<b>Storage Contract</b><br/>TableStorage · StorageSession · RowRecord<br/>read_table() · find_by_primary_key()<br/>stage_insert/update/delete() · commit() · rollback()"]

Backends["<b>Backend Implementations</b><br/>Current: ConfigFile catalog, administration and table storage<br/>Future: binary catalog, administration and table storage<br/><i>Paths, serialization and physical formats stay here</i>"]

Callers -->|"create() · open() · query() · execute()"| Runtime
Runtime -->|"query() · table() · select/insert/update/delete()"| Frontends
Frontends -->|"build() / compile()"| Canonical
Canonical -->|"validate(query)"| Validation
Validation -->|"create_plan(bound_query)"| Planning
Planning -->|"execute(plan, context)"| Execution
Execution -->|"rows · statistics · diagnostics"| Results

Runtime -->|"create_database() · create_table() · rename_*() · alter_table() · drop_*()"| Catalog
Validation -->|"get_table() · create_snapshot()"| Catalog
Execution -->|"read_table() · stage_*() · commit() · rollback()"| Storage
Catalog -->|"implemented by"| Backends
Storage -->|"implemented by"| Backends

class Callers frontend;
class Frontends translation;
class Canonical canonical;
class Validation validation;
class Planning planning;
class Execution execution;
class Catalog catalog;
class Storage storage;
class Results result;
class Runtime runtime;
class Backends storage;

# THIS IS A FUTURE IMPLEMENTATION

Everything provided bellow is a "vision" of the future after the architectural implementation is achieved   

---

# Extending GDSQL Beyond Local Storage

## 1. Vision for networked and remote data management

The canonical query architecture should allow GDSQL to support more than local `.cfg` files.

The query runtime should depend on abstract contracts rather than assuming that all data exists in a local `ConfigFile`. This permits additional data-management strategies to be implemented without changing the SQL parser, fluent API, query model, or editor.

Possible environments include:

- Local single-player games.
- Host-authoritative cooperative games.
- Dedicated multiplayer servers.
- Client-server applications.
- Offline-first games.
- Cloud-backed persistent worlds.
- Peer-hosted sessions.
- Hybrid local and remote data systems.

The architectural extension is:

```text
Frontend
    ↓
QuerySpec
    ↓
Validation and planning
    ↓
Application/runtime services
    ↓
Data access boundary
    ├── Local TableStorage
    ├── Remote Database Gateway
    ├── Replicated Data Store
    └── Hybrid Data Store
```

The canonical query model remains useful, but networked applications require an additional distinction:

> A database query is not always an appropriate network message.

In an authoritative multiplayer system, clients should generally submit **intent**, not arbitrary database instructions.

For example, a client may request:

```text
PurchaseItemCommand
MoveItemCommand
CreateLobbyCommand
UpdateCharacterLoadoutCommand
```

The server validates the command and creates the required `QuerySpec` internally.

The client should not normally send:

```sql
UPDATE players
SET currency = 999999;
```

or a serialized equivalent:

```text
UpdateQuerySpec
    target: players
    assignments:
        currency = 999999
```

This distinction preserves server authority and prevents database internals from becoming the public multiplayer protocol.

---

## 2. Local data access

The default GDSQL implementation remains a local storage runtime.

```text
QuerySpec
    ↓
QueryPlan
    ↓
QueryExecutor
    ↓
TableStorage
    ↓
ConfigFileTableStorage
    ↓
.cfg
```

This model is appropriate for:

- Game configuration.
- Save games.
- Local inventory.
- Static item definitions.
- Dialogue data.
- Quest definitions.
- Editor-managed resources.
- Single-player runtime state.

The storage implementation may use:

```gdscript
class_name ConfigFileTableStorage
extends TableStorage
```

The upper layers depend only on `TableStorage`.

---

## 3. Remote database gateway

A remote system may expose database-like operations through a network service.

```gdscript
@abstract
class_name RemoteDatabaseGateway
extends RefCounted

@abstract
func execute(
    request: RemoteQueryRequest
) -> RemoteQueryResult

@abstract
func begin_transaction() -> RemoteTransactionId

@abstract
func commit(
    transaction_id: RemoteTransactionId
) -> RemoteOperationResult

@abstract
func rollback(
    transaction_id: RemoteTransactionId
) -> RemoteOperationResult
```

A remote request may contain a restricted serialized query:

```gdscript
class_name RemoteQueryRequest
extends RefCounted

var request_id: StringName
var operation: RemoteQueryOperation
var payload: Dictionary
var transaction_id: RemoteTransactionId
var authentication: AuthenticationContext
```

This approach may be appropriate for:

- Trusted editor-to-server tools.
- Administrative interfaces.
- Internal backend communication.
- Dedicated-server persistence.
- Controlled service-to-service communication.

It is less appropriate as a public protocol for untrusted game clients.

The remote gateway hides:

- HTTP.
- WebSocket.
- ENet.
- RPC.
- Serialization formats.
- Authentication headers.
- Retry behavior.
- Connection pooling.
- Server endpoints.

The caller depends on the gateway contract rather than a specific transport.

---

## 4. Application command boundary

For multiplayer gameplay, application commands should normally sit above the query system.

```gdscript
@abstract
class_name GameCommand
extends RefCounted

var command_id: StringName
var player_id: PlayerId
var expected_version: int
```

```gdscript
class_name PurchaseItemCommand
extends GameCommand

var item_id: ItemId
var quantity: int
```

A command handler owns the use case:

```gdscript
@abstract
class_name CommandHandler
extends RefCounted

@abstract
func handle(
    command: GameCommand,
    context: CommandContext
) -> CommandResult
```

```gdscript
class_name PurchaseItemHandler
extends CommandHandler

var _database: DatabaseContext
var _catalog: ItemCatalog
var _permissions: PermissionService

func _init(
    database: DatabaseContext,
    catalog: ItemCatalog,
    permissions: PermissionService
) -> void:
    _database = database
    _catalog = catalog
    _permissions = permissions

func handle(
    command: GameCommand,
    context: CommandContext
) -> CommandResult:
    var purchase := command as PurchaseItemCommand

    var validation := _validate_purchase(
        purchase,
        context
    )

    if not validation.is_successful():
        return validation

    var transaction := _database.begin_transaction()

    var debit_query := _build_currency_update(purchase)
    var inventory_query := _build_inventory_insert(purchase)

    var debit_result := transaction.execute(debit_query)
    var inventory_result := transaction.execute(
        inventory_query
    )

    if not debit_result.is_successful() \
            or not inventory_result.is_successful():
        transaction.rollback()
        return CommandResult.failure(
            &"PURCHASE_FAILED"
        )

    transaction.commit()

    return CommandResult.success()
```

The command handler translates trusted application intent into one or more canonical queries.

```text
Client input
    ↓
Network message
    ↓
GameCommand
    ↓
Authentication and authorization
    ↓
CommandHandler
    ↓
QuerySpec
    ↓
Server-side database runtime
```

This provides a stronger boundary than exposing `QuerySpec` directly over the network.

---

## 5. Authoritative host architecture

A cooperative game may use one player as the authoritative host.

```text
Client
    ↓ command
Host application layer
    ↓
Host GDSQL runtime
    ↓
Authoritative storage
    ↓
State change event
    ↓
Connected clients
```

The host owns:

- Validation.
- Query execution.
- Persistent state.
- Conflict resolution.
- Transaction order.
- Replication order.
- Version assignment.

Clients own:

- Input collection.
- Local prediction where applicable.
- Presentation.
- Cached replicated state.
- Reconciliation.

A host implementation may contain:

```gdscript
class_name HostDataService
extends RefCounted

var _command_bus: CommandBus
var _event_publisher: ReplicationPublisher

func handle_client_command(
    peer: PeerIdentity,
    command: GameCommand
) -> CommandResult:
    var result := _command_bus.dispatch(
        command,
        peer
    )

    if result.is_successful():
        _event_publisher.publish(
            result.domain_events
        )

    return result
```

The host should not trust client-supplied ownership fields, prices, calculated rewards, or version numbers without validation.

---

## 6. Dedicated server architecture

A dedicated server can use the same application and query layers while replacing the transport and storage implementations.

```text
Game client
    ↓
Network transport
    ↓
Server endpoint
    ↓
Command deserializer
    ↓
Command handler
    ↓
QuerySpec
    ↓
DatabaseContext
    ↓
Server storage
```

Possible server storage implementations include:

```text
ConfigFileTableStorage
SQLiteTableStorage
PostgresTableStorage
RemoteServiceTableStorage
InMemoryTableStorage
```

The server can use GDSQL’s canonical query model even when `.cfg` is no longer the physical persistence format.

That possibility depends on preserving the storage abstraction:

```gdscript
var storage: TableStorage
```

rather than requiring:

```gdscript
var storage: ConfigFileTableStorage
```

---

## 7. Query transport

A serialized `QuerySpec` may be useful between trusted systems.

```gdscript
@abstract
class_name QuerySpecCodec
extends RefCounted

@abstract
func encode(query: QuerySpec) -> Dictionary

@abstract
func decode(data: Dictionary) -> QueryDecodingResult
```

Example representation:

```gdscript
{
    "operation": "select",
    "source": {
        "type": "table",
        "name": "heroes"
    },
    "projections": [
        {
            "type": "column",
            "name": "name"
        },
        {
            "type": "column",
            "name": "health"
        }
    ],
    "predicate": {
        "type": "comparison",
        "operator": "greater_than",
        "left": {
            "type": "column",
            "name": "health"
        },
        "right": {
            "type": "literal",
            "value": 100
        }
    }
}
```

The decoder must treat serialized input as untrusted data.

It should validate:

- Supported operation types.
- Supported expression types.
- Maximum nesting depth.
- Maximum projection count.
- Maximum inserted-row count.
- Allowed tables.
- Allowed columns.
- Allowed functions.
- Literal sizes.
- Payload size.
- Query complexity.

A transport codec converts representations. It does not authorize operations.

---

## 8. Restricted remote queries

A system that permits remote querying should use capabilities or policies.

```gdscript
@abstract
class_name QueryAuthorizationPolicy
extends RefCounted

@abstract
func authorize(
    identity: RequestIdentity,
    query: QuerySpec,
    catalog: CatalogSnapshot
) -> QueryAuthorizationResult
```

A policy may define:

- Readable tables.
- Writable tables.
- Allowed columns.
- Allowed operations.
- Maximum result size.
- Maximum query cost.
- Allowed functions.
- Whether joins are permitted.
- Whether transactions are permitted.
- Whether mutations require ownership predicates.

Example:

```gdscript
class_name PlayerProfileQueryPolicy
extends QueryAuthorizationPolicy

func authorize(
    identity: RequestIdentity,
    query: QuerySpec,
    catalog: CatalogSnapshot
) -> QueryAuthorizationResult:
    if query is not SelectQuerySpec:
        return QueryAuthorizationResult.denied(
            &"READ_ONLY_ENDPOINT"
        )

    if query.source.table_name != &"player_profiles":
        return QueryAuthorizationResult.denied(
            &"TABLE_NOT_ALLOWED"
        )

    return QueryAuthorizationResult.allowed()
```

Authorization occurs before planning and execution.

---

## 9. Replication

Replication sends state changes from the authority to other peers.

It is separate from query execution.

```gdscript
@abstract
class_name ReplicationPublisher
extends RefCounted

@abstract
func publish(events: Array[ReplicationEvent]) -> void
```

```gdscript
@abstract
class_name ReplicationConsumer
extends RefCounted

@abstract
func apply(event: ReplicationEvent) -> ReplicationResult
```

A replication event describes an accepted state transition:

```gdscript
class_name RowChangedEvent
extends ReplicationEvent

var table_id: TableId
var row_id: RowId
var version: int
var changes: Dictionary
```

Replication events may include:

```text
RowCreatedEvent
RowChangedEvent
RowDeletedEvent
SnapshotCreatedEvent
TransactionCommittedEvent
```

Clients apply replicated state to a local cache:

```text
Authoritative transaction
    ↓
Committed domain or storage events
    ↓
ReplicationPublisher
    ↓
Network
    ↓
ReplicationConsumer
    ↓
ReplicatedDataStore
```

Clients do not independently replay the server’s original database query unless deterministic replay is an explicit system requirement.

The accepted result is replicated, not necessarily the implementation details that produced it.

---

## 10. Replicated data store

A replicated data store holds a local view of authoritative remote data.

```gdscript
@abstract
class_name ReplicatedDataStore
extends RefCounted

@abstract
func apply_snapshot(
    snapshot: ReplicationSnapshot
) -> ReplicationResult

@abstract
func apply_event(
    event: ReplicationEvent
) -> ReplicationResult

@abstract
func get_row(
    table_id: TableId,
    row_id: RowId
) -> RowRecord

@abstract
func get_version(
    table_id: TableId,
    row_id: RowId
) -> int
```

The replicated store may support local read queries:

```text
ReplicatedDataStore
    ↓
Read-only TableStorage adapter
    ↓
QueryExecutor
```

This permits a client to use the normal query pipeline against synchronized local data without sending every read request to the server.

For example:

```gdscript
class_name ReplicatedTableStorage
extends TableStorage
```

This implementation may allow:

- `read_table()`.
- `find_by_primary_key()`.

It may reject:

- `stage_insert()`.
- `stage_update()`.
- `stage_delete()`.
- `commit()`.

Mutations remain commands sent to the authority.

---

## 11. Read and write separation

Networked systems benefit from separating read and write paths.

```text
Writes:
Client command
    ↓
Authority
    ↓
Command handler
    ↓
QuerySpec mutation
    ↓
Transaction
    ↓
Replication event

Reads:
Client QuerySpec
    ↓
Local replicated store
```

This model is similar to command-query separation:

- Commands request state changes.
- Queries read existing state.
- Events distribute accepted changes.

The separation does not require a full event-sourcing architecture. It simply prevents remote writes from being treated as unrestricted database calls.

---

## 12. Offline-first data management

An offline-first game may maintain local changes until connectivity returns.

```gdscript
class_name PendingCommandQueue
extends RefCounted

var _commands: Array[QueuedCommand] = []

func enqueue(command: GameCommand) -> void:
    _commands.push_back(
        QueuedCommand.new(command)
    )

func get_pending() -> Array[QueuedCommand]:
    return _commands.duplicate()
```

The synchronization flow becomes:

```text
Offline action
    ↓
Local command validation
    ↓
Optimistic local state
    ↓
PendingCommandQueue
    ↓ connectivity restored
Remote authority
    ↓
Accepted or rejected result
    ↓
Reconciliation
```

This requires:

- Stable command identifiers.
- Idempotency.
- Version checks.
- Conflict handling.
- Retry policies.
- Reconciliation.
- Clear ownership of authoritative values.

The database layer alone cannot resolve gameplay conflicts. Conflict rules belong to the application domain.

Examples include:

- Last-write-wins.
- Server-wins.
- Client retry.
- Version rejection.
- Mergeable counters.
- Inventory-specific reconciliation.
- Compensation commands.

---

## 13. Optimistic concurrency

Networked mutations should support version checks where concurrent changes are possible.

```gdscript
class_name ConcurrencyCondition
extends RefCounted

var expected_version: int
```

An update may internally become:

```text
UPDATE inventory
SET quantity = quantity - 1,
    version = version + 1
WHERE player_id = ?
  AND item_id = ?
  AND version = expected_version
```

The result distinguishes:

```text
Mutation succeeded.
Row no longer exists.
Version conflict occurred.
Authorization failed.
Validation failed.
```

A generic failed update should not hide concurrency conflicts.

---

## 14. Transactions across network boundaries

A local `TransactionManager` coordinates one storage runtime.

Distributed transactions across multiple servers or services are a separate concern.

```text
Local transaction:
One runtime
One storage authority
One commit boundary

Distributed operation:
Multiple services
Multiple commit boundaries
Partial failure is possible
```

For distributed workflows, application-level orchestration is generally clearer than pretending that every remote operation belongs to one database transaction.

Possible patterns include:

- Saga orchestration.
- Compensation commands.
- Idempotent operations.
- Outbox records.
- Event delivery confirmation.
- Retryable workflow steps.

The core GDSQL transaction interface should remain local to one authoritative storage context.

---

## 15. Network transport boundary

Network transport should remain replaceable.

```gdscript
@abstract
class_name NetworkTransport
extends RefCounted

@abstract
func send(
    peer: PeerIdentity,
    message: NetworkMessage
) -> NetworkSendResult

@abstract
func broadcast(
    message: NetworkMessage,
    excluded_peers: Array[PeerIdentity] = []
) -> NetworkSendResult
```

Possible implementations include:

```text
GodotRpcTransport
EnetTransport
WebSocketTransport
HttpTransport
LoopbackTransport
```

Application commands and replication events do not depend directly on ENet, RPC annotations, HTTP requests, or WebSocket frames.

---

## 16. Serialization boundary

Network serialization is separate from storage serialization.

```text
GodotVariantCodec
    Encodes values for `.cfg` persistence.

NetworkMessageCodec
    Encodes commands and events for transport.

QuerySpecCodec
    Encodes canonical query structures when required.
```

These codecs may share lower-level value conversion utilities, but they have different compatibility and security requirements.

```gdscript
@abstract
class_name NetworkMessageCodec
extends RefCounted

@abstract
func encode(
    message: NetworkMessage
) -> PackedByteArray

@abstract
func decode(
    payload: PackedByteArray
) -> NetworkDecodingResult
```

Network codecs should include:

- Message type.
- Protocol version.
- Request or event identifier.
- Payload length.
- Schema version.
- Optional checksum or signature.
- Validation diagnostics.

---

## 17. Hybrid storage

A hybrid data store combines local and remote sources.

```gdscript
class_name HybridTableStorage
extends TableStorage

var _local: TableStorage
var _remote: RemoteDatabaseGateway
var _routing: StorageRoutingPolicy
```

A routing policy determines ownership:

```gdscript
@abstract
class_name StorageRoutingPolicy
extends RefCounted

@abstract
func resolve(
    table: TableDefinition,
    operation: QuerySpec.Operation
) -> StorageRoute
```

Possible routes include:

```text
LOCAL
REMOTE
REPLICATED_READ
LOCAL_THEN_REMOTE
REMOTE_WITH_LOCAL_CACHE
```

Example ownership:

| Data | Read location | Write authority |
|---|---|---|
| Item definitions | Local packaged data | Development tools |
| Player profile | Local replicated cache | Dedicated server |
| Match state | Memory or replicated cache | Match host |
| Save-game preferences | Local `.cfg` | Local client |
| Global economy | Cached remote view | Backend service |
| Session lobby | Replicated memory | Lobby host |

Hybrid routing remains below application commands and above physical storage implementations.

---

## 18. In-memory data

Some runtime data does not require immediate persistence.

```gdscript
class_name InMemoryTableStorage
extends TableStorage
```

It may be used for:

- Match state.
- Temporary sessions.
- Unit tests.
- Query benchmarks.
- Client-side replicated caches.
- Preview environments.
- Editor simulations.

Persistence may occur periodically:

```text
InMemoryTableStorage
    ↓ periodic snapshot
ConfigFileTableStorage
```

or remotely:

```text
InMemoryTableStorage
    ↓ commit event
RemoteDatabaseGateway
```

The query pipeline remains unchanged.

---

## 19. Event journal and replay

An optional event journal may record accepted state changes.

```gdscript
@abstract
class_name EventJournal
extends RefCounted

@abstract
func append(
    events: Array[DomainEvent]
) -> JournalAppendResult

@abstract
func read_from(
    sequence: int
) -> Array[DomainEvent]
```

An event journal can support:

- Debugging.
- Audit trails.
- Replication recovery.
- Session replay.
- State rebuilding.
- Desynchronization investigation.

This is an optional extension and should not be required by the base query runtime.

---

## 20. Network-aware composition root

A multiplayer server can compose the architecture differently from a local game.

```gdscript
class_name MultiplayerServerFactory
extends RefCounted

static func create(
    settings: ServerSettings
) -> ServerRuntime:
    var storage: TableStorage = \
        _create_server_storage(settings)

    var catalog: CatalogService = \
        _create_catalog(settings)

    var database := \
        GDSQLRuntimeFactory.create_with(
            storage,
            catalog
        )

    var command_bus := DefaultCommandBus.new()
    var permissions := DefaultPermissionService.new()
    var replication := DefaultReplicationPublisher.new(
        settings.transport,
        settings.message_codec
    )

    command_bus.register(
        PurchaseItemCommand,
        PurchaseItemHandler.new(
            database,
            settings.item_catalog,
            permissions
        )
    )

    return ServerRuntime.new(
        database,
        command_bus,
        replication
    )
```

A multiplayer client can use a different composition:

```gdscript
class_name MultiplayerClientFactory
extends RefCounted

static func create(
    settings: ClientSettings
) -> ClientRuntime:
    var replicated_store := \
        DefaultReplicatedDataStore.new()

    var storage: TableStorage = \
        ReplicatedTableStorage.new(
            replicated_store
        )

    var database := \
        GDSQLRuntimeFactory.create_read_only(
            storage,
            settings.catalog
        )

    var command_sender := \
        RemoteCommandSender.new(
            settings.transport,
            settings.message_codec
        )

    return ClientRuntime.new(
        database,
        command_sender,
        replicated_store
    )
```

The shared contracts remain stable while runtime composition changes by environment.

---

# Complete Architecture and Glossary Map

The following diagram maps the principal domains, classes, flow boundaries, and optional network extensions.

```mermaid
flowchart TB

%% =========================================================
%% PUBLIC API
%% =========================================================
subgraph API["Public API"]
    Database["Database<br/>Primary user-facing entry point"]
    DatabaseContext["DatabaseContext<br/>Pipeline coordinator"]
    Query["Query<br/>Fluent query entry point"]
    QueryResult["QueryResult<br/>Public query output"]
end

Database --> Query
Database --> DatabaseContext
DatabaseContext --> QueryResult

%% =========================================================
%% FRONTENDS
%% =========================================================
subgraph FRONTENDS["Query Frontends"]
    SQLText["SQL Text"]
    FluentInput["Fluent API Calls"]
    GraphInput["Query Graph Input"]
    ModelInput["Optional Model API"]
end

SQLText --> SqlLexer
FluentInput --> SelectQueryBuilder
GraphInput --> QueryGraph
ModelInput --> DatabaseModel

%% =========================================================
%% SQL LEXER
%% =========================================================
subgraph SQL_LEXER["SQL Lexer Domain"]
    SqlLexer["SqlLexer<br/>Text to tokens"]
    SqlToken["SqlToken<br/>Lexical unit"]
    TokenizationResult["TokenizationResult<br/>Tokens and diagnostics"]
    SourceSpan["SourceSpan<br/>Source location"]
end

SqlLexer --> TokenizationResult
TokenizationResult --> SqlToken
SqlToken --> SourceSpan
TokenizationResult --> QueryDiagnostic

%% =========================================================
%% SQL PARSER / AST
%% =========================================================
subgraph SQL_AST["SQL Parser and AST Domain"]
    SqlParser["SqlParser<br/>Tokens to SQL AST"]
    SqlParseResult["SqlParseResult<br/>Statement and diagnostics"]
    SqlStatement["SqlStatement<br/>Abstract SQL statement"]
    SqlSelectStatement["SqlSelectStatement<br/>SELECT syntax"]
    SqlColumnNode["SqlColumnNode<br/>Column syntax"]
    SqlTableNode["SqlTableNode<br/>Table syntax"]
    SqlBinaryExpressionNode["SqlBinaryExpressionNode<br/>Binary syntax expression"]
    SqlLiteralNode["SqlLiteralNode<br/>Literal syntax"]
end

TokenizationResult --> SqlParser
SqlParser --> SqlParseResult
SqlParseResult --> SqlStatement
SqlStatement --> SqlSelectStatement
SqlSelectStatement --> SqlColumnNode
SqlSelectStatement --> SqlTableNode
SqlSelectStatement --> SqlBinaryExpressionNode
SqlBinaryExpressionNode --> SqlColumnNode
SqlBinaryExpressionNode --> SqlLiteralNode
SqlParseResult --> QueryDiagnostic

%% =========================================================
%% SQL COMPILER
%% =========================================================
subgraph SQL_COMPILER["SQL Compilation Domain"]
    SqlQueryCompiler["SqlQueryCompiler<br/>SQL AST to QuerySpec"]
    QueryCompilationResult["QueryCompilationResult<br/>Compiled query and diagnostics"]
end

SqlParseResult --> SqlQueryCompiler
SqlQueryCompiler --> QueryCompilationResult
QueryCompilationResult --> QuerySpec
QueryCompilationResult --> QueryDiagnostic

%% =========================================================
%% GRAPH FRONTEND
%% =========================================================
subgraph GRAPH["Graph Frontend Domain"]
    QueryGraph["QueryGraph<br/>Graph query model"]
    GraphQueryCompiler["GraphQueryCompiler<br/>Graph to QuerySpec"]
end

QueryGraph --> GraphQueryCompiler
GraphQueryCompiler --> QuerySpec

%% =========================================================
%% FLUENT API
%% =========================================================
subgraph FLUENT["Fluent Query Domain"]
    SelectQueryBuilder["SelectQueryBuilder<br/>Controlled query construction"]
end

Query --> SelectQueryBuilder
SelectQueryBuilder --> SelectQuerySpec

%% =========================================================
%% OPTIONAL MODEL API
%% =========================================================
subgraph MODEL_API["Optional Model API"]
    DatabaseModel["DatabaseModel<br/>Model-oriented persistence"]
    ModelMapper["ModelMapper<br/>Model to QuerySpec"]
end

DatabaseModel --> ModelMapper
ModelMapper --> QuerySpec
ModelMapper --> ModelResultMaterializer

%% =========================================================
%% QUERY MODEL
%% =========================================================
subgraph QUERY_MODEL["Canonical Query Model"]
    QuerySpec["QuerySpec<br/>Abstract canonical operation"]
    SelectQuerySpec["SelectQuerySpec<br/>Read operation"]
    InsertQuerySpec["InsertQuerySpec<br/>Insert operation"]
    UpdateQuerySpec["UpdateQuerySpec<br/>Update operation"]
    DeleteQuerySpec["DeleteQuerySpec<br/>Delete operation"]
    QuerySpecVisitor["QuerySpecVisitor<br/>Query-type visitor"]

    QuerySource["QuerySource<br/>Abstract row source"]
    TableReference["TableReference<br/>Logical table reference"]
    JoinSpec["JoinSpec<br/>Join description"]
    InsertRow["InsertRow<br/>Insert values"]
    ColumnAssignment["ColumnAssignment<br/>Update assignment"]
    OrderClause["OrderClause<br/>Ordering description"]
    SortDirection["SortDirection<br/>ASC or DESC"]
    ComparisonOperator["ComparisonOperator<br/>Comparison type"]
    LogicalOperator["LogicalOperator<br/>Logical type"]
end

QuerySpec --> SelectQuerySpec
QuerySpec --> InsertQuerySpec
QuerySpec --> UpdateQuerySpec
QuerySpec --> DeleteQuerySpec

SelectQuerySpec --> QuerySource
SelectQuerySpec --> JoinSpec
SelectQuerySpec --> OrderClause
InsertQuerySpec --> TableReference
InsertQuerySpec --> InsertRow
UpdateQuerySpec --> TableReference
UpdateQuerySpec --> ColumnAssignment
DeleteQuerySpec --> TableReference

QuerySource --> TableReference
OrderClause --> SortDirection
SelectQuerySpec --> QuerySpecVisitor
InsertQuerySpec --> QuerySpecVisitor
UpdateQuerySpec --> QuerySpecVisitor
DeleteQuerySpec --> QuerySpecVisitor

%% =========================================================
%% EXPRESSION MODEL
%% =========================================================
subgraph EXPRESSIONS["Canonical Expression Model"]
    QueryExpression["QueryExpression<br/>Abstract canonical expression"]
    ExpressionVisitor["ExpressionVisitor<br/>Expression visitor"]
    ColumnExpression["ColumnExpression<br/>Column reference"]
    LiteralExpression["LiteralExpression<br/>Variant literal"]
    ComparisonExpression["ComparisonExpression<br/>Binary comparison"]
    LogicalExpression["LogicalExpression<br/>Logical composition"]
    FunctionExpression["FunctionExpression<br/>Function invocation"]
end

QueryExpression --> ColumnExpression
QueryExpression --> LiteralExpression
QueryExpression --> ComparisonExpression
QueryExpression --> LogicalExpression
QueryExpression --> FunctionExpression

ColumnExpression --> ExpressionVisitor
LiteralExpression --> ExpressionVisitor
ComparisonExpression --> ExpressionVisitor
LogicalExpression --> ExpressionVisitor
FunctionExpression --> ExpressionVisitor

ComparisonExpression --> ComparisonOperator
LogicalExpression --> LogicalOperator
SelectQuerySpec --> QueryExpression
JoinSpec --> QueryExpression
ColumnAssignment --> QueryExpression
OrderClause --> QueryExpression
InsertRow --> QueryExpression

%% =========================================================
%% DIAGNOSTICS AND RESULTS
%% =========================================================
subgraph DIAGNOSTICS["Diagnostics and Operation Results"]
    QueryDiagnostic["QueryDiagnostic<br/>Typed diagnostic"]
    OperationResult["OperationResult<br/>Generic value and diagnostics"]
    QueryValidationResult["QueryValidationResult"]
    QueryBindingResult["QueryBindingResult"]
    QueryPlanningResult["QueryPlanningResult"]
    QueryExecutionResult["QueryExecutionResult"]
    StorageOperationResult["StorageOperationResult"]
    StorageCommitResult["StorageCommitResult"]
end

OperationResult --> QueryDiagnostic
QueryValidationResult --> QueryDiagnostic
QueryBindingResult --> QueryDiagnostic
QueryPlanningResult --> QueryDiagnostic
QueryExecutionResult --> QueryDiagnostic
StorageOperationResult --> QueryDiagnostic
StorageCommitResult --> QueryDiagnostic
QueryDiagnostic --> SourceSpan

%% =========================================================
%% VALIDATION
%% =========================================================
subgraph VALIDATION["Semantic Validation Domain"]
    QueryValidator["QueryValidator<br/>Validation contract"]
    DefaultQueryValidator["DefaultQueryValidator<br/>Default semantic validator"]
end

QuerySpec --> QueryValidator
QueryValidator --> DefaultQueryValidator
DefaultQueryValidator --> CatalogSnapshot
DefaultQueryValidator --> QueryValidationResult

%% =========================================================
%% BINDING
%% =========================================================
subgraph BINDING["Binding Domain"]
    BoundQuery["BoundQuery<br/>Resolved canonical query"]
    BoundSelectQuery["BoundSelectQuery<br/>Resolved select query"]
    BoundQueryOperation["BoundQueryOperation<br/>Resolved operation"]
    BoundColumnExpression["BoundColumnExpression<br/>Resolved column"]
    TableId["TableId<br/>Stable table identifier"]
    ColumnId["ColumnId<br/>Stable column identifier"]
end

QueryValidationResult --> BoundQuery
BoundQuery --> BoundQueryOperation
BoundQueryOperation --> BoundSelectQuery
BoundQuery --> BoundColumnExpression
BoundColumnExpression --> TableId
BoundColumnExpression --> ColumnId
BoundQuery --> TableDefinition
BoundQuery --> ResultSchema

%% =========================================================
%% PLANNING
%% =========================================================
subgraph PLANNING["Query Planning Domain"]
    QueryPlanner["QueryPlanner<br/>BoundQuery to QueryPlan"]
    QueryPlan["QueryPlan<br/>Root executable plan"]
    PlanNode["PlanNode<br/>Abstract plan node"]
    PlanNodeVisitor["PlanNodeVisitor<br/>Plan visitor"]

    TableScanPlan["TableScanPlan<br/>Full table scan"]
    PrimaryKeyLookupPlan["PrimaryKeyLookupPlan<br/>Primary-key lookup"]
    FilterPlan["FilterPlan<br/>Predicate filtering"]
    ProjectionPlan["ProjectionPlan<br/>Column projection"]
    AggregatePlan["AggregatePlan<br/>Grouping and aggregation"]
    SortPlan["SortPlan<br/>Row ordering"]
    LimitPlan["LimitPlan<br/>Offset and limit"]
end

BoundQuery --> QueryPlanner
QueryPlanner --> QueryPlanningResult
QueryPlanningResult --> QueryPlan
QueryPlan --> PlanNode

PlanNode --> TableScanPlan
PlanNode --> PrimaryKeyLookupPlan
PlanNode --> FilterPlan
PlanNode --> ProjectionPlan
PlanNode --> AggregatePlan
PlanNode --> SortPlan
PlanNode --> LimitPlan

TableScanPlan --> PlanNodeVisitor
PrimaryKeyLookupPlan --> PlanNodeVisitor
FilterPlan --> PlanNodeVisitor
ProjectionPlan --> PlanNodeVisitor
AggregatePlan --> PlanNodeVisitor
SortPlan --> PlanNodeVisitor
LimitPlan --> PlanNodeVisitor

TableScanPlan --> TableDefinition
PrimaryKeyLookupPlan --> TableDefinition
FilterPlan --> QueryExpression
ProjectionPlan --> QueryExpression
AggregatePlan --> QueryExpression
SortPlan --> OrderClause
PlanNode --> ResultSchema

%% =========================================================
%% EXECUTION
%% =========================================================
subgraph EXECUTION["Query Execution Domain"]
    QueryExecutor["QueryExecutor<br/>Execution contract"]
    DefaultQueryExecutor["DefaultQueryExecutor<br/>GDScript executor"]
    ExecutionContext["ExecutionContext<br/>Runtime services"]
    ExpressionEvaluator["ExpressionEvaluator<br/>Expression execution"]
    QueryFunctionRegistry["QueryFunctionRegistry<br/>Function lookup"]
    QueryCancellationToken["QueryCancellationToken<br/>Cancellation state"]
    TransactionManager["TransactionManager<br/>Transaction coordination"]
end

QueryPlan --> QueryExecutor
QueryExecutor --> DefaultQueryExecutor
DefaultQueryExecutor --> ExecutionContext
DefaultQueryExecutor --> QueryExecutionResult
ExecutionContext --> CatalogService
ExecutionContext --> TableStorage
ExecutionContext --> TransactionManager
ExecutionContext --> ExpressionEvaluator
ExecutionContext --> QueryFunctionRegistry
ExecutionContext --> QueryCancellationToken
ExpressionEvaluator --> QueryExpression

%% =========================================================
%% CATALOG
%% =========================================================
subgraph CATALOG["Catalog Domain"]
    CatalogService["CatalogService<br/>Catalog contract"]
    ConfigFileCatalogService["ConfigFileCatalogService<br/>Config-backed catalog"]
    CatalogSnapshot["CatalogSnapshot<br/>Stable metadata view"]
    DatabaseDefinition["DatabaseDefinition"]
    TableDefinition["TableDefinition"]
    ColumnDefinition["ColumnDefinition"]
    IndexDefinition["IndexDefinition"]
end

CatalogService --> ConfigFileCatalogService
CatalogService --> CatalogSnapshot
CatalogSnapshot --> DatabaseDefinition
CatalogSnapshot --> TableDefinition
DatabaseDefinition --> TableDefinition
TableDefinition --> ColumnDefinition
TableDefinition --> IndexDefinition

%% =========================================================
%% STORAGE
%% =========================================================
subgraph STORAGE["Storage Domain"]
    TableStorage["TableStorage<br/>Abstract row storage"]
    ConfigFileTableStorage["ConfigFileTableStorage<br/>.cfg backend"]
    InMemoryTableStorage["InMemoryTableStorage<br/>Memory backend"]
    ReplicatedTableStorage["ReplicatedTableStorage<br/>Read-only replicated backend"]
    HybridTableStorage["HybridTableStorage<br/>Multi-source backend"]

    StorageSession["StorageSession<br/>Unit of work state"]
    TableSnapshot["TableSnapshot<br/>Stable table read"]
    RowRecord["RowRecord<br/>Runtime row"]
    DatabasePathResolver["DatabasePathResolver<br/>Logical-to-physical paths"]
    ConfigFileCache["ConfigFileCache<br/>Loaded file cache"]
    GodotVariantCodec["GodotVariantCodec<br/>Storage serialization"]
end

TableStorage --> ConfigFileTableStorage
TableStorage --> InMemoryTableStorage
TableStorage --> ReplicatedTableStorage
TableStorage --> HybridTableStorage

ConfigFileTableStorage --> DatabasePathResolver
ConfigFileTableStorage --> ConfigFileCache
ConfigFileTableStorage --> GodotVariantCodec
ConfigFileTableStorage --> StorageSession
ConfigFileTableStorage --> TableSnapshot
TableSnapshot --> RowRecord
TableStorage --> StorageOperationResult
TableStorage --> StorageCommitResult
TableStorage --> TableDefinition

%% =========================================================
%% RESULT MATERIALIZATION
%% =========================================================
subgraph MATERIALIZATION["Result and Materialization Domain"]
    RowSet["RowSet<br/>Internal execution rows"]
    ResultSchema["ResultSchema<br/>Output columns and types"]
    ResultMapping["ResultMapping<br/>Output mapping rules"]
    ResultMaterializer["ResultMaterializer<br/>Materialization contract"]

    DictionaryResultMaterializer["DictionaryResultMaterializer"]
    ResourceResultMaterializer["ResourceResultMaterializer"]
    ModelResultMaterializer["ModelResultMaterializer"]
    EditorTableMaterializer["EditorTableMaterializer"]
    CsvExportMaterializer["CsvExportMaterializer"]
end

QueryExecutionResult --> RowSet
RowSet --> RowRecord
RowSet --> ResultSchema
ResultMaterializer --> DictionaryResultMaterializer
ResultMaterializer --> ResourceResultMaterializer
ResultMaterializer --> ModelResultMaterializer
ResultMaterializer --> EditorTableMaterializer
ResultMaterializer --> CsvExportMaterializer
ResultMaterializer --> ResultMapping
ResultMaterializer --> RowSet
ResultMaterializer --> QueryResult

%% =========================================================
%% EDITOR
%% =========================================================
subgraph EDITOR["Editor Domain"]
    Workbench["Workbench"]
    SqlEditor["SQL Editor"]
    QueryGraphEditor["Query Graph Editor"]
    TableEditor["Table Editor"]
    DiagnosticsPanel["Diagnostics Panel"]
    ResultGrid["Result Grid"]
end

Workbench --> SqlEditor
Workbench --> QueryGraphEditor
Workbench --> TableEditor
SqlEditor --> SQLText
QueryGraphEditor --> QueryGraph
SqlEditor --> DiagnosticsPanel
QueryGraphEditor --> DiagnosticsPanel
TableEditor --> DiagnosticsPanel
QueryResult --> ResultGrid
QueryDiagnostic --> DiagnosticsPanel
EditorTableMaterializer --> ResultGrid

%% =========================================================
%% APPLICATION COMMANDS
%% =========================================================
subgraph COMMANDS["Application Command Domain"]
    GameCommand["GameCommand<br/>Requested gameplay intent"]
    PurchaseItemCommand["PurchaseItemCommand"]
    CommandHandler["CommandHandler<br/>Use-case contract"]
    PurchaseItemHandler["PurchaseItemHandler"]
    CommandContext["CommandContext"]
    CommandResult["CommandResult"]
    CommandBus["CommandBus"]
    PermissionService["PermissionService"]
end

GameCommand --> PurchaseItemCommand
CommandHandler --> PurchaseItemHandler
CommandBus --> CommandHandler
CommandBus --> GameCommand
PurchaseItemHandler --> CommandContext
PurchaseItemHandler --> PermissionService
PurchaseItemHandler --> DatabaseContext
PurchaseItemHandler --> QuerySpec
PurchaseItemHandler --> CommandResult

%% =========================================================
%% REMOTE DATABASE
%% =========================================================
subgraph REMOTE_QUERY["Remote Query Domain"]
    RemoteDatabaseGateway["RemoteDatabaseGateway<br/>Trusted remote data gateway"]
    RemoteQueryRequest["RemoteQueryRequest"]
    RemoteQueryResult["RemoteQueryResult"]
    RemoteQueryOperation["RemoteQueryOperation"]
    RemoteTransactionId["RemoteTransactionId"]
    QuerySpecCodec["QuerySpecCodec<br/>Query serialization"]
    QueryDecodingResult["QueryDecodingResult"]
    QueryAuthorizationPolicy["QueryAuthorizationPolicy"]
    QueryAuthorizationResult["QueryAuthorizationResult"]
    AuthenticationContext["AuthenticationContext"]
    RequestIdentity["RequestIdentity"]
end

RemoteDatabaseGateway --> RemoteQueryRequest
RemoteDatabaseGateway --> RemoteQueryResult
RemoteQueryRequest --> RemoteQueryOperation
RemoteQueryRequest --> RemoteTransactionId
RemoteQueryRequest --> AuthenticationContext
QuerySpecCodec --> QuerySpec
QuerySpecCodec --> QueryDecodingResult
QueryAuthorizationPolicy --> RequestIdentity
QueryAuthorizationPolicy --> QuerySpec
QueryAuthorizationPolicy --> CatalogSnapshot
QueryAuthorizationPolicy --> QueryAuthorizationResult

%% =========================================================
%% NETWORK TRANSPORT
%% =========================================================
subgraph NETWORK["Network Transport Domain"]
    NetworkTransport["NetworkTransport<br/>Transport contract"]
    GodotRpcTransport["GodotRpcTransport"]
    EnetTransport["EnetTransport"]
    WebSocketTransport["WebSocketTransport"]
    HttpTransport["HttpTransport"]
    LoopbackTransport["LoopbackTransport"]

    NetworkMessage["NetworkMessage"]
    NetworkMessageCodec["NetworkMessageCodec"]
    NetworkDecodingResult["NetworkDecodingResult"]
    NetworkSendResult["NetworkSendResult"]
    PeerIdentity["PeerIdentity"]
end

NetworkTransport --> GodotRpcTransport
NetworkTransport --> EnetTransport
NetworkTransport --> WebSocketTransport
NetworkTransport --> HttpTransport
NetworkTransport --> LoopbackTransport
NetworkTransport --> NetworkMessage
NetworkTransport --> NetworkSendResult
NetworkTransport --> PeerIdentity
NetworkMessageCodec --> NetworkMessage
NetworkMessageCodec --> NetworkDecodingResult

%% =========================================================
%% REPLICATION
%% =========================================================
subgraph REPLICATION["Replication Domain"]
    ReplicationPublisher["ReplicationPublisher<br/>Publishes accepted state changes"]
    ReplicationConsumer["ReplicationConsumer<br/>Applies replicated changes"]
    ReplicationEvent["ReplicationEvent"]
    RowCreatedEvent["RowCreatedEvent"]
    RowChangedEvent["RowChangedEvent"]
    RowDeletedEvent["RowDeletedEvent"]
    SnapshotCreatedEvent["SnapshotCreatedEvent"]
    TransactionCommittedEvent["TransactionCommittedEvent"]
    ReplicationSnapshot["ReplicationSnapshot"]
    ReplicationResult["ReplicationResult"]
    ReplicatedDataStore["ReplicatedDataStore<br/>Local authoritative view"]
end

ReplicationPublisher --> ReplicationEvent
ReplicationConsumer --> ReplicationEvent
ReplicationConsumer --> ReplicationResult
ReplicationEvent --> RowCreatedEvent
ReplicationEvent --> RowChangedEvent
ReplicationEvent --> RowDeletedEvent
ReplicationEvent --> SnapshotCreatedEvent
ReplicationEvent --> TransactionCommittedEvent
ReplicationConsumer --> ReplicatedDataStore
ReplicatedDataStore --> ReplicationSnapshot
ReplicatedDataStore --> RowRecord
ReplicatedDataStore --> TableId
ReplicatedDataStore --> RowId
ReplicatedTableStorage --> ReplicatedDataStore
ReplicationPublisher --> NetworkTransport
ReplicationConsumer --> NetworkMessageCodec

%% =========================================================
%% OFFLINE / SYNC
%% =========================================================
subgraph OFFLINE["Offline and Synchronization Domain"]
    PendingCommandQueue["PendingCommandQueue"]
    QueuedCommand["QueuedCommand"]
    ConcurrencyCondition["ConcurrencyCondition"]
    ReconciliationService["ReconciliationService"]
    StorageRoutingPolicy["StorageRoutingPolicy"]
    StorageRoute["StorageRoute"]
end

PendingCommandQueue --> QueuedCommand
QueuedCommand --> GameCommand
GameCommand --> ConcurrencyCondition
ReconciliationService --> PendingCommandQueue
ReconciliationService --> ReplicatedDataStore
HybridTableStorage --> StorageRoutingPolicy
StorageRoutingPolicy --> StorageRoute

%% =========================================================
%% EVENTS / JOURNAL
%% =========================================================
subgraph EVENTS["Optional Event Domain"]
    DomainEvent["DomainEvent"]
    EventJournal["EventJournal"]
    JournalAppendResult["JournalAppendResult"]
end

CommandResult --> DomainEvent
ReplicationPublisher --> DomainEvent
EventJournal --> DomainEvent
EventJournal --> JournalAppendResult

%% =========================================================
%% COMPOSITION ROOTS
%% =========================================================
subgraph COMPOSITION["Composition Roots"]
    GDSQLRuntimeFactory["GDSQLRuntimeFactory<br/>Local runtime composition"]
    MultiplayerServerFactory["MultiplayerServerFactory<br/>Server composition"]
    MultiplayerClientFactory["MultiplayerClientFactory<br/>Client composition"]
end

GDSQLRuntimeFactory --> DatabaseContext
GDSQLRuntimeFactory --> TableStorage
GDSQLRuntimeFactory --> CatalogService
GDSQLRuntimeFactory --> QueryValidator
GDSQLRuntimeFactory --> QueryPlanner
GDSQLRuntimeFactory --> QueryExecutor
GDSQLRuntimeFactory --> ResultMaterializer

MultiplayerServerFactory --> DatabaseContext
MultiplayerServerFactory --> CommandBus
MultiplayerServerFactory --> ReplicationPublisher
MultiplayerServerFactory --> NetworkTransport
MultiplayerServerFactory --> TableStorage

MultiplayerClientFactory --> DatabaseContext
MultiplayerClientFactory --> ReplicatedDataStore
MultiplayerClientFactory --> ReplicatedTableStorage
MultiplayerClientFactory --> NetworkTransport
MultiplayerClientFactory --> ReplicationConsumer

%% =========================================================
%% PRIMARY CROSS-DOMAIN FLOW
%% =========================================================
DatabaseContext --> QueryValidator
QueryValidationResult --> QueryBindingResult
QueryBindingResult --> BoundQuery
DatabaseContext --> QueryPlanner
DatabaseContext --> QueryExecutor
DatabaseContext --> ResultMaterializer

DefaultQueryExecutor --> TableStorage
DefaultQueryExecutor --> CatalogService
DefaultQueryExecutor --> TransactionManager
DefaultQueryExecutor --> ExpressionEvaluator

CommandBus --> NetworkTransport
NetworkTransport --> CommandBus

CommandResult --> ReplicationPublisher
ReplicationPublisher --> NetworkTransport
NetworkTransport --> ReplicationConsumer

RemoteDatabaseGateway --> NetworkTransport
RemoteDatabaseGateway --> QuerySpecCodec
RemoteDatabaseGateway --> QueryAuthorizationPolicy

HybridTableStorage --> RemoteDatabaseGateway
HybridTableStorage --> ConfigFileTableStorage
HybridTableStorage --> ReplicatedTableStorage
HybridTableStorage --> InMemoryTableStorage
```

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
classDef diagnostic fill:#FEE2E2,stroke:#DC2626,stroke-width:2px,color:#450A0A;
classDef runtime fill:#EDE9FE,stroke:#7C3AED,stroke-width:3px,color:#2E1065;
classDef editor fill:#FAE8FF,stroke:#C026D3,stroke-width:2px,color:#4A044E;
classDef future fill:#FFFFFF,stroke:#94A3B8,stroke-width:2px,stroke-dasharray:6 4,color:#475569;



    subgraph Frontends["Query Frontends"]
        SQLInput["SQL Text"]
        FluentAPI["Fluent Query API"]
        GraphInput["Query Graph"]
        FutureFrontend["Future Frontend"]
    end

    subgraph SQL["SQL Translation"]
        SqlLexer["SqlLexer"]
        SqlToken["SqlToken"]
        TokenizationResult["TokenizationResult"]

        SqlParser["SqlParser"]
        SqlParseResult["SqlParseResult"]

        SqlStatement["SqlStatement"]
        SqlSelectStatement["SqlSelectStatement"]
        SqlColumnNode["SqlColumnNode"]
        SqlTableNode["SqlTableNode"]
        SqlBinaryExpressionNode["SqlBinaryExpressionNode"]
        SqlLiteralNode["SqlLiteralNode"]

        SqlQueryCompiler["SqlQueryCompiler"]
        QueryCompilationResult["QueryCompilationResult"]
    end

    subgraph Fluent["Fluent Construction"]
        Query["Query"]
        SelectQueryBuilder["SelectQueryBuilder"]
        InsertQueryBuilder["InsertQueryBuilder"]
        UpdateQueryBuilder["UpdateQueryBuilder"]
        DeleteQueryBuilder["DeleteQueryBuilder"]
    end

    subgraph Graph["Graph Translation"]
        QueryGraph["QueryGraph"]
        GraphQueryCompiler["GraphQueryCompiler"]
    end

    subgraph Canonical["Canonical Query Model"]
        QuerySpec["QuerySpec"]

        SelectQuerySpec["SelectQuerySpec"]
        InsertQuerySpec["InsertQuerySpec"]
        UpdateQuerySpec["UpdateQuerySpec"]
        DeleteQuerySpec["DeleteQuerySpec"]

        QuerySpecVisitor["QuerySpecVisitor"]

        QuerySource["QuerySource"]
        TableReference["TableReference"]
        JoinSpec["JoinSpec"]
        InsertRow["InsertRow"]
        ColumnAssignment["ColumnAssignment"]
        OrderClause["OrderClause"]
        SortDirection["SortDirection"]
    end

    subgraph Expressions["Expression Model"]
        QueryExpression["QueryExpression"]
        ExpressionVisitor["ExpressionVisitor"]

        ColumnExpression["ColumnExpression"]
        LiteralExpression["LiteralExpression"]
        ComparisonExpression["ComparisonExpression"]
        LogicalExpression["LogicalExpression"]
        FunctionExpression["FunctionExpression"]

        ComparisonOperator["ComparisonOperator"]
        LogicalOperator["LogicalOperator"]
    end

    subgraph Validation["Validation and Binding"]
        QueryValidator["QueryValidator"]
        DefaultQueryValidator["DefaultQueryValidator"]
        QueryValidationResult["QueryValidationResult"]

        BoundQuery["BoundQuery"]
        BoundSelectQuery["BoundSelectQuery"]
        BoundInsertQuery["BoundInsertQuery"]
        BoundUpdateQuery["BoundUpdateQuery"]
        BoundDeleteQuery["BoundDeleteQuery"]
        BoundQueryOperation["BoundQueryOperation"]
        BoundColumnExpression["BoundColumnExpression"]

        TableId["TableId"]
        ColumnId["ColumnId"]
    end

    subgraph Planning["Query Planning"]
        QueryPlanner["QueryPlanner"]
        QueryPlan["QueryPlan"]

        PlanNode["PlanNode"]
        PlanNodeVisitor["PlanNodeVisitor"]

        TableScanPlan["TableScanPlan"]
        PrimaryKeyLookupPlan["PrimaryKeyLookupPlan"]
        FilterPlan["FilterPlan"]
        ProjectionPlan["ProjectionPlan"]
        AggregatePlan["AggregatePlan"]
        SortPlan["SortPlan"]
        LimitPlan["LimitPlan"]
        InsertPlan["InsertPlan"]
        UpdatePlan["UpdatePlan"]
        DeletePlan["DeletePlan"]
    end

    subgraph Execution["Query Execution"]
        QueryExecutor["QueryExecutor"]
        DefaultQueryExecutor["DefaultQueryExecutor"]
        ExecutionContext["ExecutionContext"]

        ExpressionEvaluator["ExpressionEvaluator"]
        QueryFunctionRegistry["QueryFunctionRegistry"]
        QueryCancellationToken["QueryCancellationToken"]
        TransactionManager["TransactionManager"]
    end

    subgraph Catalog["Catalog"]
        CatalogService["CatalogService"]
        ConfigFileCatalogService["ConfigFileCatalogService"]
        CatalogAdministrationService["CatalogAdministrationService"]
        ConfigFileCatalogAdministrationService["ConfigFileCatalogAdministrationService"]
        CatalogSnapshot["CatalogSnapshot"]

        DatabaseDefinition["DatabaseDefinition"]
        TableDefinition["TableDefinition"]
        ColumnDefinition["ColumnDefinition"]
        TableAlteration["TableAlteration"]
        IndexDefinition["IndexDefinition"]
    end

    subgraph Storage["Storage"]
        TableStorage["TableStorage"]
        ConfigFileTableStorage["ConfigFileTableStorage"]

        StorageSession["StorageSession"]
        TableSnapshot["TableSnapshot"]
        RowRecord["RowRecord"]

        DatabasePathResolver["DatabasePathResolver"]
        ConfigFileCache["ConfigFileCache"]
        GodotVariantCodec["GodotVariantCodec"]

        FutureStorage["Future Storage Backend"]
    end

    subgraph Results["Results and Materialization"]
        RowSet["RowSet"]
        ResultSchema["ResultSchema"]
        ResultMapping["ResultMapping"]

        ResultMaterializer["ResultMaterializer"]
        DictionaryResultMaterializer["DictionaryResultMaterializer"]
        ResourceResultMaterializer["ResourceResultMaterializer"]
        ModelResultMaterializer["ModelResultMaterializer"]
        EditorTableMaterializer["EditorTableMaterializer"]
        CsvExportMaterializer["CsvExportMaterializer"]

        DatabaseResult["DatabaseResult"]
        QueryResult["QueryResult"]
    end

    subgraph Diagnostics["Diagnostics"]
        QueryDiagnostic["QueryDiagnostic"]
        DiagnosticsCollection["Diagnostics"]
        SourceSpan["SourceSpan"]

        OperationResult["OperationResult"]
        CatalogOperationResult["CatalogOperationResult"]
        QueryExecutionResult["QueryExecutionResult"]
        QueryPlanningResult["QueryPlanningResult"]
        StorageOperationResult["StorageOperationResult"]
        StorageCommitResult["StorageCommitResult"]
    end

    subgraph Runtime["Runtime Facade"]
        Database["Database"]
        DatabaseContext["DatabaseContext"]
        GDSQLRuntimeFactory["GDSQLRuntimeFactory"]
    end

    subgraph Editor["Editor"]
        EditorBoundary["Editor Tools"]
    end



    SQLInput --> SqlLexer
    SqlLexer --> TokenizationResult
    TokenizationResult --> SqlToken
    TokenizationResult --> SqlParser
    SqlParser --> SqlParseResult
    SqlParseResult --> SqlStatement
    SqlStatement --> SqlSelectStatement

    SqlSelectStatement --> SqlColumnNode
    SqlSelectStatement --> SqlTableNode
    SqlSelectStatement --> SqlBinaryExpressionNode
    SqlBinaryExpressionNode --> SqlLiteralNode

    SqlParseResult --> SqlQueryCompiler
    SqlQueryCompiler --> QueryCompilationResult
    QueryCompilationResult --> QuerySpec

    FluentAPI --> Query
    Query --> SelectQueryBuilder
    SelectQueryBuilder --> QuerySpec
    Query --> InsertQueryBuilder
    InsertQueryBuilder --> InsertQuerySpec

    GraphInput --> QueryGraph
    QueryGraph --> GraphQueryCompiler
    GraphQueryCompiler --> QuerySpec

    FutureFrontend -.-> QuerySpec

    QuerySpec --> SelectQuerySpec
    QuerySpec --> InsertQuerySpec
    QuerySpec --> UpdateQuerySpec
    QuerySpec --> DeleteQuerySpec
    QuerySpec --> QuerySpecVisitor

    SelectQuerySpec --> QuerySource
    QuerySource --> TableReference
    SelectQuerySpec --> JoinSpec
    SelectQuerySpec --> OrderClause
    InsertQuerySpec --> InsertRow
    UpdateQuerySpec --> ColumnAssignment
    InsertQuerySpec --> TableReference
    UpdateQuerySpec --> TableReference
    DeleteQuerySpec --> TableReference
    OrderClause --> SortDirection

    QueryExpression --> ColumnExpression
    QueryExpression --> LiteralExpression
    QueryExpression --> ComparisonExpression
    QueryExpression --> LogicalExpression
    QueryExpression --> FunctionExpression
    QueryExpression --> ExpressionVisitor

    ComparisonExpression --> ComparisonOperator
    LogicalExpression --> LogicalOperator

    SelectQuerySpec --> QueryExpression
    JoinSpec --> QueryExpression
    ColumnAssignment --> QueryExpression
    OrderClause --> QueryExpression

    QuerySpec --> QueryValidator
    QueryValidator --> DefaultQueryValidator
    DefaultQueryValidator --> CatalogSnapshot
    DefaultQueryValidator --> QueryValidationResult

    QueryValidationResult --> BoundQuery
    BoundQuery --> BoundQueryOperation
    BoundQueryOperation --> BoundSelectQuery
    BoundQueryOperation --> BoundInsertQuery
    BoundQuery --> BoundColumnExpression
    BoundColumnExpression --> ExpressionVisitor
    BoundColumnExpression --> TableId
    BoundColumnExpression --> ColumnId

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
    PlanNode --> InsertPlan
    PlanNode --> PlanNodeVisitor

    QueryPlan --> QueryExecutor
    QueryExecutor --> DefaultQueryExecutor
    DefaultQueryExecutor --> ExecutionContext
    ExecutionContext --> CatalogService
    ExecutionContext --> TableStorage
    ExecutionContext --> TransactionManager
    ExecutionContext --> ExpressionEvaluator
    ExecutionContext --> QueryFunctionRegistry
    ExecutionContext --> QueryCancellationToken

    CatalogService --> CatalogSnapshot
    CatalogSnapshot --> DatabaseDefinition
    DatabaseDefinition --> TableDefinition
    TableDefinition --> ColumnDefinition
    TableDefinition --> IndexDefinition

    TableStorage --> ConfigFileTableStorage
    TableStorage -.-> FutureStorage
    ConfigFileTableStorage --> StorageSession
    ConfigFileTableStorage --> TableSnapshot
    TableSnapshot --> RowRecord
    ConfigFileTableStorage --> DatabasePathResolver
    ConfigFileTableStorage --> ConfigFileCache
    ConfigFileTableStorage --> GodotVariantCodec

    DefaultQueryExecutor --> QueryExecutionResult
    QueryExecutionResult --> RowSet
    RowSet --> RowRecord
    RowSet --> ResultSchema

    ResultMaterializer --> ResultMapping
    ResultMaterializer --> DictionaryResultMaterializer
    ResultMaterializer --> ResourceResultMaterializer
    ResultMaterializer --> ModelResultMaterializer
    ResultMaterializer --> EditorTableMaterializer
    ResultMaterializer --> CsvExportMaterializer
    RowSet --> ResultMaterializer
    ResultMaterializer --> QueryResult

    QueryDiagnostic --> SourceSpan
    DiagnosticsCollection --> QueryDiagnostic
    QueryValidationResult --> QueryDiagnostic
    QueryPlanningResult --> QueryDiagnostic
    QueryExecutionResult --> QueryDiagnostic
    StorageOperationResult --> QueryDiagnostic
    StorageCommitResult --> QueryDiagnostic

    Database --> DatabaseContext
    DatabaseContext --> QueryValidator
    DatabaseContext --> QueryPlanner
    DatabaseContext --> QueryExecutor
    DatabaseContext --> ResultMaterializer

    GDSQLRuntimeFactory --> DatabaseContext
    GDSQLRuntimeFactory --> CatalogService
    GDSQLRuntimeFactory --> TableStorage
    GDSQLRuntimeFactory --> QueryValidator
    GDSQLRuntimeFactory --> QueryPlanner
    GDSQLRuntimeFactory --> QueryExecutor

    EditorBoundary --> Database
    EditorBoundary --> QueryGraph
    EditorBoundary --> QueryResult
    EditorBoundary --> QueryDiagnostic

    CatalogService --> ConfigFileCatalogService
    ConfigFileCatalogService --> DatabasePathResolver
    CatalogAdministrationService --> ConfigFileCatalogAdministrationService
    ConfigFileCatalogAdministrationService --> DatabasePathResolver
    CatalogAdministrationService --> CatalogOperationResult
    Database --> CatalogOperationResult
    DatabaseContext --> CatalogAdministrationService
    GDSQLRuntimeFactory --> CatalogAdministrationService
    GDSQLRuntimeFactory --> ConfigFileCatalogAdministrationService
    OperationResult --> DatabaseResult
    Database --> DatabaseResult
    OperationResult --> DiagnosticsCollection
    OperationResult --> QueryResult
    CatalogAdministrationService --> TableAlteration
    Query --> UpdateQueryBuilder
    UpdateQueryBuilder --> UpdateQuerySpec
    Query --> DeleteQueryBuilder
    DeleteQueryBuilder --> DeleteQuerySpec
    BoundQueryOperation --> BoundUpdateQuery
    BoundQueryOperation --> BoundDeleteQuery
    PlanNode --> UpdatePlan
    PlanNode --> DeletePlan

%% SQL translation: edges 0–13
linkStyle 0,1,2,3,4,5,6,7,8,9,10,11,12,13 stroke:#8B5CF6,stroke-width:2.5px;

%% Fluent API: edges 14–18
linkStyle 14,15,16,17,18 stroke:#3B82F6,stroke-width:2.5px;

%% Graph frontend: edges 19–21
linkStyle 19,20,21 stroke:#C026D3,stroke-width:2.5px;

%% Future frontend extension: edge 22
linkStyle 22 stroke:#94A3B8,stroke-width:2px,stroke-dasharray:6 4;

%% Canonical QuerySpec model: edges 23–37
linkStyle 23,24,25,26,27,28,29,30,31,32,33,34,35,36,37 stroke:#D97706,stroke-width:2px;

%% Expression model: edges 38–49
linkStyle 38,39,40,41,42,43,44,45,46,47,48,49 stroke:#CA8A04,stroke-width:2px;

%% Validation and binding: edges 50–61
linkStyle 50,51,52,53,54,55,56,57,58,59,60,61 stroke:#DB2777,stroke-width:2.5px;

%% Planning: edges 62–74
linkStyle 62,63,64,65,66,67,68,69,70,71,72,73,74 stroke:#EA580C,stroke-width:2.5px;

%% Execution: edges 75–83
linkStyle 75,76,77,78,79,80,81,82,83 stroke:#16A34A,stroke-width:2.5px;

%% Catalog: edges 84–88
linkStyle 84,85,86,87,88 stroke:#0284C7,stroke-width:2px;

%% Storage: edges 89–96
linkStyle 89,91,92,93,94,95,96 stroke:#0F766E,stroke-width:2.5px;

%% Future storage extension: edge 90
linkStyle 90 stroke:#94A3B8,stroke-width:2px,stroke-dasharray:6 4;

%% Execution output: edges 97–100
linkStyle 97,98,99,100 stroke:#16A34A,stroke-width:2px;

%% Result materialization: edges 101–108
linkStyle 101,102,103,104,105,106,107,108 stroke:#475569,stroke-width:2.5px;

%% Diagnostics: edges 109–115
linkStyle 109,110,111,112,113,114,115 stroke:#DC2626,stroke-width:1.8px;

%% Runtime facade: edges 116–126
linkStyle 116,117,118,119,120,121,122,123,124,125,126 stroke:#7C3AED,stroke-width:2.5px;

%% Editor boundary: edges 127–130
linkStyle 127,128,129,130 stroke:#C026D3,stroke-width:2px;

%% Catalog administration and backend composition: edges 131–139
linkStyle 131,132,133,134,135,136,137,138,139 stroke:#0284C7,stroke-width:2px;

%% Public database result: edges 140–141
linkStyle 140,141 stroke:#475569,stroke-width:2px;

%% Composed diagnostics and query result inheritance: edges 142–143
linkStyle 142,143 stroke:#475569,stroke-width:2px;

%% Typed table alteration: edge 144
linkStyle 144 stroke:#0284C7,stroke-width:2px;

%% Fluent update/delete: edges 145–148
linkStyle 145,146,147,148 stroke:#3B82F6,stroke-width:2.5px;

%% Mutation binding and planning: edges 149–152
linkStyle 149,150 stroke:#DB2777,stroke-width:2.5px;
linkStyle 151,152 stroke:#EA580C,stroke-width:2.5px;


%% Frontends
class SQLInput,FluentAPI,GraphInput frontend;
class FutureFrontend future;

%% SQL, fluent, and graph translation
class SqlLexer,SqlToken,TokenizationResult translation;
class SqlParser,SqlParseResult,SqlStatement,SqlSelectStatement translation;
class SqlColumnNode,SqlTableNode,SqlBinaryExpressionNode,SqlLiteralNode translation;
class SqlQueryCompiler,QueryCompilationResult translation;
class Query,SelectQueryBuilder,InsertQueryBuilder,UpdateQueryBuilder,DeleteQueryBuilder,QueryGraph,GraphQueryCompiler translation;

%% Canonical query and expression models
class QuerySpec,SelectQuerySpec,InsertQuerySpec,UpdateQuerySpec,DeleteQuerySpec canonical;
class QuerySpecVisitor,QuerySource,TableReference,JoinSpec canonical;
class InsertRow,ColumnAssignment,OrderClause,SortDirection canonical;
class QueryExpression,ExpressionVisitor,ColumnExpression,LiteralExpression canonical;
class ComparisonExpression,LogicalExpression,FunctionExpression canonical;
class ComparisonOperator,LogicalOperator canonical;

%% Validation and binding
class QueryValidator,DefaultQueryValidator,QueryValidationResult validation;
class BoundQuery,BoundSelectQuery,BoundInsertQuery,BoundUpdateQuery,BoundDeleteQuery,BoundQueryOperation validation;
class BoundColumnExpression,TableId,ColumnId validation;

%% Planning
class QueryPlanner,QueryPlanningResult,QueryPlan planning;
class PlanNode,PlanNodeVisitor,TableScanPlan,PrimaryKeyLookupPlan planning;
class FilterPlan,ProjectionPlan,AggregatePlan,SortPlan,LimitPlan,InsertPlan,UpdatePlan,DeletePlan planning;

%% Execution
class QueryExecutor,DefaultQueryExecutor,ExecutionContext execution;
class ExpressionEvaluator,QueryFunctionRegistry,QueryCancellationToken execution;
class TransactionManager,QueryExecutionResult execution;

%% Catalog
class CatalogService,ConfigFileCatalogService,CatalogSnapshot catalog;
class CatalogAdministrationService,ConfigFileCatalogAdministrationService catalog;
class DatabaseDefinition,TableDefinition,ColumnDefinition,TableAlteration,IndexDefinition catalog;

%% Storage
class TableStorage,ConfigFileTableStorage storage;
class StorageSession,TableSnapshot,RowRecord storage;
class DatabasePathResolver,ConfigFileCache,GodotVariantCodec storage;
class FutureStorage future;

%% Results
class RowSet,ResultSchema,ResultMapping result;
class ResultMaterializer,DictionaryResultMaterializer result;
class ResourceResultMaterializer,ModelResultMaterializer result;
class EditorTableMaterializer,CsvExportMaterializer,DatabaseResult,QueryResult result;

%% Diagnostics
class QueryDiagnostic,DiagnosticsCollection,SourceSpan,OperationResult,CatalogOperationResult diagnostic;
class QueryPlanningResult,StorageOperationResult,StorageCommitResult diagnostic;

%% Runtime and editor
class Database,DatabaseContext,GDSQLRuntimeFactory runtime;
class EditorBoundary editor;

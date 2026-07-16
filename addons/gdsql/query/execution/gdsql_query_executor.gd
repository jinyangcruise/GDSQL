@abstract
class_name GDSQLQueryExecutor
extends RefCounted

@abstract
func execute(plan: GDSQLQueryPlan, context: GDSQLExecutionContext) -> GDSQLQueryExecutionResult

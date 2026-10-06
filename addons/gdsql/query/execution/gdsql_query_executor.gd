@abstract
class_name GDSQLQueryExecutor
extends RefCounted

@abstract
func execute(plan: GDSQLQueryPlan, context: GDSQLExecutionContext) -> GDSQLQueryExecutionResult


func _tr(message: StringName) -> StringName:
	return TranslationServer.get_or_add_domain(&"GDSQL").translate(message)

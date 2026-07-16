class_name GDSQLPlanNodeVisitor
extends RefCounted

func visit_table_scan(node: GDSQLTableScanPlan) -> Variant:
	return null


func visit_primary_key_lookup(node: GDSQLPrimaryKeyLookupPlan) -> Variant:
	return null


func visit_filter(node: GDSQLFilterPlan) -> Variant:
	return null


func visit_projection(node: GDSQLProjectionPlan) -> Variant:
	return null


func visit_aggregate(node: GDSQLAggregatePlan) -> Variant:
	return null


func visit_sort(node: GDSQLSortPlan) -> Variant:
	return null


func visit_limit(node: GDSQLLimitPlan) -> Variant:
	return null


func visit_insert(node: GDSQLInsertPlan) -> Variant:
	return null


func visit_update(node: GDSQLUpdatePlan) -> Variant:
	return null


func visit_delete(node: GDSQLDeletePlan) -> Variant:
	return null

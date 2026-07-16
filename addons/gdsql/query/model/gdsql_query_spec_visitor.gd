class_name GDSQLQuerySpecVisitor
extends RefCounted

func visit_select(query: GDSQLSelectQuerySpec) -> Variant:
	return null


func visit_insert(query: GDSQLInsertQuerySpec) -> Variant:
	return null


func visit_update(query: GDSQLUpdateQuerySpec) -> Variant:
	return null


func visit_delete(query: GDSQLDeleteQuerySpec) -> Variant:
	return null

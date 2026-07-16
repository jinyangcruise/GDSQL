class_name GDSQLModelMapper
extends RefCounted

func to_insert(model: GDSQLDatabaseModel) -> GDSQLInsertQuerySpec:
	return null


func to_update(model: GDSQLDatabaseModel) -> GDSQLUpdateQuerySpec:
	return null


func materialize(rows: GDSQLRowSet) -> GDSQLQueryResult:
	return null

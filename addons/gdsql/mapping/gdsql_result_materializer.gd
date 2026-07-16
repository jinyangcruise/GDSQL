@abstract
class_name GDSQLResultMaterializer
extends RefCounted

@abstract
func materialize(rows: GDSQLRowSet, mapping: GDSQLResultMapping = null) -> GDSQLQueryResult

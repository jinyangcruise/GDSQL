class_name GDSQLInsertQueryBuilder
extends RefCounted

var _database_name: StringName
var _table_name: StringName
var _columns: Array[StringName] = []
var _rows: Array[GDSQLInsertRow] = []
var _built: bool = false


func _init(
		database_name: StringName = &"",
		table_name: StringName = &"",
) -> void:
	_database_name = database_name
	_table_name = table_name


func into_table(table_name: StringName) -> GDSQLInsertQueryBuilder:
	_ensure_mutable()
	_table_name = table_name
	return self


func values(row: Dictionary) -> GDSQLInsertQueryBuilder:
	_ensure_mutable()
	if _columns.is_empty():
		for key: Variant in row.keys():
			_columns.append(StringName(str(key)))
	var ordered_values: Array[Variant] = []
	for column in _columns:
		if row.has(column):
			ordered_values.append(row[column])
		else:
			ordered_values.append(row.get(String(column)))
	_rows.append(GDSQLInsertRow.new(ordered_values))
	return self


func build() -> GDSQLInsertQuerySpec:
	_ensure_mutable()
	_built = true
	var spec := GDSQLInsertQuerySpec.new()
	spec.target = GDSQLTableReference.new(_table_name, _database_name)
	spec.columns = _columns.duplicate()
	spec.rows = _rows.duplicate()
	return spec


func _ensure_mutable() -> void:
	assert(not _built, "Insert query builder cannot be modified after build().")

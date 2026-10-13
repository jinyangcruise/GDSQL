extends RefCounted

const CURSOR_KIND := &"ordered_index"


static func cursor_offset(
	cursor: GDSQLStorageReadCursor,
	index: GDSQLIndexDefinition,
	direction: GDSQLStorageOrderDirection.Direction,
	result: GDSQLStorageReadBatch,
) -> int:
	if cursor == null:
		return 0
	var token: Variant = cursor.get_token()
	if token is Dictionary:
		var data := token as Dictionary
		var offset: Variant = data.get("offset")
		if data.get("kind") == CURSOR_KIND \
				and StringName(data.get("index", &"")) == index.name \
				and int(data.get("direction", -1)) == direction \
				and offset is int and int(offset) >= 0:
			return int(offset)
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_STORAGE_ORDERED_INDEX_CURSOR_MISMATCH",
			"The cursor belongs to a different ordered index read.",
		),
	)
	return 0


static func create_cursor(
	backend_id: StringName,
	table: GDSQLTableDefinition,
	index: GDSQLIndexDefinition,
	direction: GDSQLStorageOrderDirection.Direction,
	offset: int,
) -> GDSQLStorageReadCursor:
	return GDSQLStorageReadCursor.new(
		backend_id,
		table.database_name,
		table.name,
		{
			"kind": CURSOR_KIND,
			"index": index.name,
			"direction": direction,
			"offset": offset,
		},
	)


static func sort_rows(
	rows: Array[GDSQLRowRecord],
	index: GDSQLIndexDefinition,
	direction: GDSQLStorageOrderDirection.Direction,
) -> void:
	rows.sort_custom(_row_precedes.bind(index, direction))


static func values_precede(
	left: Array,
	right: Array,
	direction: GDSQLStorageOrderDirection.Direction,
) -> bool:
	for value_index in mini(left.size(), right.size()):
		var comparison := compare_values(left[value_index], right[value_index])
		if comparison == 0:
			continue
		if direction == GDSQLStorageOrderDirection.Direction.DESCENDING:
			return comparison > 0
		return comparison < 0
	return false


static func compare_values(left: Variant, right: Variant) -> int:
	if left == right:
		return 0
	if left == null:
		return -1
	if right == null:
		return 1
	if (typeof(left) == TYPE_INT or typeof(left) == TYPE_FLOAT) \
			and (typeof(right) == TYPE_INT or typeof(right) == TYPE_FLOAT):
		return -1 if left < right else 1
	if typeof(left) == typeof(right):
		match typeof(left):
			TYPE_STRING, TYPE_STRING_NAME:
				return -1 if String(left) < String(right) else 1
			TYPE_BOOL:
				return -1 if not bool(left) else 1
	var left_text := str(left)
	var right_text := str(right)
	if left_text == right_text:
		return 0
	return -1 if left_text < right_text else 1


static func _row_precedes(
	left: GDSQLRowRecord,
	right: GDSQLRowRecord,
	index: GDSQLIndexDefinition,
	direction: GDSQLStorageOrderDirection.Direction,
) -> bool:
	return values_precede(
		_index_values(left, index),
		_index_values(right, index),
		direction,
	)


static func _index_values(
	row: GDSQLRowRecord,
	index: GDSQLIndexDefinition,
) -> Array:
	var values: Array = []
	for column_name in index.columns:
		values.append(row.get_value(column_name))
	return values

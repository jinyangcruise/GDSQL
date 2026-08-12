@tool
class_name GDSQLQueryGraphSourceSelector
extends VBoxContainer
## Shared registration/table selector backed only by inspection metadata.

signal changed(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
)

var _inspections: Array[GDSQLDatabaseInspection] = []

@onready var _database: OptionButton = %Database
@onready var _table: OptionButton = %Table


func _ready() -> void:
	_database.item_selected.connect(_on_database_selected)
	_table.item_selected.connect(_on_table_selected)


func configure(
		inspections: Array[GDSQLDatabaseInspection],
		selected_registration: StringName,
		selected_table: StringName,
) -> void:
	_inspections.clear()
	for inspection in inspections:
		if inspection != null and inspection.registration != null:
			_inspections.append(inspection)
	_inspections.sort_custom(_sort_inspections)
	_populate_databases(selected_registration)
	_populate_tables(selected_table)
	_emit_changed()


func get_selected_registration() -> StringName:
	if _database == null or _database.selected < 0:
		return &""
	return StringName(_database.get_item_metadata(_database.selected))


func get_selected_database() -> StringName:
	var inspection := get_selected_inspection()
	return inspection.registration.database_name if inspection != null else &""


func get_selected_table() -> StringName:
	if _table == null or _table.selected < 0:
		return &""
	return StringName(_table.get_item_metadata(_table.selected))


func get_selected_inspection() -> GDSQLDatabaseInspection:
	var registration_name := get_selected_registration()
	for inspection in _inspections:
		if inspection.registration.name == registration_name:
			return inspection
	return null


func get_selected_table_inspection() -> GDSQLTableInspection:
	var inspection := get_selected_inspection()
	return inspection.get_table(get_selected_table()) if inspection != null else null


func _populate_databases(selected_registration: StringName) -> void:
	_database.clear()
	for inspection in _inspections:
		var registration := inspection.registration
		_database.add_item(String(registration.database_name))
		var index := _database.item_count - 1
		_database.set_item_metadata(index, registration.name)
		_database.set_item_tooltip(
			index,
			"Location: %s\nRuntime storage: %s" % [
				registration.data_root,
				GDSQLStorageBackendIds.get_display_name(registration.storage_backend_id),
			],
		)
		if registration.name == selected_registration:
			_database.select(index)
	_database.disabled = _database.item_count == 0
	if _database.item_count > 0 and _database.selected < 0:
		_database.select(0)


func _populate_tables(selected_table: StringName = &"") -> void:
	_table.clear()
	var inspection := get_selected_inspection()
	if inspection == null:
		_table.disabled = true
		return
	var tables := inspection.tables.duplicate()
	tables.sort_custom(_sort_tables)
	for table_inspection in tables:
		_table.add_item(String(table_inspection.name))
		var index := _table.item_count - 1
		_table.set_item_metadata(index, table_inspection.name)
		_table.set_item_tooltip(
			index,
			"%d columns · %d rows" % [
				table_inspection.column_count,
				table_inspection.row_count,
			],
		)
		if table_inspection.name == selected_table:
			_table.select(index)
	_table.disabled = _table.item_count == 0
	if _table.item_count > 0 and _table.selected < 0:
		_table.select(0)


func _on_database_selected(_index: int) -> void:
	_populate_tables()
	_emit_changed()


func _on_table_selected(_index: int) -> void:
	_emit_changed()


func _emit_changed() -> void:
	changed.emit(
		get_selected_registration(),
		get_selected_database(),
		get_selected_table(),
	)


func _sort_inspections(left: GDSQLDatabaseInspection, right: GDSQLDatabaseInspection) -> bool:
	return String(left.registration.database_name) < String(right.registration.database_name)


func _sort_tables(left: GDSQLTableInspection, right: GDSQLTableInspection) -> bool:
	return String(left.name) < String(right.name)

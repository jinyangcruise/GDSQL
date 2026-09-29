class_name GDSQLEditorCommandPalette
extends RefCounted
## Projects the lightweight workbench inventory into Godot's command palette.

const COMMAND_PREFIX := "gdsql/navigation/"

var _palette: EditorCommandPalette
var _workbench: GDSQLWorkbench
var _action_hub: GDSQLEditorActionHub
var _command_keys: Array[String] = []


func _init(
		palette: EditorCommandPalette,
		workbench: GDSQLWorkbench,
		action_hub: GDSQLEditorActionHub,
) -> void:
	_palette = palette
	_workbench = workbench
	_action_hub = action_hub


func refresh() -> void:
	clear()
	if _palette == null or _workbench == null or _action_hub == null:
		return
	var inspections := _workbench.get_inspections()
	inspections.sort_custom(_sort_inspections)
	for inspection in inspections:
		_add_database_command(inspection)
		var tables := inspection.tables.duplicate()
		tables.sort_custom(_sort_tables)
		for table in tables:
			_add_table_command(inspection, table)


func clear() -> void:
	if _palette != null:
		for command_key in _command_keys:
			_palette.remove_command(command_key)
	_command_keys.clear()


func _add_database_command(inspection: GDSQLDatabaseInspection) -> void:
	if inspection == null or inspection.registration == null:
		return
	var registration_name := inspection.registration.name
	var command_key := "%sdatabase/%s" % [COMMAND_PREFIX, registration_name]
	var display_name := "GDSQL: Open database %s" \
			% inspection.registration.database_name
	if registration_name != inspection.registration.database_name:
		display_name += " (%s)" % registration_name
	_palette.add_command(
		display_name,
		command_key,
		_invoke.bind(
			GDSQLEditorActionIds.OPEN_REGISTRATION,
			[registration_name],
		),
	)
	_command_keys.append(command_key)


func _add_table_command(
		inspection: GDSQLDatabaseInspection,
		table: GDSQLTableInspection,
) -> void:
	if table == null:
		return
	var registration_name := inspection.registration.name
	var command_key := "%stable/%s/%s" % [
		COMMAND_PREFIX,
		registration_name,
		table.name,
	]
	var column_names := PackedStringArray()
	for column in table.columns:
		column_names.append(String(column.name))
	var display_name := "GDSQL: Open table %s / %s" % [
		inspection.registration.database_name,
		table.name,
	]
	if not column_names.is_empty():
		display_name += " · %s" % ", ".join(column_names)
	_palette.add_command(
		display_name,
		command_key,
		_invoke.bind(
			GDSQLEditorActionIds.SELECT_TABLE,
			[registration_name, table.name],
		),
	)
	_command_keys.append(command_key)


func _invoke(action_id: StringName, arguments: Array) -> void:
	_action_hub.invoke(action_id, arguments, true)


func _sort_inspections(
		left: GDSQLDatabaseInspection,
		right: GDSQLDatabaseInspection,
) -> bool:
	var left_key := "%s/%s" % [
		left.registration.database_name,
		left.registration.name,
	]
	var right_key := "%s/%s" % [
		right.registration.database_name,
		right.registration.name,
	]
	return left_key.naturalnocasecmp_to(right_key) < 0


func _sort_tables(left: GDSQLTableInspection, right: GDSQLTableInspection) -> bool:
	return String(left.name).naturalnocasecmp_to(String(right.name)) < 0

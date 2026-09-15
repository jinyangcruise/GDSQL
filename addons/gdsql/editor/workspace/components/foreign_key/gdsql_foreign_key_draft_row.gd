@tool
class_name GDSQLEditorForeignKeyDraftRow
extends PanelContainer
## Scene-backed authoring row for one same-database foreign key.

signal changed
signal remove_requested(row: Control)

var _database: GDSQLDatabaseDefinition
var _source_table: GDSQLTableDefinition
var _configuring := false

@onready var _name: LineEdit = %Name
@onready var _local_column: OptionButton = %LocalColumn
@onready var _target_table: OptionButton = %TargetTable
@onready var _target_column: OptionButton = %TargetColumn


func _ready() -> void:
	_local_column.item_selected.connect(_on_local_column_selected.unbind(1))
	_target_table.item_selected.connect(_on_target_table_selected.unbind(1))
	_target_column.item_selected.connect(_on_target_column_selected.unbind(1))
	%Remove.pressed.connect(remove_requested.emit.bind(self))
	for button in [_local_column, _target_table, _target_column]:
		button.get_popup().allow_search = true


func configure(
		database: GDSQLDatabaseDefinition,
		source_table: GDSQLTableDefinition,
) -> void:
	_database = database
	_source_table = source_table
	_rebuild_options(&"", &"", &"")


func refresh_context(
		database: GDSQLDatabaseDefinition,
		source_table: GDSQLTableDefinition,
) -> void:
	var local_name := _selected_name(_local_column)
	var table_name := _selected_name(_target_table)
	var column_name := _selected_name(_target_column)
	_database = database
	_source_table = source_table
	_rebuild_options(local_name, table_name, column_name)


func build_definition() -> GDSQLForeignKeyDefinition:
	return GDSQLForeignKeyDefinition.new(
		StringName(_name.text.strip_edges()),
		_selected_name(_local_column),
		_selected_name(_target_table),
		_selected_name(_target_column),
	)


func get_validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var definition := build_definition()
	if definition.name == &"":
		errors.append("Every foreign key requires a constraint name.")
	elif not String(definition.name).is_valid_identifier():
		errors.append("Foreign key '%s' must use a valid identifier." % definition.name)
	var local := _source_table.get_column(definition.column) if _source_table != null else null
	if local == null:
		errors.append("Foreign key '%s' requires a local column." % definition.name)
	elif not GDSQLForeignKeyDefinition.supports_column_type(local.data_type):
		errors.append("Foreign key column '%s' must use int, String, or StringName." % local.name)
	var target := _find_table(definition.referenced_table)
	if target == null:
		errors.append("Foreign key '%s' requires a referenced table." % definition.name)
	elif definition.referenced_column == &"" \
			or not _is_compatible_target(target, definition.referenced_column, local):
		errors.append("Foreign key '%s' requires a matching unique target column." % definition.name)
	return errors


func get_constraint_name() -> StringName:
	return StringName(_name.text.strip_edges())


func get_local_column_name() -> StringName:
	return _selected_name(_local_column)


func focus_local_column() -> void:
	_local_column.grab_focus()


func _rebuild_options(
		local_name: StringName,
		table_name: StringName,
		column_name: StringName,
) -> void:
	_configuring = true
	_populate_local_columns(local_name)
	_populate_target_tables(table_name)
	_populate_target_columns(column_name)
	_update_constraint_name()
	_configuring = false


func _populate_local_columns(preferred: StringName) -> void:
	_local_column.clear()
	if _source_table != null:
		for column in _source_table.columns:
			if GDSQLForeignKeyDefinition.supports_column_type(column.data_type):
				_local_column.add_item(String(column.name))
				_local_column.set_item_metadata(_local_column.item_count - 1, column.name)
	_select_name(_local_column, preferred)
	_set_empty_state(_local_column, "No key-compatible columns")


func _populate_target_tables(preferred: StringName) -> void:
	_target_table.clear()
	var local := _selected_local_column()
	if local != null:
		var seen: Dictionary[StringName, bool] = { }
		if _database != null:
			for table in _database.tables:
				if _source_table != null and table.name == _source_table.name:
					continue
				if not seen.has(table.name) and _has_compatible_target(table, local):
					_add_named_item(_target_table, table.name)
					seen[table.name] = true
	_select_name(_target_table, preferred)
	_set_empty_state(_target_table, "No compatible target tables")


func _populate_target_columns(preferred: StringName) -> void:
	_target_column.clear()
	var local := _selected_local_column()
	var table := _find_table(_selected_name(_target_table))
	if local != null and table != null:
		for column in table.columns:
			if _is_compatible_target(table, column.name, local):
				_add_named_item(_target_column, column.name)
	_select_name(_target_column, preferred)
	_set_empty_state(_target_column, "No matching unique columns")


func _on_local_column_selected() -> void:
	if _configuring:
		return
	_configuring = true
	_populate_target_tables(&"")
	_populate_target_columns(&"")
	_configuring = false
	_update_constraint_name()
	changed.emit()


func _on_target_table_selected() -> void:
	if _configuring:
		return
	_configuring = true
	_populate_target_columns(&"")
	_update_constraint_name()
	_configuring = false
	changed.emit()


func _on_target_column_selected() -> void:
	if _configuring:
		return
	_update_constraint_name()
	changed.emit()


func _selected_local_column() -> GDSQLColumnDefinition:
	if _source_table == null:
		return null
	return _source_table.get_column(_selected_name(_local_column))


func _find_table(table_name: StringName) -> GDSQLTableDefinition:
	if table_name == &"":
		return null
	if _source_table != null and _source_table.name == table_name:
		return null
	return _database.get_table(table_name) if _database != null else null


func _has_compatible_target(
		table: GDSQLTableDefinition,
		local: GDSQLColumnDefinition,
) -> bool:
	for column in table.columns:
		if _is_compatible_target(table, column.name, local):
			return true
	return false


func _is_compatible_target(
		table: GDSQLTableDefinition,
		column_name: StringName,
		local: GDSQLColumnDefinition,
) -> bool:
	if local == null:
		return false
	var column := table.get_column(column_name)
	return column != null \
			and column.data_type == local.data_type \
			and table.has_unique_key(column_name)


func _add_named_item(button: OptionButton, item_name: StringName) -> void:
	button.add_item(String(item_name))
	button.set_item_metadata(button.item_count - 1, item_name)


func _select_name(button: OptionButton, preferred: StringName) -> void:
	for index in button.item_count:
		if StringName(button.get_item_metadata(index)) == preferred:
			button.select(index)
			return
	if button.item_count > 0:
		button.select(0)


func _selected_name(button: OptionButton) -> StringName:
	if button.selected < 0 or button.selected >= button.item_count \
			or button.is_item_disabled(button.selected):
		return &""
	return StringName(button.get_item_metadata(button.selected))


func _set_empty_state(button: OptionButton, message: String) -> void:
	if button.item_count > 0:
		button.disabled = false
		return
	button.add_item(message)
	button.set_item_disabled(0, true)
	button.select(0)
	button.disabled = true


func _update_constraint_name() -> void:
	var parts: Array[String] = ["fk"]
	var names: Array[StringName] = [
		_source_table.name if _source_table != null else &"",
		_selected_name(_local_column),
		_selected_name(_target_table),
		_selected_name(_target_column),
	]
	for value in names:
		if value != &"":
			parts.append(String(value))
	_name.text = "_".join(parts)
	_name.tooltip_text = "Generated constraint name: %s" % _name.text

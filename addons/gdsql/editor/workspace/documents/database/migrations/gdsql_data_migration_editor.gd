@tool
class_name GDSQLEditorDataMigrationEditor
extends VBoxContainer
## Scene-backed authoring for one typed, single-table row-update migration.

signal changed
signal table_changed

var _database: GDSQLDatabaseDefinition
var _configuring := false

@onready var _table_select: OptionButton = %TableSelect
@onready var _values: GDSQLMutationValuesEditor = %Values
@onready var _where: GDSQLWhereExpressionEditor = %WhereExpression
@onready var _all_rows_confirmation: CheckButton = %AllRowsConfirmation
@onready var _resource_note: Label = %ResourceNote


func _ready() -> void:
	_table_select.item_selected.connect(_on_table_selected)
	_values.changed.connect(_emit_changed)
	_where.changed.connect(_on_where_changed)
	_all_rows_confirmation.toggled.connect(_emit_changed.unbind(1))


func configure(database: GDSQLDatabaseDefinition) -> void:
	_database = database
	_configuring = true
	_table_select.clear()
	if database != null:
		for table in database.tables:
			_table_select.add_item(String(table.name))
			_table_select.set_item_metadata(
				_table_select.item_count - 1,
				table.name,
			)
	_table_select.disabled = _table_select.item_count == 0
	if _table_select.item_count > 0:
		_table_select.select(0)
	_configure_selected_table()
	_configuring = false
	changed.emit()


func get_selected_table_name() -> StringName:
	if _table_select.selected < 0:
		return &""
	return StringName(_table_select.get_item_metadata(_table_select.selected))


func build_step() -> GDSQLOperationResult:
	var table := _selected_table()
	if table == null:
		return _error(
			&"GDSQL_EDITOR_DATA_MIGRATION_TABLE_REQUIRED",
			"Select a table to update.",
		)
	var values_result := _values.build_values()
	if not values_result.is_successful():
		return values_result
	var predicate_result := _where.build_expression()
	if not predicate_result.is_successful():
		return predicate_result
	var predicate := predicate_result.get_value() as GDSQLQueryExpression
	if predicate == null and not _all_rows_confirmation.button_pressed:
		return _error(
			&"GDSQL_EDITOR_DATA_MIGRATION_ALL_ROWS_CONFIRMATION_REQUIRED",
			"Enable WHERE or explicitly confirm updating every row.",
		)
	var assignments: Array[GDSQLColumnAssignment] = []
	var values := values_result.get_value() as Dictionary
	for column_name in values:
		assignments.append(
			GDSQLColumnAssignment.new(
				StringName(column_name),
				GDSQLLiteralExpression.new(values[column_name]),
			),
		)
	var step := GDSQLDataMigrationStep.new(table.name, assignments, predicate)
	if not step.is_valid():
		return _error(
			&"GDSQL_EDITOR_DATA_MIGRATION_STEP_INVALID",
			"The row update could not be represented as a durable migration.",
		)
	values_result.value = step
	return values_result


func _configure_selected_table() -> void:
	var table := _selected_table()
	var assignable_columns: Array[GDSQLColumnDefinition] = []
	var where_columns: Array[GDSQLColumnDefinition] = []
	var has_resource_columns := false
	if table != null:
		where_columns = table.columns
		for column in table.columns:
			if column.data_type == TYPE_OBJECT:
				has_resource_columns = true
				continue
			if column.name == table.primary_key or column.auto_increment \
					or column.generation != GDSQLColumnDefinition.Generation.NONE:
				continue
			assignable_columns.append(column)
	_values.configure(assignable_columns)
	_where.configure(where_columns)
	_all_rows_confirmation.button_pressed = false
	_resource_note.visible = has_resource_columns
	_update_safety_presentation()


func _selected_table() -> GDSQLTableDefinition:
	return (
			_database.get_table(get_selected_table_name())
			if _database != null and get_selected_table_name() != &""
			else null
	)


func _on_table_selected(_index: int) -> void:
	_configure_selected_table()
	if not _configuring:
		table_changed.emit()
		changed.emit()


func _on_where_changed() -> void:
	if _where.is_enabled():
		_all_rows_confirmation.button_pressed = false
	_update_safety_presentation()
	_emit_changed()


func _update_safety_presentation() -> void:
	_all_rows_confirmation.visible = not _where.is_enabled()


func _emit_changed() -> void:
	if not _configuring:
		changed.emit()


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result

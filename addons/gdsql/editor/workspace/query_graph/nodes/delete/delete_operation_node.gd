@tool
extends GDSQLQueryGraphNode
## Standalone DELETE operation presentation with explicit all-row safety.

signal source_changed(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
)
signal query_changed
signal query_activated

const ROW_SET_PORT_TYPE := 0
const ROW_SET_COLOR := Color("62b5e5")

@onready var _source: GDSQLQueryGraphSourceSelector = %Source
@onready var _where: GDSQLWhereExpressionEditor = %WhereExpression
@onready var _all_rows_confirmation: CheckButton = %AllRowsConfirmation
@onready var _summary: Label = %Summary
@onready var _query: GDSQLEditorActionButton = %Query


func _ready() -> void:
	super._ready()
	_source.changed.connect(_on_source_changed)
	_where.changed.connect(_on_where_changed)
	_all_rows_confirmation.toggled.connect(_on_confirmation_changed)
	_query.pressed.connect(query_activated.emit)
	set_slot(
		%OutputRow.get_index(),
		false,
		ROW_SET_PORT_TYPE,
		ROW_SET_COLOR,
		true,
		ROW_SET_PORT_TYPE,
		ROW_SET_COLOR,
	)


func configure_query_action(
		hub: GDSQLEditorActionHub,
		definition: GDSQLEditorActionDefinition,
) -> void:
	_query.configure(hub, definition)


func configure(
		inspections: Array[GDSQLDatabaseInspection],
		selected_registration: StringName,
		selected_table: StringName,
) -> void:
	_source.configure(inspections, selected_registration, selected_table)


func get_selected_registration() -> StringName:
	return _source.get_selected_registration()


func get_selected_database() -> StringName:
	return _source.get_selected_database()


func get_selected_table() -> StringName:
	return _source.get_selected_table()


func build_graph_node() -> GDSQLOperationResult:
	var predicate_result := _where.build_expression()
	if not predicate_result.is_successful():
		return predicate_result
	var predicate := predicate_result.get_value() as GDSQLQueryExpression
	if predicate == null and not _all_rows_confirmation.button_pressed:
		return _error(
			&"GDSQL_QUERY_GRAPH_DELETE_ALL_ROWS_CONFIRMATION_REQUIRED",
			"Enable WHERE or explicitly confirm deleting every row.",
		)
	var node := GDSQLQueryGraphDeleteNode.new(
		get_selected_database(),
		get_selected_table(),
	)
	node.predicate = predicate
	predicate_result.value = node
	return predicate_result


func _configure_where() -> void:
	var table := _source.get_selected_table_inspection()
	var columns: Array[GDSQLColumnDefinition] = []
	if table != null:
		columns = table.columns
	_where.configure(columns)
	_all_rows_confirmation.button_pressed = false
	_update_safety_presentation()


func _on_source_changed(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
) -> void:
	_configure_where()
	_update_summary()
	source_changed.emit(registration_name, database_name, table_name)


func _on_where_changed() -> void:
	if _where.is_enabled():
		_all_rows_confirmation.button_pressed = false
	_update_safety_presentation()
	_update_summary()


func _on_confirmation_changed(_enabled: bool) -> void:
	_update_summary()


func _update_safety_presentation() -> void:
	_all_rows_confirmation.visible = not _where.is_enabled()


func _update_summary() -> void:
	var suffix := _where.get_summary()
	if suffix.is_empty() and _all_rows_confirmation.button_pressed:
		suffix = " · ALL ROWS CONFIRMED"
	_summary.text = (
			"DELETE FROM %s%s" % [get_selected_table(), suffix]
			if get_selected_table() != &""
			else "No source selected."
	)
	query_changed.emit()


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result

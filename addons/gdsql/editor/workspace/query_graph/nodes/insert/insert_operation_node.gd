@tool
extends GDSQLQueryGraphNode
## Standalone single-row INSERT operation presentation.

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
@onready var _values: GDSQLMutationValuesEditor = %Values
@onready var _summary: Label = %Summary
@onready var _query: GDSQLEditorActionButton = %Query


func _ready() -> void:
	super._ready()
	_source.changed.connect(_on_source_changed)
	_values.changed.connect(_update_summary)
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
	var values_result := _values.build_values()
	if not values_result.is_successful():
		return values_result
	var node := GDSQLQueryGraphInsertNode.new(
		get_selected_database(),
		get_selected_table(),
	)
	var values := values_result.get_value() as Dictionary
	for column_name in values:
		node.columns.append(StringName(column_name))
		node.values.append(values[column_name])
	values_result.value = node
	return values_result


func _configure_values() -> void:
	var table := _source.get_selected_table_inspection()
	var columns: Array[GDSQLColumnDefinition] = []
	if table != null:
		columns = table.columns
	_values.configure(columns)


func _on_source_changed(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
) -> void:
	_configure_values()
	_update_summary()
	source_changed.emit(registration_name, database_name, table_name)


func _update_summary() -> void:
	var table_name := get_selected_table()
	_summary.text = (
			"INSERT INTO %s · %d value(s)" % [table_name, _values.get_included_count()]
			if table_name != &""
			else "No source selected."
	)
	query_changed.emit()

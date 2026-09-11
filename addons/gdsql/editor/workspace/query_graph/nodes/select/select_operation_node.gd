@tool
extends GDSQLQueryGraphNode
## SELECT operation presentation backed by lightweight schema inspections.

signal source_changed(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
)
signal query_changed
signal query_activated

const ROW_SET_PORT_TYPE := 0
const ROW_SET_COLOR := Color("62b5e5")
const COLUMN_SELECT_ALL := 10_000
const COLUMN_CLEAR := 10_001

var _inspections: Array[GDSQLDatabaseInspection] = []
var _column_count := 0

@onready var _database: OptionButton = %Database
@onready var _table: OptionButton = %Table
@onready var _columns: MenuButton = %Columns
@onready var _where_expression: GDSQLWhereExpressionEditor = %WhereExpression
@onready var _selection_summary: Label = %SelectionSummary
@onready var _query: GDSQLEditorActionButton = %Query


func _ready() -> void:
	super._ready()
	_database.item_selected.connect(_on_database_selected)
	_table.item_selected.connect(_on_table_selected)
	_columns.get_popup().id_pressed.connect(_on_column_toggled)
	_columns.get_popup().hide_on_checkable_item_selection = false
	_where_expression.changed.connect(_on_where_changed)
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
	var previous_registration := get_selected_registration()
	var previous_table := get_selected_table()
	var previous_columns := get_selected_columns()
	_inspections.clear()
	for inspection in inspections:
		if inspection != null and inspection.registration != null:
			_inspections.append(inspection)
	_inspections.sort_custom(_sort_inspections)
	_populate_databases(selected_registration)
	_populate_tables(selected_table)
	var same_source := (
			previous_registration == get_selected_registration()
			and previous_table == get_selected_table()
	)
	_populate_columns(previous_columns, same_source)
	_configure_where(same_source)
	_update_selection()


func get_selected_registration() -> StringName:
	if _database == null or _database.selected < 0:
		return &""
	return StringName(_database.get_item_metadata(_database.selected))


func get_selected_database() -> StringName:
	var inspection := _get_selected_inspection()
	return inspection.registration.database_name if inspection != null else &""


func get_selected_table() -> StringName:
	if _table == null or _table.selected < 0:
		return &""
	return StringName(_table.get_item_metadata(_table.selected))


func get_selected_columns() -> Array[StringName]:
	var selected: Array[StringName] = []
	if _columns == null:
		return selected
	var popup := _columns.get_popup()
	for index in range(popup.item_count):
		if popup.is_item_checkable(index) and popup.is_item_checked(index):
			selected.append(StringName(popup.get_item_metadata(index)))
	return selected


func are_all_columns_selected() -> bool:
	return _column_count > 0 and get_selected_columns().size() == _column_count


func build_predicate() -> GDSQLOperationResult:
	return _where_expression.build_expression()


func build_graph_node() -> GDSQLOperationResult:
	var predicate_result := build_predicate()
	if not predicate_result.is_successful():
		return predicate_result
	var node := GDSQLQueryGraphSelectNode.new(
		get_selected_database(),
		get_selected_table(),
	)
	node.projections = get_selected_columns()
	node.include_all_columns = are_all_columns_selected()
	node.predicate = predicate_result.get_value() as GDSQLQueryExpression
	predicate_result.value = node
	return predicate_result


func _populate_databases(selected_registration: StringName) -> void:
	_database.clear()
	for inspection in _inspections:
		var registration := inspection.registration
		_database.add_item(String(registration.database_name))
		var item_index := _database.item_count - 1
		_database.set_item_metadata(item_index, registration.name)
		_database.set_item_tooltip(
			item_index,
			"Location: %s\nRuntime storage: %s"
			% [
				registration.data_root,
				GDSQLStorageBackendIds.get_display_name(registration.storage_backend_id),
			],
		)
		if registration.name == selected_registration:
			_database.select(item_index)
	_database.disabled = _database.item_count == 0
	if _database.item_count > 0 and _database.selected < 0:
		_database.select(0)


func _populate_tables(selected_table: StringName = &"") -> void:
	_table.clear()
	var inspection := _get_selected_inspection()
	if inspection == null:
		_table.disabled = true
		return
	var tables := inspection.tables.duplicate()
	tables.sort_custom(_sort_tables)
	for table_inspection in tables:
		_table.add_item(String(table_inspection.name))
		var item_index := _table.item_count - 1
		_table.set_item_metadata(item_index, table_inspection.name)
		_table.set_item_tooltip(
			item_index,
			"%d columns · %d rows" % [table_inspection.column_count, table_inspection.row_count],
		)
		if table_inspection.name == selected_table:
			_table.select(item_index)
	_table.disabled = _table.item_count == 0
	if _table.item_count > 0 and _table.selected < 0:
		_table.select(0)


func _populate_columns(
		selected_columns: Array[StringName] = [],
		preserve_selection: bool = false,
) -> void:
	var popup := _columns.get_popup()
	popup.clear()
	_column_count = 0
	var table_inspection := _get_selected_table_inspection()
	if table_inspection == null:
		_columns.disabled = true
		_columns.text = "No columns"
		return
	_column_count = table_inspection.columns.size()
	if _column_count > 0:
		popup.add_item("Select all", COLUMN_SELECT_ALL)
		popup.add_item("Clear", COLUMN_CLEAR)
		popup.add_separator()
	for column in table_inspection.columns:
		popup.add_check_item(String(column.name), popup.item_count)
		var index := popup.item_count - 1
		popup.set_item_metadata(index, column.name)
		popup.set_item_checked(
			index,
			column.name in selected_columns if preserve_selection else true,
		)
	_columns.disabled = _column_count == 0
	_update_columns_label()


func _get_selected_inspection() -> GDSQLDatabaseInspection:
	var registration_name := get_selected_registration()
	for inspection in _inspections:
		if inspection.registration.name == registration_name:
			return inspection
	return null


func _get_selected_table_inspection() -> GDSQLTableInspection:
	var inspection := _get_selected_inspection()
	return inspection.get_table(get_selected_table()) if inspection != null else null


func _update_selection() -> void:
	var database_name := get_selected_database()
	var table_name := get_selected_table()
	if database_name == &"":
		_selection_summary.text = "No database is available."
	elif table_name == &"":
		_selection_summary.text = "No table is available in %s." % database_name
	else:
		var projection := _projection_summary()
		_selection_summary.text = "SELECT %s FROM %s.%s%s" % [
			projection,
			database_name,
			table_name,
			_where_summary(),
		]
	source_changed.emit(get_selected_registration(), database_name, table_name)
	query_changed.emit()


func _projection_summary() -> String:
	if are_all_columns_selected():
		return "*"
	var names: Array[String] = []
	for column_name in get_selected_columns():
		names.append(String(column_name))
	return ", ".join(names) if not names.is_empty() else "<no columns>"


func _where_summary() -> String:
	return _where_expression.get_summary()


func _update_columns_label() -> void:
	var total := _column_count
	var selected := get_selected_columns().size()
	if total == 0:
		_columns.text = "No columns"
	elif selected == total:
		_columns.text = "All columns"
	elif selected == 0:
		_columns.text = "No columns"
	else:
		_columns.text = "%d of %d columns" % [selected, total]


func _configure_where(preserve_state: bool = false) -> void:
	var table_inspection := _get_selected_table_inspection()
	var columns: Array[GDSQLColumnDefinition] = []
	if table_inspection != null:
		columns = table_inspection.columns
	_where_expression.configure(columns, preserve_state)


func _on_database_selected(_index: int) -> void:
	_populate_tables()
	_populate_columns()
	_configure_where()
	_update_selection()


func _on_table_selected(_index: int) -> void:
	_populate_columns()
	_configure_where()
	_update_selection()


func _on_column_toggled(id: int) -> void:
	var popup := _columns.get_popup()
	if id in [COLUMN_SELECT_ALL, COLUMN_CLEAR]:
		var checked := id == COLUMN_SELECT_ALL
		for item_index in range(popup.item_count):
			if popup.is_item_checkable(item_index):
				popup.set_item_checked(item_index, checked)
		_update_columns_label()
		_update_selection()
		return
	var index := popup.get_item_index(id)
	if index < 0 or not popup.is_item_checkable(index):
		return
	popup.set_item_checked(index, not popup.is_item_checked(index))
	_update_columns_label()
	_update_selection()


func _on_where_changed() -> void:
	_update_selection()


func _sort_inspections(left: GDSQLDatabaseInspection, right: GDSQLDatabaseInspection) -> bool:
	return String(left.registration.database_name) \
			< String(right.registration.database_name)


func _sort_tables(left: GDSQLTableInspection, right: GDSQLTableInspection) -> bool:
	return String(left.name) < String(right.name)

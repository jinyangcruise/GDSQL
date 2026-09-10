@tool
class_name GDSQLWorkspace
extends Control
## Hosts independent scene-backed editor documents behind one tab bar.

signal database_create_submitted(
		database_name: StringName,
		data_root: String,
		storage_backend_id: StringName,
		database_role: StringName,
)
signal database_save_submitted(
		registration_name: StringName,
		database_name: StringName,
		new_tables: Array[GDSQLTableDefinition],
		table_changes: Array[GDSQLEditorTableChange],
)
signal database_refresh_submitted(registration_name: StringName)
signal table_rows_requested(
		registration_name: StringName,
		table_name: StringName,
		query: GDSQLSelectQuerySpec,
		count_query: GDSQLSelectQuerySpec,
)
signal table_row_insert_requested(
		registration_name: StringName,
		table_name: StringName,
		values: Dictionary,
)
signal table_rows_update_requested(
		registration_name: StringName,
		table_name: StringName,
		updates: Array[Dictionary],
)
signal table_rows_delete_requested(
		registration_name: StringName,
		table_name: StringName,
		primary_keys: Array[Variant],
)
signal query_graph_submitted(
		document_key: StringName,
		source_node_name: StringName,
		registration_name: StringName,
		query: GDSQLQuerySpec,
)
signal query_result_row_insert_requested(
		document_key: StringName,
		source_node_name: StringName,
		registration_name: StringName,
		table_name: StringName,
		values: Dictionary,
)
signal query_result_row_update_requested(
		document_key: StringName,
		source_node_name: StringName,
		registration_name: StringName,
		table_name: StringName,
		original_primary_key: Variant,
		values: Dictionary,
)
signal query_result_row_delete_requested(
		document_key: StringName,
		source_node_name: StringName,
		registration_name: StringName,
		table_name: StringName,
		primary_key: Variant,
)

const WELCOME_SCENE := preload(
	"res://addons/gdsql/editor/workspace/documents/welcome/gdsql_welcome_document.tscn"
)
const CREATE_DATABASE_SCENE := preload(
	"res://addons/gdsql/editor/workspace/documents/create_database/gdsql_database_create_document.tscn"
)
const DATABASE_SCENE := preload(
	"res://addons/gdsql/editor/workspace/documents/database/gdsql_database_document.tscn"
)
const TABLE_DATA_SCENE := preload(
	"res://addons/gdsql/editor/workspace/table_editor/gdsql_table_data_document.tscn"
)
const MODEL_ASSISTANT_SCENE := preload(
	"res://addons/gdsql/editor/workspace/documents/model/gdsql_model_assistant_document.tscn"
)
const SAVE_SLOTS_SCENE := preload(
	"res://addons/gdsql/editor/workspace/documents/save_slots/gdsql_save_slots_document.tscn"
)
const QUERY_GRAPH_SCENE := preload(
	"res://addons/gdsql/editor/workspace/query_graph/graph_editor.tscn"
)
const WELCOME_KEY := &"welcome"
const CREATE_DATABASE_KEY := &"database:create"
const SAVE_SLOTS_KEY := &"save_slots"
const MENU_CREATE_DATABASE := 1
const MENU_CREATE_TABLE := 2
const MENU_REFRESH := 3
const MENU_SAVE_SLOTS := 4

var _action_hub: GDSQLEditorActionHub
var _workbench: GDSQLWorkbench
var _document_keys: Array[StringName] = []
var _documents: Dictionary[StringName, Control] = { }
var _active_registration: StringName
var _database_inspections: Array[GDSQLDatabaseInspection] = []
var _pending_close_key: StringName

@onready var _file_menu: PopupMenu = $Layout/MenuPanel/MenuBar/File
@onready var _database_menu: PopupMenu = $Layout/MenuPanel/MenuBar/Database
@onready var _tabs: TabBar = $Layout/DocumentTabs
@onready var _document_host: Control = $Layout/DocumentHost
@onready var _discard_document_confirmation: ConfirmationDialog = %DiscardDocumentConfirmation


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tabs.clear_tabs()
	_tabs.tab_changed.connect(_on_tab_changed)
	_tabs.tab_close_pressed.connect(_on_tab_close_pressed)
	_file_menu.id_pressed.connect(_on_menu_pressed)
	_database_menu.id_pressed.connect(_on_menu_pressed)
	_discard_document_confirmation.confirmed.connect(_confirm_close_document)
	_open_welcome_document()


func configure(action_hub: GDSQLEditorActionHub, workbench: GDSQLWorkbench) -> void:
	_action_hub = action_hub
	_workbench = workbench
	var welcome := _documents.get(WELCOME_KEY) as Control
	if welcome != null:
		welcome.call("configure", _action_hub, _workbench)
	var save_slots := _documents.get(SAVE_SLOTS_KEY) as Control
	if save_slots != null:
		save_slots.call("configure", _action_hub, _workbench)


func refresh_welcome() -> void:
	var welcome := _documents.get(WELCOME_KEY) as Control
	if welcome != null:
		welcome.call("refresh_status")


func refresh_save_slots() -> void:
	var document := _documents.get(SAVE_SLOTS_KEY) as Control
	if document != null:
		document.call("refresh_slots")


func show_welcome() -> void:
	_activate_document(WELCOME_KEY)


func show_save_slots() -> void:
	var document := _documents.get(SAVE_SLOTS_KEY) as Control
	if document == null:
		document = SAVE_SLOTS_SCENE.instantiate() as Control
		_add_document(SAVE_SLOTS_KEY, "Save Slots", document)
		document.call("configure", _action_hub, _workbench)
	document.call("refresh_slots")
	_activate_document(SAVE_SLOTS_KEY)


func show_database(
		inspection: GDSQLDatabaseInspection,
		session: GDSQLWorkbenchSession,
) -> void:
	if inspection == null or session == null:
		return
	var key := _database_key(inspection.registration.name)
	var document := _documents.get(key) as Control
	if document == null:
		document = DATABASE_SCENE.instantiate() as Control
		document.connect("save_requested", _on_database_save_requested)
		document.connect("delete_requested", _on_database_delete_requested)
		document.connect("refresh_requested", _on_database_refresh_requested)
		_add_document(
			key,
			String(inspection.registration.database_name),
			document,
		)
		document.call("configure_actions", _action_hub, key)
	document.call("configure", inspection, session)
	_activate_document(key)


func show_table(
		inspections: Array[GDSQLDatabaseInspection],
		inspection: GDSQLDatabaseInspection,
		session: GDSQLWorkbenchSession,
) -> void:
	if inspection == null or session == null or session.selected_table == null:
		return
	_database_inspections = inspections.duplicate()
	var key := _table_key(
		inspection.registration.name,
		session.selected_table.name,
	)
	var document := _documents.get(key) as Control
	if document == null:
		document = TABLE_DATA_SCENE.instantiate() as Control
		document.connect(
			"rows_requested",
			_on_table_rows_requested,
		)
		document.connect(
			"row_insert_requested",
			_on_table_row_insert_requested,
		)
		document.connect(
			"rows_update_requested",
			_on_table_rows_update_requested,
		)
		document.connect(
			"rows_delete_requested",
			_on_table_rows_delete_requested,
		)
		document.connect(
			"model_assistant_requested",
			_on_model_assistant_requested,
		)
		_add_document(
			key,
			"%s · %s" % [
				inspection.registration.database_name,
				session.selected_table.name,
			],
			document,
		)
	var table_inspection := inspection.get_table(session.selected_table.name)
	document.call(
		"configure",
		inspection.registration.name,
		session.selected_table,
		table_inspection.row_count if table_inspection != null else 0,
	)
	_activate_document(key)
	document.call("request_rows")


func show_model_assistant(
		registration_name: StringName,
		table: GDSQLTableDefinition,
) -> void:
	if table == null:
		return
	var key := _model_key(registration_name, table.name)
	var document := _documents.get(key) as Control
	if document == null:
		document = MODEL_ASSISTANT_SCENE.instantiate() as Control
		document.connect(
			"close_requested",
			_close_document_by_key.bind(key),
		)
		document.connect("scripts_generated", _on_model_scripts_generated)
		_add_document(key, "%s model" % table.name, document)
	document.call(
		"configure",
		registration_name,
		table,
		_role_for_registration(registration_name),
	)
	_activate_document(key)


func refresh_database(
		inspection: GDSQLDatabaseInspection,
		session: GDSQLWorkbenchSession,
) -> void:
	if inspection == null or session == null:
		return
	_upsert_inspection(inspection)
	var key := _database_key(inspection.registration.name)
	var document := _documents.get(key) as Control
	if document != null:
		document.call("configure", inspection, session)
		var index := _document_keys.find(key)
		if index >= 0:
			_tabs.set_tab_title(
				index,
				String(inspection.registration.database_name),
			)
	_refresh_table_documents(inspection, session)


func open_create_database_page(default_root: String = "res://data") -> void:
	var document := _get_create_database_document()
	document.call("reset", default_root)
	_activate_document(CREATE_DATABASE_KEY)


func open_create_save_slot_page() -> void:
	var document := _get_create_database_document()
	document.call("reset_save_slot")
	_activate_document(CREATE_DATABASE_KEY)


func _get_create_database_document() -> Control:
	var document := _documents.get(CREATE_DATABASE_KEY) as Control
	if document == null:
		document = CREATE_DATABASE_SCENE.instantiate() as Control
		document.connect("create_requested", _on_database_create_requested)
		document.connect(
			"cancel_requested",
			_close_document_by_key.bind(CREATE_DATABASE_KEY),
		)
		_add_document(
			CREATE_DATABASE_KEY,
			"New Database",
			document,
		)
	return document


func close_database_create() -> void:
	_close_document_by_key(CREATE_DATABASE_KEY)


func accept_database_saved(
		registration_name: StringName,
		inspection: GDSQLDatabaseInspection,
		session: GDSQLWorkbenchSession,
) -> void:
	var document := _documents.get(
		_database_key(registration_name),
	) as Control
	if document != null:
		document.call("accept_saved_state", inspection, session)
	refresh_database(inspection, session)


func begin_table_draft() -> void:
	var document := _active_database_document()
	if document != null:
		document.call("add_table_draft")


func present_table_rows(
		registration_name: StringName,
		table_name: StringName,
		result: GDSQLQueryResult,
		total_rows: int = -1,
) -> void:
	var document := _documents.get(
		_table_key(registration_name, table_name),
	) as Control
	if document != null and document.has_method("present_rows"):
		document.call("present_rows", result, total_rows)


func request_table_rows(
		registration_name: StringName,
		table_name: StringName,
) -> void:
	var document := _documents.get(
		_table_key(registration_name, table_name),
	) as Control
	if document != null and document.has_method("request_rows"):
		document.call("request_rows")


func present_query_graph_result(
		document_key: StringName,
		source_node_name: StringName,
		registration_name: StringName,
		table: GDSQLTableDefinition,
		result: GDSQLQueryResult,
) -> void:
	var document := _documents.get(document_key) as Control
	if document == null:
		return
	document.call(
		"present_query_result",
		source_node_name,
		registration_name,
		table,
		result,
	)
	_activate_document(document_key)


func request_query_graph(
		document_key: StringName,
		source_node_name: StringName = &"",
) -> GDSQLOperationResult:
	var document := _documents.get(document_key) as Control
	if document == null or not document.has_method("request_query"):
		var result := GDSQLOperationResult.new()
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_EDITOR_QUERY_GRAPH_DOCUMENT_NOT_FOUND",
				"The query graph document is no longer open.",
			),
		)
		return result
	return document.call("request_query", source_node_name) as GDSQLOperationResult


func get_active_registration() -> StringName:
	return _active_registration


func close_registration(registration_name: StringName) -> void:
	var table_prefix := "table:%s:" % registration_name
	var model_prefix := "model:%s:" % registration_name
	var keys_to_close: Array[StringName] = []
	for key in _document_keys:
		if String(key).begins_with(table_prefix) \
				or String(key).begins_with(model_prefix):
			keys_to_close.append(key)
	for key in keys_to_close:
		_close_document_by_key(key)
	_close_document_by_key(_database_key(registration_name))
	if _active_registration == registration_name:
		show_welcome()


func close_table(
		registration_name: StringName,
		table_name: StringName,
) -> void:
	_close_document_by_key(_table_key(registration_name, table_name))
	_close_document_by_key(_model_key(registration_name, table_name))


func _open_welcome_document() -> void:
	var welcome := WELCOME_SCENE.instantiate() as Control
	_add_document(WELCOME_KEY, "Welcome", welcome)
	if _action_hub != null:
		welcome.call("configure", _action_hub, _workbench)
	_activate_document(WELCOME_KEY)


func _add_document(
		key: StringName,
		title: String,
		document: Control,
) -> void:
	document.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	document.hide()
	_document_host.add_child(document)
	_document_keys.append(key)
	_documents[key] = document
	_tabs.add_tab(title)


func _activate_document(key: StringName) -> void:
	var index := _document_keys.find(key)
	if index < 0:
		return
	_tabs.current_tab = index
	_show_document(index)


func _show_document(index: int) -> void:
	if index < 0 or index >= _document_keys.size():
		return
	for document_value in _documents.values():
		var document := document_value as Control
		document.hide()
	var key := _document_keys[index]
	var document := _documents[key]
	document.show()
	_active_registration = &""
	if String(key).begins_with("database:") \
			and key != CREATE_DATABASE_KEY:
		_active_registration = StringName(
			String(key).trim_prefix("database:"),
		)
	elif String(key).begins_with("table:") or String(key).begins_with("model:"):
		var parts := String(key).split(":", false, 2)
		if parts.size() >= 2:
			_active_registration = StringName(parts[1])
	if _action_hub != null:
		var context_id := GDSQLEditorActionHub.GLOBAL_CONTEXT
		if document.has_method("get_action_context_id"):
			context_id = StringName(document.call("get_action_context_id"))
		elif String(key).begins_with("database:") and key != CREATE_DATABASE_KEY:
			context_id = key
		var activated := _action_hub.set_active_context(context_id)
		if not activated.is_successful() \
				and context_id != GDSQLEditorActionHub.GLOBAL_CONTEXT:
			_action_hub.set_active_context(GDSQLEditorActionHub.GLOBAL_CONTEXT)
	_set_create_table_enabled(_active_registration != &"")


func _close_document_by_key(key: StringName) -> void:
	var index := _document_keys.find(key)
	if index <= 0:
		return
	var document := _documents.get(key) as Control
	if document != null and document.has_method("release_actions"):
		document.call("release_actions")
	_document_keys.remove_at(index)
	_documents.erase(key)
	_tabs.remove_tab(index)
	if is_instance_valid(document):
		document.queue_free()
	var next_index := clampi(index - 1, 0, _document_keys.size() - 1)
	_tabs.current_tab = next_index
	_show_document(next_index)


func _active_database_document() -> Control:
	if _active_registration == &"":
		return null
	return _documents.get(_database_key(_active_registration)) as Control


func _database_key(registration_name: StringName) -> StringName:
	return StringName("database:%s" % registration_name)


func _table_key(
		registration_name: StringName,
		table_name: StringName,
) -> StringName:
	return StringName("table:%s:%s" % [registration_name, table_name])


func _model_key(
		registration_name: StringName,
		table_name: StringName,
) -> StringName:
	return StringName("model:%s:%s" % [registration_name, table_name])


func _role_for_registration(registration_name: StringName) -> StringName:
	if _workbench != null:
		for binding in _workbench.snapshot.role_bindings:
			if binding.registration_name == registration_name:
				return binding.role
	return GDSQLDatabaseRegistry.CONTENT_ROLE


func _refresh_table_documents(
		inspection: GDSQLDatabaseInspection,
		session: GDSQLWorkbenchSession,
) -> void:
	if session.catalog_snapshot == null:
		return
	var database := session.catalog_snapshot.get_database(
		inspection.registration.database_name,
	)
	if database == null:
		return
	var prefix := "table:%s:" % inspection.registration.name
	var missing_keys: Array[StringName] = []
	for key in _document_keys:
		var key_text := String(key)
		if not key_text.begins_with(prefix):
			continue
		var table_name := StringName(key_text.trim_prefix(prefix))
		var table := database.get_table(table_name)
		if table == null:
			missing_keys.append(key)
			continue
		var document := _documents.get(key) as Control
		if document != null:
			var table_inspection := inspection.get_table(table.name)
			document.call(
				"configure",
				inspection.registration.name,
				table,
				table_inspection.row_count if table_inspection != null else 0,
			)
	var model_prefix := "model:%s:" % inspection.registration.name
	for key in _document_keys:
		var key_text := String(key)
		if not key_text.begins_with(model_prefix):
			continue
		var table_name := StringName(key_text.trim_prefix(model_prefix))
		var table := database.get_table(table_name)
		if table == null:
			missing_keys.append(key)
			continue
		var document := _documents.get(key) as Control
		if document != null:
			document.call("refresh_table", table)
	for key in missing_keys:
		_close_document_by_key(key)


func _upsert_inspection(inspection: GDSQLDatabaseInspection) -> void:
	for index in range(_database_inspections.size()):
		var current := _database_inspections[index]
		if current != null and current.registration != null \
				and current.registration.name == inspection.registration.name:
			_database_inspections[index] = inspection
			return
	_database_inspections.append(inspection)


func _set_create_table_enabled(enabled: bool) -> void:
	var item_index := _database_menu.get_item_index(MENU_CREATE_TABLE)
	if item_index >= 0:
		_database_menu.set_item_disabled(item_index, not enabled)


func _on_database_create_requested(
		database_name: StringName,
		data_root: String,
		storage_backend_id: StringName,
		database_role: StringName,
) -> void:
	database_create_submitted.emit(
		database_name,
		data_root,
		storage_backend_id,
		database_role,
	)


func _on_database_save_requested(
		registration_name: StringName,
		database_name: StringName,
		new_tables: Array[GDSQLTableDefinition],
		table_changes: Array[GDSQLEditorTableChange],
) -> void:
	database_save_submitted.emit(
		registration_name,
		database_name,
		new_tables,
		table_changes,
	)


func _on_database_delete_requested(registration_name: StringName) -> void:
	if _action_hub != null:
		_action_hub.invoke(
			GDSQLEditorActionIds.REMOVE_REGISTRATION,
			[registration_name],
		)


func _on_database_refresh_requested(registration_name: StringName) -> void:
	database_refresh_submitted.emit(registration_name)


func _on_table_rows_requested(
		registration_name: StringName,
		table_name: StringName,
		query: GDSQLSelectQuerySpec,
		count_query: GDSQLSelectQuerySpec,
) -> void:
	table_rows_requested.emit(registration_name, table_name, query, count_query)


func _on_table_row_insert_requested(
		registration_name: StringName,
		table_name: StringName,
		values: Dictionary,
) -> void:
	table_row_insert_requested.emit(registration_name, table_name, values)


func _on_table_rows_update_requested(
		registration_name: StringName,
		table_name: StringName,
		updates: Array[Dictionary],
) -> void:
	table_rows_update_requested.emit(
		registration_name,
		table_name,
		updates,
	)


func _on_table_rows_delete_requested(
		registration_name: StringName,
		table_name: StringName,
		primary_keys: Array[Variant],
) -> void:
	table_rows_delete_requested.emit(
		registration_name,
		table_name,
		primary_keys,
	)


func _on_model_assistant_requested(
		registration_name: StringName,
		table: GDSQLTableDefinition,
) -> void:
	show_model_assistant(registration_name, table)


func _on_model_scripts_generated(_generated_path: String, _user_path: String) -> void:
	refresh_welcome()


func _on_query_graph_submitted(
		source_node_name: StringName,
		registration_name: StringName,
		query: GDSQLQuerySpec,
		document_key: StringName,
) -> void:
	query_graph_submitted.emit(
		document_key,
		source_node_name,
		registration_name,
		query,
	)


func _on_query_result_row_insert_requested(
		source_node_name: StringName,
		registration_name: StringName,
		table_name: StringName,
		values: Dictionary,
		document_key: StringName,
) -> void:
	query_result_row_insert_requested.emit(
		document_key,
		source_node_name,
		registration_name,
		table_name,
		values,
	)


func _on_query_result_row_update_requested(
		source_node_name: StringName,
		registration_name: StringName,
		table_name: StringName,
		original_primary_key: Variant,
		values: Dictionary,
		document_key: StringName,
) -> void:
	query_result_row_update_requested.emit(
		document_key,
		source_node_name,
		registration_name,
		table_name,
		original_primary_key,
		values,
	)


func _on_query_result_row_delete_requested(
		source_node_name: StringName,
		registration_name: StringName,
		table_name: StringName,
		primary_key: Variant,
		document_key: StringName,
) -> void:
	query_result_row_delete_requested.emit(
		document_key,
		source_node_name,
		registration_name,
		table_name,
		primary_key,
	)


func _on_menu_pressed(id: int) -> void:
	if _action_hub == null:
		return
	match id:
		MENU_CREATE_DATABASE:
			_action_hub.invoke(GDSQLEditorActionIds.CREATE_DATABASE)
		MENU_CREATE_TABLE:
			_action_hub.invoke(GDSQLEditorActionIds.CREATE_TABLE)
		MENU_REFRESH:
			_action_hub.invoke(GDSQLEditorActionIds.REFRESH_DATABASES)
		MENU_SAVE_SLOTS:
			_action_hub.invoke(GDSQLEditorActionIds.SHOW_SAVE_SLOTS)


func _on_tab_changed(index: int) -> void:
	_show_document(index)


func _on_tab_close_pressed(index: int) -> void:
	if index <= 0 or index >= _document_keys.size():
		return
	var key := _document_keys[index]
	var document := _documents.get(key) as Control
	if document != null \
			and document.has_method("has_unsaved_changes") \
			and bool(document.call("has_unsaved_changes")):
		_pending_close_key = key
		_discard_document_confirmation.dialog_text = (
				"This query result has unsaved row changes. Close it and discard the draft?"
		)
		_discard_document_confirmation.popup_centered(Vector2i(480, 170))
		return
	_close_document_by_key(key)


func _confirm_close_document() -> void:
	if _pending_close_key == &"":
		return
	var key := _pending_close_key
	_pending_close_key = &""
	_close_document_by_key(key)

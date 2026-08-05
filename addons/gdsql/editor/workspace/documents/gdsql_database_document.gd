@tool
extends MarginContainer
## One editable database document containing table and column folds.

signal save_requested(
		registration_name: StringName,
		database_name: StringName,
		new_tables: Array[GDSQLTableDefinition],
		table_changes: Array[GDSQLEditorTableChange],
)
signal delete_requested(registration_name: StringName)
signal refresh_requested(registration_name: StringName)

const TABLE_FOLD_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_table_fold.tscn"
)
const TABLE_DRAFT_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_table_draft_fold.tscn"
)

var _inspection: GDSQLDatabaseInspection
var _session: GDSQLWorkbenchSession
var _original_database_name: StringName
var _renaming := false
var _action_hub: GDSQLEditorActionHub
var _action_context: GDSQLContextActionHub
var _action_context_id: StringName
var _validation_state: Label

@onready var rename_button: Button = %Rename
@onready var delete_button: Button = %Delete
@onready var _database_name: LineEdit = %DatabaseName
@onready var _storage: Label = %Storage
@onready var _location: Label = %Location
@onready var _save: GDSQLEditorActionButton = %Save
@onready var _refresh: GDSQLEditorActionButton = %Refresh
@onready var _dirty_state: Label = %DirtyState
@onready var _existing_tables: VBoxContainer = %ExistingTables
@onready var _draft_tables: VBoxContainer = %DraftTables
@onready var _add_table: GDSQLEditorActionButton = %AddTable
@onready var _save_confirmation: ConfirmationDialog = $SaveConfirmation
@onready var _delete_confirmation: ConfirmationDialog = $DeleteConfirmation


func _ready() -> void:
	_validation_state = get_node_or_null("%ValidationState") as Label
	if _validation_state == null:
		_validation_state = Label.new()
		_validation_state.name = "ValidationState"
		_validation_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_validation_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		$Layout/Footer.add_child(_validation_state)
		$Layout/Footer.move_child(_validation_state, 0)
	rename_button.pressed.connect(_begin_rename)
	delete_button.pressed.connect(_delete_confirmation.popup_centered.bind(Vector2i(460, 170)))
	_database_name.text_changed.connect(_on_changed.unbind(1))
	_save_confirmation.confirmed.connect(_emit_save)
	$RefreshConfirmation.confirmed.connect(_emit_refresh)
	_delete_confirmation.confirmed.connect(_emit_delete)
	_update_dirty_state()


func configure_actions(
		action_hub: GDSQLEditorActionHub,
		context_id: StringName,
) -> void:
	if _action_hub == action_hub and _action_context_id == context_id:
		return
	release_actions()
	_action_hub = action_hub
	_action_context_id = context_id
	_action_context = GDSQLContextActionHub.new(context_id)
	_action_context.add_action(
		GDSQLEditorActionDefinition.new(
			GDSQLEditorActionIds.SAVE_DATABASE_CHANGES,
			"Save Changes",
			"Review and apply the pending database changes.",
			&"Save",
			&"document",
			0,
		),
		_request_save,
	)
	_action_context.add_action(
		GDSQLEditorActionDefinition.new(
			GDSQLEditorActionIds.REFRESH_DATABASE_CHANGES,
			"Refresh",
			"Reload the database catalog and discard local drafts.",
			&"Reload",
			&"document",
			1,
		),
		_request_refresh,
	)
	var registered := _action_hub.register_context(_action_context)
	if not registered.is_successful():
		return
	_save.configure(
		_action_hub,
		_action_context.get_action(GDSQLEditorActionIds.SAVE_DATABASE_CHANGES),
	)
	_refresh.configure(
		_action_hub,
		_action_context.get_action(GDSQLEditorActionIds.REFRESH_DATABASE_CHANGES),
	)
	_add_table.configure_action(_action_hub, GDSQLEditorActionIds.CREATE_TABLE)
	_update_dirty_state()


func release_actions() -> void:
	if _action_hub != null and _action_context_id != &"":
		_action_hub.unregister_context(_action_context_id)
	_action_context = null
	_action_context_id = &""
	_action_hub = null


func configure(inspection: GDSQLDatabaseInspection, session: GDSQLWorkbenchSession) -> void:
	_inspection = inspection
	_session = session
	_original_database_name = inspection.registration.database_name
	if not _renaming:
		_database_name.text = String(_original_database_name)
	_location.text = inspection.registration.data_root
	_storage.text = GDSQLStorageBackendIds.get_display_name(
		inspection.registration.storage_backend_id,
	)
	_delete_confirmation.dialog_text = (
			(
					"Remove database '%s' from GDSQL?\n\n"
					+ "Files at '%s' will remain unchanged. Creating the same database "
					+ "later will load these files again."
			)
			% [
				inspection.registration.database_name,
				inspection.registration.data_root.path_join(
					String(inspection.registration.database_name),
				),
			]
	)
	_render_existing_tables()
	_update_dirty_state()


func accept_saved_state(
		inspection: GDSQLDatabaseInspection,
		session: GDSQLWorkbenchSession,
) -> void:
	for draft in _draft_tables.get_children():
		_draft_tables.remove_child(draft)
		draft.queue_free()
	_renaming = false
	_database_name.editable = false
	configure(inspection, session)


func add_table_draft() -> void:
	var draft := TABLE_DRAFT_SCENE.instantiate() as Control
	_draft_tables.add_child(draft)
	draft.connect("changed", _update_dirty_state)
	draft.connect("remove_requested", _remove_table_draft)
	draft.call("configure_new")
	_update_dirty_state()


func focus_table(table_name: StringName) -> void:
	for fold in _existing_tables.get_children():
		if fold.get("table_name") == table_name:
			fold.call("focus")
			fold.grab_focus()
			return


func _render_existing_tables() -> void:
	for child in _existing_tables.get_children():
		_existing_tables.remove_child(child)
		child.queue_free()
	if _session == null or _session.catalog_snapshot == null:
		return
	var database := _session.catalog_snapshot.get_database(_inspection.registration.database_name)
	if database == null:
		return
	for table_inspection in _inspection.tables:
		var table := database.get_table(table_inspection.name)
		if table == null:
			continue
		var fold := TABLE_FOLD_SCENE.instantiate()
		_existing_tables.add_child(fold)
		fold.call("configure", table, table_inspection)
		fold.connect("changed", _update_dirty_state)


func _begin_rename() -> void:
	_renaming = true
	_database_name.editable = true
	_database_name.grab_focus()
	_database_name.select_all()
	_update_dirty_state()


func _remove_table_draft(draft: Control) -> void:
	_draft_tables.remove_child(draft)
	draft.queue_free()
	_update_dirty_state()


func _request_save() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _is_valid() or not _is_dirty():
		return result
	var changes: Array[String] = []
	var requested_name := _requested_database_name()
	if requested_name != _original_database_name:
		changes.append("Rename database '%s' to '%s'." % [_original_database_name, requested_name])
	for draft in _draft_tables.get_children():
		var definition := draft.call("build_definition") as GDSQLTableDefinition
		changes.append("Create table '%s'." % definition.name)
	for fold in _existing_tables.get_children():
		var table_change := fold.call("build_change") as GDSQLEditorTableChange
		for alteration in table_change.alterations:
			changes.append(
				"%s: %s" % [table_change.table_name, alteration.describe()],
			)
	_save_confirmation.dialog_text = "\n".join(changes)
	_save_confirmation.popup_centered(Vector2i(520, 220))
	result.value = self
	return result


func _request_refresh() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _inspection == null:
		return result
	if _is_dirty():
		$RefreshConfirmation.popup_centered(Vector2i(500, 190))
	else:
		_emit_refresh()
	result.value = self
	return result


func _emit_save() -> void:
	var definitions: Array[GDSQLTableDefinition] = []
	for draft in _draft_tables.get_children():
		definitions.append(draft.call("build_definition") as GDSQLTableDefinition)
	var table_changes: Array[GDSQLEditorTableChange] = []
	for fold in _existing_tables.get_children():
		var table_change := fold.call("build_change") as GDSQLEditorTableChange
		if not table_change.alterations.is_empty():
			table_changes.append(table_change)
	save_requested.emit(
		_inspection.registration.name,
		_requested_database_name(),
		definitions,
		table_changes,
	)


func _emit_delete() -> void:
	delete_requested.emit(_inspection.registration.name)


func _emit_refresh() -> void:
	refresh_requested.emit(_inspection.registration.name)


func _on_changed() -> void:
	_update_dirty_state()


func _update_dirty_state() -> void:
	var dirty := _is_dirty()
	var validation_errors := _get_validation_errors()
	_dirty_state.text = "Unsaved changes" if dirty else "Saved"
	_validation_state.visible = dirty and not validation_errors.is_empty()
	_validation_state.text = (
			validation_errors[0]
			if not validation_errors.is_empty()
			else ""
	)
	if _action_context != null:
		_action_context.set_action_enabled(
			GDSQLEditorActionIds.SAVE_DATABASE_CHANGES,
			dirty and validation_errors.is_empty(),
		)


func _is_dirty() -> bool:
	if _requested_database_name() != _original_database_name \
			or _draft_tables.get_child_count() > 0:
		return true
	for fold in _existing_tables.get_children():
		if bool(fold.call("has_changes")):
			return true
	return false


func _is_valid() -> bool:
	return _get_validation_errors().is_empty()


func _get_validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var database_name := _requested_database_name()
	if database_name == &"":
		errors.append("A database name is required.")
	elif not String(database_name).is_valid_identifier():
		errors.append("Database '%s' must be a valid identifier." % database_name)
	for draft in _draft_tables.get_children():
		var draft_errors: Array[String] = draft.call("get_validation_errors")
		errors.append_array(draft_errors)
	for fold in _existing_tables.get_children():
		if not bool(fold.call("is_valid_draft")):
			errors.append(
				"Table '%s' contains an invalid column or index change." \
						% fold.get("table_name"),
			)
	return errors


func _requested_database_name() -> StringName:
	return StringName(_database_name.text.strip_edges())

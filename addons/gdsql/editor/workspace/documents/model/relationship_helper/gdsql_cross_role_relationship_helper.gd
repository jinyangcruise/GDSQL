@tool
extends PanelContainer
## Builds one explicit save-to-content relationship entry from model bindings.

signal reference_registered(registration_name: StringName, table_name: StringName)

const SETTINGS_PATH := "res://.gdsql/settings.cfg"
const SETTINGS_BINDING_PREFIX := "model_binding:"
const SETTINGS_CLASS_KEY := "class_name"
const SETTINGS_ROLE_KEY := "role"
const CONTENT_REFERENCE_ROW_SCENE := preload(
	"res://addons/gdsql/editor/workspace/documents/model/relationship_helper/gdsql_content_reference_row.tscn"
)


class Target extends RefCounted:
	var registration_name: StringName
	var database_name: StringName
	var table: GDSQLTableInspection
	var model_class: StringName


	func _init(
			target_registration: StringName,
			target_database: StringName,
			target_table: GDSQLTableInspection,
			target_model_class: StringName,
	) -> void:
		registration_name = target_registration
		database_name = target_database
		table = target_table
		model_class = target_model_class


var _table: GDSQLTableDefinition
var _registration_name: StringName
var _inspections: Array[GDSQLDatabaseInspection] = []
var _role_bindings: Array[GDSQLDatabaseRoleBinding] = []
var _targets: Array[Target] = []
var _last_name_suggestion := ""
var _settings := ConfigFile.new()
var _reference_store := GDSQLEditorContentReferenceStore.new()

@onready var _local_column: OptionButton = %LocalReferenceColumn
@onready var _content_target: OptionButton = %ContentTarget
@onready var _relationship_name: LineEdit = %RelationshipName
@onready var _snippet: CodeEdit = %RelationshipSnippet


func _ready() -> void:
	if _is_scene_preview():
		return
	_local_column.item_selected.connect(_on_local_column_selected)
	_content_target.item_selected.connect(_on_target_selected)
	_relationship_name.text_changed.connect(_refresh_snippet)
	%CopyRelationship.pressed.connect(_copy_relationship)


func configure(
		registration_name: StringName,
		table: GDSQLTableDefinition,
		inspections: Array[GDSQLDatabaseInspection],
		role_bindings: Array[GDSQLDatabaseRoleBinding],
) -> void:
	_registration_name = registration_name
	_table = table
	_inspections = inspections.duplicate()
	_role_bindings = role_bindings.duplicate()
	_last_name_suggestion = ""
	_settings = ConfigFile.new()
	_settings.load(SETTINGS_PATH)
	_local_column.clear()
	for column in _table.columns:
		if not GDSQLForeignKeyDefinition.supports_column_type(column.data_type):
			continue
		_local_column.add_item(
			"%s · %s" % [column.name, type_string(column.data_type)],
		)
		_local_column.set_item_metadata(_local_column.item_count - 1, column.name)
	_local_column.disabled = _local_column.item_count == 0
	_select_preferred_local_column()
	_refresh_targets()
	_refresh_registered_references()


func _on_local_column_selected(_index: int) -> void:
	_refresh_targets()


func _select_preferred_local_column() -> void:
	var selected_index := -1
	var selected_score := -1
	for index in range(_local_column.item_count):
		var column_name := StringName(_local_column.get_item_metadata(index))
		var normalized := String(column_name).to_lower()
		var score := 0
		if column_name != _table.primary_key:
			score += 4
		if normalized.contains("content"):
			score += 2
		if normalized.ends_with("_id") or normalized.ends_with("_key"):
			score += 1
		if score > selected_score:
			selected_index = index
			selected_score = score
	if selected_index >= 0:
		_local_column.select(selected_index)


func _refresh_targets() -> void:
	_content_target.clear()
	_targets.clear()
	var source_column := _selected_local_column()
	if source_column == null:
		_set_unavailable(
			"Add an int, String, or StringName content identifier to this save table.",
		)
		return
	for inspection in _inspections:
		if inspection == null or inspection.registration == null:
			continue
		for inspected_table in inspection.tables:
			_append_target(inspection, inspected_table, source_column.data_type)
	_content_target.disabled = _targets.is_empty()
	if _targets.is_empty():
		_set_unavailable(
			"No compatible content model binding was found. Generate or open its Model Assistant once.",
		)
		return
	for target in _targets:
		_content_target.add_item(
			"%s / %s · %s" % [
				target.database_name,
				target.table.name,
				target.model_class,
			],
		)
	_content_target.select(0)
	_on_target_selected(0)


func _append_target(
		inspection: GDSQLDatabaseInspection,
		inspected_table: GDSQLTableInspection,
		source_type: Variant.Type,
) -> void:
	if inspected_table.primary_key == &"":
		return
	var target_column := inspected_table.get_column(inspected_table.primary_key)
	if target_column == null or target_column.data_type != source_type:
		return
	var registration := inspection.registration
	var model_class := StringName(
		_load_binding_value(registration, inspected_table.name, SETTINGS_CLASS_KEY),
	)
	if model_class == &"":
		return
	var role := StringName(
		_load_binding_value(registration, inspected_table.name, SETTINGS_ROLE_KEY),
	)
	if role == &"":
		role = _role_for_registration(registration.name)
	if role != GDSQLDatabaseRegistry.CONTENT_ROLE:
		return
	_targets.append(
		Target.new(
			registration.name,
			registration.database_name,
			inspected_table,
			model_class,
		),
	)


func _selected_local_column() -> GDSQLColumnDefinition:
	if _local_column.item_count == 0:
		return null
	return _table.get_column(
		StringName(_local_column.get_item_metadata(_local_column.selected)),
	)


func _on_target_selected(index: int) -> void:
	if index < 0 or index >= _targets.size():
		_set_unavailable("Choose a content model target.")
		return
	var suggestion := String(_targets[index].model_class)
	if suggestion.ends_with("Content"):
		suggestion = suggestion.trim_suffix("Content")
	suggestion = suggestion.to_snake_case()
	if _relationship_name.text.is_empty() \
			or _relationship_name.text == _last_name_suggestion:
		_relationship_name.text = suggestion
	_last_name_suggestion = suggestion
	_refresh_snippet()


func _refresh_snippet(_value: String = "") -> void:
	var target := _selected_target()
	var source_column := _selected_local_column()
	var relationship_name := _relationship_name.text.strip_edges()
	if target == null or source_column == null or relationship_name.is_empty():
		_snippet.text = ""
		%CopyRelationship.disabled = true
		return
	if not relationship_name.is_valid_identifier() \
			or relationship_name != relationship_name.to_snake_case():
		_snippet.text = ""
		%RelationshipHelperStatus.text = (
				"Use a snake_case reference name such as hero_content."
		)
		%CopyRelationship.disabled = true
		return
	var reference := _current_reference()
	_snippet.text = reference.build_relationship_snippet() if reference != null else ""
	%RelationshipHelperStatus.text = (
			"Paste this entry inside the save model's relationships() return array."
	)
	%CopyRelationship.disabled = false


func _selected_target() -> Target:
	var index := _content_target.selected
	return _targets[index] if index >= 0 and index < _targets.size() else null


func _set_unavailable(message: String) -> void:
	_snippet.text = ""
	%RelationshipHelperStatus.text = message
	%CopyRelationship.disabled = true


func _copy_relationship() -> void:
	if _snippet.text.is_empty():
		return
	var reference := _current_reference()
	if reference == null:
		return
	var save_error := _reference_store.save(reference)
	if save_error != OK:
		%RelationshipHelperStatus.text = (
				"Could not register the editor picker (%s)." % error_string(save_error)
		)
		return
	DisplayServer.clipboard_set(_snippet.text)
	_refresh_registered_references()
	reference_registered.emit(_registration_name, _table.name)
	%RelationshipHelperStatus.text = (
			"Picker registered and relationship copied. Paste it inside relationships()."
	)


func _current_reference() -> GDSQLEditorContentReference:
	var target := _selected_target()
	var source_column := _selected_local_column()
	var relationship_name := StringName(_relationship_name.text.strip_edges())
	if target == null or source_column == null or relationship_name == &"":
		return null
	return GDSQLEditorContentReference.new(
		relationship_name,
		_registration_name,
		_table.database_name,
		_table.name,
		source_column.name,
		target.registration_name,
		target.database_name,
		target.table.name,
		target.table.primary_key,
		target.model_class,
	)


func _refresh_registered_references() -> void:
	for child in %RegisteredReferences.get_children():
		%RegisteredReferences.remove_child(child)
		child.queue_free()
	var references := _reference_store.load_for_table(
		_registration_name,
		_table.database_name,
		_table.name,
	)
	%NoRegisteredReferences.visible = references.is_empty()
	for reference in references:
		var row := CONTENT_REFERENCE_ROW_SCENE.instantiate()
		%RegisteredReferences.add_child(row)
		row.configure(reference)
		row.remove_requested.connect(_remove_registered_reference)
		row.snippet_copied.connect(_on_registered_snippet_copied)


func _remove_registered_reference(reference: GDSQLEditorContentReference) -> void:
	var remove_error := _reference_store.remove(reference)
	if remove_error != OK:
		%RelationshipHelperStatus.text = (
				"Could not remove the editor picker (%s)." % error_string(remove_error)
		)
		return
	_refresh_registered_references()
	reference_registered.emit(_registration_name, _table.name)
	%RelationshipHelperStatus.text = (
			"Removed %s from the editor picker. Model code was not changed."
			% reference.relationship_name
	)


func _on_registered_snippet_copied(
		reference: GDSQLEditorContentReference,
) -> void:
	%RelationshipHelperStatus.text = (
			"Copied the %s relationship declaration." % reference.relationship_name
	)


func _load_binding_value(
		registration: GDSQLDatabaseRegistration,
		table_name: StringName,
		key: String,
) -> String:
	return String(
		_settings.get_value(
			"%s%s:%s:%s" % [
				SETTINGS_BINDING_PREFIX,
				registration.name,
				registration.database_name,
				table_name,
			],
			key,
			"",
		),
	)


func _role_for_registration(registration_name: StringName) -> StringName:
	for binding in _role_bindings:
		if binding.registration_name == registration_name:
			return binding.role
	return &""


func _is_scene_preview() -> bool:
	if not Engine.is_editor_hint():
		return false
	var root := EditorInterface.get_edited_scene_root()
	return root == self or (root != null and root.is_ancestor_of(self))

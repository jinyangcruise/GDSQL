@tool
class_name GDSQLContentPreviewAdapter
extends Node
## Opt-in editor adapter that applies one content row to a transient scene.
##
## Assign a user model extending [GDSQLContentModel], enter the value of that
## model's primary key, choose a visual [PackedScene], and map model properties
## to compatible properties on the preview scene. Refreshing reads content only;
## the instantiated preview and fetched values are never saved into this scene.

signal preview_refreshed(result: GDSQLOperationResult)

const PREVIEW_NODE_NAME := &"GDSQLContentPreview"
const STATUS_PROPERTY := &"preview_status"

@export_category("Content Row")
## User-owned model script for the content table, such as `HeroContent`.
## Save and settings models are rejected because this preview is read-only.
@export var content_model: Script
## Primary-key value of the content row, not the column name. For example, use
## `1` for integer row id 1 or `iron_sword` for a String/StringName identifier.
@export_placeholder("Example: 1 or iron_sword") var stable_identifier := ""

@export_category("Transient Preview")
## Visual scene instantiated temporarily to display the selected content row.
@export var preview_scene: PackedScene
## Node that temporarily receives the preview instance. The path is relative to
## this adapter; `.` places it below the adapter. Fetched values never modify it.
@export_node_path("Node") var preview_host: NodePath = NodePath(".")
## Explicit model-to-scene property mappings. Source values come from the
## selected content model. Targets belong to the instantiated preview scene.
@export var bindings: Array[GDSQLContentPreviewBinding] = []

@export_category("Advanced Project Paths")
## Durable database registry. Keep the default unless the project moved it.
@export_file("*.cfg") var registry_path := GDSQLConfigFileDatabaseRegistryStore.DEFAULT_PATH
## Direct/Managed profile settings. Keep the default unless the project moved it.
@export_file("*.cfg") var setup_settings_path := GDSQLConfigFileSetupProfileStore.DEFAULT_PATH
## Disposable Managed Content cache root. Direct Content does not use it.
@export_dir var managed_cache_root := GDSQLConfigFileContentCacheStore.DEFAULT_CACHE_ROOT

@export_category("Actions")
## Reloads the configured row and rebuilds the transient preview instance.
@export_tool_button("Refresh Content Preview", "Reload") var refresh_action := refresh_preview
## Removes the transient preview without changing database or authored data.
@export_tool_button("Clear Content Preview", "Clear") var clear_action := clear_preview

var _preview_instance: Node
var _last_result: GDSQLOperationResult
var _status := "Not loaded."


func _exit_tree() -> void:
	clear_preview()


func _get_property_list() -> Array[Dictionary]:
	return [
		{
			"name": STATUS_PROPERTY,
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_MULTILINE_TEXT,
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
		},
	]


func _get(property: StringName) -> Variant:
	if property == STATUS_PROPERTY:
		return _status
	return null


func refresh_preview() -> GDSQLOperationResult:
	clear_preview()
	var validation := _validate_configuration()
	if not validation.is_successful():
		return _complete(validation)
	var runtime_node := GDSQLRuntimeNode.new()
	runtime_node.auto_start = false
	runtime_node.registry_path = registry_path
	runtime_node.setup_settings_path = setup_settings_path
	runtime_node.managed_cache_root = managed_cache_root
	var started := runtime_node.start()
	if not started.is_successful():
		runtime_node.free()
		return _complete(started)
	var runtime := started.get_value() as GDSQLRuntimeSession
	var loaded := GDSQLEditorContentPreviewService.new(
		runtime.get_model_context(),
	).load(content_model, stable_identifier)
	if loaded.is_successful():
		_apply_preview(loaded.get_value() as GDSQLModel, loaded)
	runtime_node.stop(false)
	runtime_node.free()
	return _complete(loaded)


func clear_preview() -> void:
	if is_instance_valid(_preview_instance):
		_preview_instance.free()
	_preview_instance = null


func get_last_result() -> GDSQLOperationResult:
	return _last_result


func get_preview_instance() -> Node:
	return _preview_instance


func _validate_configuration() -> GDSQLOperationResult:
	if preview_scene == null:
		return _failure(
			&"GDSQL_CONTENT_PREVIEW_SCENE_REQUIRED",
			"Choose a scene to instantiate as the transient preview.",
		)
	if bindings.is_empty():
		return _failure(
			&"GDSQL_CONTENT_PREVIEW_BINDING_REQUIRED",
			"Add at least one content-to-preview property binding.",
		)
	var host := get_node_or_null(preview_host)
	if host == null:
		return _failure(
			&"GDSQL_CONTENT_PREVIEW_HOST_NOT_FOUND",
			"The configured preview host does not exist.",
		)
	return GDSQLOperationResult.new()


func _apply_preview(model: GDSQLModel, result: GDSQLOperationResult) -> void:
	var host := get_node_or_null(preview_host)
	var instance := preview_scene.instantiate()
	instance.name = PREVIEW_NODE_NAME
	host.add_child(instance, false, Node.INTERNAL_MODE_FRONT)
	instance.owner = null
	_preview_instance = instance
	for binding in bindings:
		var applied := _apply_binding(model, instance, binding)
		result.diagnostics.merge(applied.diagnostics)
		if not applied.is_successful():
			clear_preview()
			return
	result.value = instance


func _apply_binding(
		model: GDSQLModel,
		preview_root: Node,
		binding: GDSQLContentPreviewBinding,
) -> GDSQLOperationResult:
	if binding == null or binding.model_property == &"" or binding.target_property == &"":
		return _failure(
			&"GDSQL_CONTENT_PREVIEW_BINDING_INVALID",
			"Every preview binding requires model and target properties.",
		)
	if not _has_property(model, binding.model_property):
		return _failure(
			&"GDSQL_CONTENT_PREVIEW_MODEL_PROPERTY_NOT_FOUND",
			"Content model property '%s' does not exist." % binding.model_property,
		)
	var target := (
			preview_root
			if binding.target_node.is_empty() or binding.target_node == NodePath(".")
			else preview_root.get_node_or_null(binding.target_node)
	)
	if target == null:
		return _failure(
			&"GDSQL_CONTENT_PREVIEW_TARGET_NOT_FOUND",
			"Preview target node '%s' does not exist." % binding.target_node,
		)
	if not _has_property(target, binding.target_property):
		return _failure(
			&"GDSQL_CONTENT_PREVIEW_TARGET_PROPERTY_NOT_FOUND",
			"Preview target '%s' has no property named '%s'." % [
				target.name,
				binding.target_property,
			],
		)
	target.set(binding.target_property, model.get(binding.model_property))
	return GDSQLOperationResult.new()


func _has_property(object: Object, property_name: StringName) -> bool:
	for property in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _complete(result: GDSQLOperationResult) -> GDSQLOperationResult:
	_last_result = result
	_status = (
			"Preview ready. Values are applied to a transient scene instance."
			if result.is_successful()
			else _first_diagnostic(result)
	)
	notify_property_list_changed()
	update_configuration_warnings()
	preview_refreshed.emit(result)
	return result


func _first_diagnostic(result: GDSQLOperationResult) -> String:
	if result != null and not result.diagnostics.entries.is_empty():
		return result.diagnostics.entries[0].message
	return "Content preview failed."


func _get_configuration_warnings() -> PackedStringArray:
	if _last_result != null and not _last_result.is_successful():
		return PackedStringArray([_first_diagnostic(_last_result)])
	return PackedStringArray()


func _failure(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result

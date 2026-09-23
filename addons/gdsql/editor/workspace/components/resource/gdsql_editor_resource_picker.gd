@tool
extends EditorResourcePicker
## Resource picker that keeps imported audio formats load-only.

const CREATE_OPTION_BASE := 1000
const LOAD_ONLY_TYPES: Array[StringName] = [
	&"AudioStreamMP3",
	&"AudioStreamOggVorbis",
]

var _create_types: Dictionary[int, StringName] = { }


func _init() -> void:
	resource_changed.connect(_reject_unpresentable_resource)


static func can_present(resource: Resource) -> bool:
	if resource == null:
		return true
	match resource.get_class():
		"AudioStreamMP3":
			var data: Variant = resource.get(&"data")
			return data is PackedByteArray and not (data as PackedByteArray).is_empty()
		"AudioStreamOggVorbis":
			return resource.get(&"packet_sequence") != null
	return true


func _reject_unpresentable_resource(resource: Resource) -> void:
	if not can_present(resource):
		set_edited_resource(null)


func _set_create_options(menu_node: Object) -> void:
	var menu := menu_node as PopupMenu
	if menu == null:
		return
	_create_types.clear()
	var allowed_types := get_allowed_types()
	allowed_types.sort()
	for type_text in allowed_types:
		var type_name := StringName(type_text)
		if type_name in LOAD_ONLY_TYPES or not _can_instantiate(type_name):
			continue
		_create_types[CREATE_OPTION_BASE + _create_types.size()] = type_name
	if _create_types.is_empty():
		return
	menu.add_separator("New")
	for option_id in _create_types:
		var type_name := _create_types[option_id]
		var icon_name := type_name if has_theme_icon(type_name, &"EditorIcons") else &"Resource"
		menu.add_icon_item(
			get_theme_icon(icon_name, &"EditorIcons"),
			String(type_name),
			option_id,
		)
	menu.add_separator()


func _handle_menu_selected(option_id: int) -> bool:
	if not _create_types.has(option_id):
		return false
	var resource := _instantiate(_create_types[option_id])
	if resource != null:
		set_edited_resource(resource)
		resource_changed.emit(resource)
	return true


func _can_instantiate(type_name: StringName) -> bool:
	if ClassDB.class_exists(type_name):
		return ClassDB.can_instantiate(type_name)
	var script := _global_class_script(type_name)
	return script != null and script.can_instantiate()


func _instantiate(type_name: StringName) -> Resource:
	if ClassDB.class_exists(type_name):
		return ClassDB.instantiate(type_name) as Resource
	var script := _global_class_script(type_name)
	return script.new() as Resource if script != null and script.can_instantiate() else null


func _global_class_script(type_name: StringName) -> Script:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if StringName(entry.get("class", "")) == type_name:
			return load(String(entry.get("path", ""))) as Script
	return null

class_name GDSQLResourceTypeConstraint
extends RefCounted
## Describes the concrete Resource family accepted by a TYPE_OBJECT column.
##
## Native Resource types are identified by [member resource_class]. Project script
## classes additionally retain their script path and resolved Script so value
## checks can use Godot's dynamic inheritance validation.

var resource_class: StringName
var script_path: String
var resolved_script: Script


func _init(
		target_class_name: StringName = &"",
		target_script_path: String = "",
		target_script: Script = null,
) -> void:
	resource_class = target_class_name
	script_path = target_script_path
	resolved_script = target_script


static func from_serialized(
		target_class_name: StringName,
		target_script_path: String = "",
) -> GDSQLResourceTypeConstraint:
	var resolved_script: Script
	if not target_script_path.is_empty() and ResourceLoader.exists(target_script_path):
		resolved_script = ResourceLoader.load(target_script_path) as Script
	return GDSQLResourceTypeConstraint.new(
		target_class_name,
		target_script_path,
		resolved_script,
	)


static func from_resource(prototype: Resource) -> GDSQLResourceTypeConstraint:
	if prototype == null:
		return null
	var prototype_script := prototype.get_script() as Script
	if prototype_script != null:
		var path := prototype_script.resource_path
		var global_name := prototype_script.get_global_name()
		var identity := global_name if global_name != &"" else StringName(path)
		return GDSQLResourceTypeConstraint.new(identity, path, prototype_script)
	return GDSQLResourceTypeConstraint.new(StringName(prototype.get_class()))


func is_valid() -> bool:
	if resource_class == &"" or resource_class == &"Resource":
		return false
	if resolved_script != null:
		return not script_path.is_empty() \
				and _is_resource_class(resolved_script.get_instance_base_type())
	return script_path.is_empty() and _is_resource_class(resource_class)


func accepts_value(value: Variant) -> bool:
	if not is_valid() or not value is Resource:
		return false
	if resolved_script != null:
		return is_instance_of(value, resolved_script)
	return (value as Resource).is_class(resource_class)


func is_equivalent_to(other: GDSQLResourceTypeConstraint) -> bool:
	return other != null \
			and resource_class == other.resource_class \
			and script_path == other.script_path


func display_name() -> String:
	if resolved_script != null:
		var global_name := resolved_script.get_global_name()
		if global_name != &"":
			return String(global_name)
		if not script_path.is_empty():
			return script_path.get_file().get_basename()
	return String(resource_class) if resource_class != &"" else "Unspecified Resource"


func picker_base_type() -> String:
	if resolved_script != null:
		var global_name := resolved_script.get_global_name()
		return (
			String(global_name)
			if global_name != &""
			else String(resolved_script.get_instance_base_type())
		)
	return String(resource_class)


func instantiate_prototype() -> Resource:
	if not is_valid():
		return null
	if resolved_script != null and resolved_script.can_instantiate():
		return resolved_script.new() as Resource
	if ClassDB.class_exists(resource_class) and ClassDB.can_instantiate(resource_class):
		return ClassDB.instantiate(resource_class) as Resource
	return null


static func _is_resource_class(candidate: StringName) -> bool:
	return candidate == &"Resource" or (
		ClassDB.class_exists(candidate)
		and ClassDB.is_parent_class(candidate, &"Resource")
	)

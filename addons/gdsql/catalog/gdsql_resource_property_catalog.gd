class_name GDSQLResourcePropertyCatalog
extends RefCounted
## Discovers bounded Resource properties that are safe to expose as filters.
##
## Only Inspector-visible scalar leaves are returned. Compound Variant values
## are represented through their scalar components, so a Vector3 property
## contributes x, y, and z leaves but is never itself a filter value.

const FILTERABLE_SCALARS: Array[Variant.Type] = [
	TYPE_BOOL,
	TYPE_INT,
	TYPE_FLOAT,
	TYPE_STRING,
	TYPE_STRING_NAME,
]


func list_filterable_leaves(
		constraint: GDSQLResourceTypeConstraint,
) -> Array[GDSQLResourcePropertyDefinition]:
	var leaves: Array[GDSQLResourcePropertyDefinition] = []
	if constraint == null or not constraint.is_valid():
		return leaves
	var seen: Dictionary = { }
	for property_info in _property_list(constraint):
		var usage := int(property_info.get("usage", 0))
		var property_type := int(property_info.get("type", TYPE_NIL)) as Variant.Type
		var property_name := StringName(property_info.get("name", ""))
		if property_name == &"" \
				or property_type == TYPE_NIL \
				or usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		var root_path: Array[StringName] = [property_name]
		_append_leaves(leaves, seen, root_path, property_type)
	return leaves


func resolve_filterable_leaf(
		constraint: GDSQLResourceTypeConstraint,
		serialized_path: String,
) -> GDSQLResourcePropertyDefinition:
	for definition in list_filterable_leaves(constraint):
		if definition.serialized_path() == serialized_path:
			return definition
	return null


func _property_list(constraint: GDSQLResourceTypeConstraint) -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	if constraint.resolved_script != null:
		var base_type := constraint.resolved_script.get_instance_base_type()
		if ClassDB.class_exists(base_type):
			properties.append_array(ClassDB.class_get_property_list(base_type))
		properties.append_array(constraint.resolved_script.get_script_property_list())
	elif ClassDB.class_exists(constraint.resource_class):
		properties.append_array(ClassDB.class_get_property_list(constraint.resource_class))
	return properties


func _append_leaves(
		leaves: Array[GDSQLResourcePropertyDefinition],
		seen: Dictionary,
		root_path: Array[StringName],
		data_type: Variant.Type,
) -> void:
	if data_type in FILTERABLE_SCALARS:
		_append_unique(leaves, seen, root_path, data_type)
		return
	var component_type := _component_type(data_type)
	if component_type == TYPE_NIL:
		return
	for component in _component_names(data_type):
		var component_path := root_path.duplicate()
		component_path.append(component)
		_append_unique(leaves, seen, component_path, component_type)


func _append_unique(
		leaves: Array[GDSQLResourcePropertyDefinition],
		seen: Dictionary,
		path: Array[StringName],
		data_type: Variant.Type,
) -> void:
	var definition := GDSQLResourcePropertyDefinition.new(path, data_type)
	var key := definition.serialized_path()
	if seen.has(key):
		return
	seen[key] = true
	leaves.append(definition)


func _component_type(data_type: Variant.Type) -> Variant.Type:
	if data_type in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I]:
		return TYPE_INT
	if data_type in [TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR]:
		return TYPE_FLOAT
	return TYPE_NIL


func _component_names(data_type: Variant.Type) -> Array[StringName]:
	match data_type:
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [&"x", &"y"]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [&"x", &"y", &"z"]
		TYPE_VECTOR4, TYPE_VECTOR4I:
			return [&"x", &"y", &"z", &"w"]
		TYPE_COLOR:
			return [&"r", &"g", &"b", &"a"]
	return []

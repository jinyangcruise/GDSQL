class_name GDSQLModelDefinition
extends RefCounted
## Stable metadata captured when a model script is registered.

var model_script: Script
var database_role: StringName
var table_name: StringName
var primary_key: StringName
var access_mode: GDSQLModelAccess.Mode
var _declared_relationships: Dictionary[StringName, GDSQLRelationshipDefinition] = { }
var _inferred_relationships: Dictionary[StringName, GDSQLRelationshipDefinition] = { }


func _init(
		script: Script = null,
		role: StringName = &"",
		table: StringName = &"",
		key: StringName = &"id",
		mode: GDSQLModelAccess.Mode = GDSQLModelAccess.Mode.READ_ONLY,
		relationships: Array[GDSQLRelationshipDefinition] = [],
) -> void:
	model_script = script
	database_role = role
	table_name = table
	primary_key = key
	access_mode = mode
	for relationship in relationships:
		_declared_relationships[relationship.name] = relationship


func has_relationship(relationship_name: StringName) -> bool:
	return _declared_relationships.has(relationship_name) \
			or _inferred_relationships.has(relationship_name)


func get_relationship(relationship_name: StringName) -> GDSQLRelationshipDefinition:
	if _declared_relationships.has(relationship_name):
		return _declared_relationships[relationship_name]
	return _inferred_relationships.get(relationship_name)


func get_relationships() -> Array[GDSQLRelationshipDefinition]:
	var result: Array[GDSQLRelationshipDefinition] = []
	for relationship in _declared_relationships.values():
		result.append(relationship)
	for relationship in _inferred_relationships.values():
		result.append(relationship)
	return result


func replace_inferred_relationships(
		relationships: Array[GDSQLRelationshipDefinition],
) -> void:
	_inferred_relationships.clear()
	for relationship in relationships:
		if relationship != null \
				and not _declared_relationships.has(relationship.name) \
				and not _inferred_relationships.has(relationship.name):
			_inferred_relationships[relationship.name] = relationship

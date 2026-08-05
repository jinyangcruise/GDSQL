class_name GDSQLModelDefinition
extends RefCounted
## Stable metadata captured when a model script is registered.

var model_script: Script
var database_role: StringName
var table_name: StringName
var primary_key: StringName
var access_mode: GDSQLModelAccess.Mode
var _relationships: Dictionary[StringName, GDSQLRelationshipDefinition] = { }


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
		_relationships[relationship.name] = relationship


func has_relationship(relationship_name: StringName) -> bool:
	return _relationships.has(relationship_name)


func get_relationship(relationship_name: StringName) -> GDSQLRelationshipDefinition:
	return _relationships.get(relationship_name)


func get_relationships() -> Array[GDSQLRelationshipDefinition]:
	var result: Array[GDSQLRelationshipDefinition] = []
	for relationship in _relationships.values():
		result.append(relationship)
	return result

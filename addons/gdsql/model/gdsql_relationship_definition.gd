class_name GDSQLRelationshipDefinition
extends RefCounted
## Typed description of navigation between two registered model types.

enum Kind { BELONGS_TO, HAS_ONE, HAS_MANY }

var name: StringName
var kind: Kind
var related_model_script: Script
var local_key: StringName
var related_key: StringName


func _init(
		relationship_name: StringName = &"",
		relationship_kind: Kind = Kind.BELONGS_TO,
		related_model: Script = null,
		declaring_model_key: StringName = &"",
		related_model_key: StringName = &"",
) -> void:
	name = relationship_name
	kind = relationship_kind
	related_model_script = related_model
	local_key = declaring_model_key
	related_key = related_model_key


## Declares that this model contains a foreign key for one related model.
static func belongs_to(
		relationship_name: StringName,
		related_model: Script,
		foreign_key: StringName,
		owner_key: StringName = &"id",
) -> GDSQLRelationshipDefinition:
	return GDSQLRelationshipDefinition.new(
		relationship_name,
		Kind.BELONGS_TO,
		related_model,
		foreign_key,
		owner_key,
	)


## Declares one related model whose foreign key references this model.
static func has_one(
		relationship_name: StringName,
		related_model: Script,
		foreign_key: StringName,
		local_key: StringName = &"id",
) -> GDSQLRelationshipDefinition:
	return GDSQLRelationshipDefinition.new(
		relationship_name,
		Kind.HAS_ONE,
		related_model,
		local_key,
		foreign_key,
	)


## Declares many related models whose foreign key references this model.
static func has_many(
		relationship_name: StringName,
		related_model: Script,
		foreign_key: StringName,
		local_key: StringName = &"id",
) -> GDSQLRelationshipDefinition:
	return GDSQLRelationshipDefinition.new(
		relationship_name,
		Kind.HAS_MANY,
		related_model,
		local_key,
		foreign_key,
	)

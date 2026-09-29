class_name GDSQLRelationshipDefinition
extends RefCounted
## Typed description of navigation between two registered model types.

enum Kind {
	BELONGS_TO,
	HAS_ONE,
	HAS_MANY,
	MANY_TO_MANY,
	REFERENCES_ONE,
}

var name: StringName
var kind: Kind
var related_model_script: Script
var local_key: StringName
var related_key: StringName
var through_model_script: Script
var through_local_key: StringName
var through_related_key: StringName


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


## Declares one stable reference resolved through the target model's role.
static func references_one(
		reference_name: StringName,
		related_model: Script,
		local_reference_key: StringName,
		related_identity_key: StringName = &"id",
) -> GDSQLRelationshipDefinition:
	return GDSQLRelationshipDefinition.new(
		reference_name,
		Kind.REFERENCES_ONE,
		related_model,
		local_reference_key,
		related_identity_key,
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


## Declares many related models connected through a registered junction model.
static func many_to_many(
		relationship_name: StringName,
		related_model: Script,
		through_model: Script,
		through_source_key: StringName,
		through_target_key: StringName,
		local_key: StringName = &"id",
		related_key: StringName = &"id",
) -> GDSQLRelationshipDefinition:
	return GDSQLRelationshipDefinition.new(
		relationship_name,
		Kind.MANY_TO_MANY,
		related_model,
		local_key,
		related_key,
		through_model,
		through_source_key,
		through_target_key,
	)


func _init(
		relationship_name: StringName = &"",
		relationship_kind: Kind = Kind.BELONGS_TO,
		related_model: Script = null,
		declaring_model_key: StringName = &"",
		related_model_key: StringName = &"",
		junction_model: Script = null,
		junction_source_key: StringName = &"",
		junction_target_key: StringName = &"",
) -> void:
	name = relationship_name
	kind = relationship_kind
	related_model_script = related_model
	local_key = declaring_model_key
	related_key = related_model_key
	through_model_script = junction_model
	through_local_key = junction_source_key
	through_related_key = junction_target_key

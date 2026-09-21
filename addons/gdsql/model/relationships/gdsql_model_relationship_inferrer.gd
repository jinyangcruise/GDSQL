class_name GDSQLModelRelationshipInferrer
extends RefCounted
## Derives default same-database model navigation from catalog foreign keys.


func infer(
		definition: GDSQLModelDefinition,
		definitions: Array[GDSQLModelDefinition],
		database: GDSQLDatabaseDefinition,
) -> Array[GDSQLRelationshipDefinition]:
	var inferred: Array[GDSQLRelationshipDefinition] = []
	if definition == null or database == null:
		return inferred
	var table := database.get_table(definition.table_name)
	var model := definition.model_script.new() as GDSQLModel
	if table == null or model == null:
		return inferred

	for foreign_key in table.foreign_keys:
		var matching_target_count := _foreign_keys_to(
			table,
			foreign_key.referenced_table,
		).size()
		var related := _find_model(
			definitions,
			definition.database_role,
			foreign_key.referenced_table,
		)
		if related != null and _relationship_keys_exist(
				model,
				foreign_key.column,
				related,
				foreign_key.referenced_column,
		):
			inferred.append(
				GDSQLRelationshipDefinition.belongs_to(
					_belongs_to_name(foreign_key, matching_target_count),
					related.model_script,
					foreign_key.column,
					foreign_key.referenced_column,
				),
			)

	for related_table in database.tables:
		var related := _find_model(
			definitions,
			definition.database_role,
			related_table.name,
		)
		if related == null:
			continue
		var incoming := _foreign_keys_to(related_table, table.name)
		for foreign_key in incoming:
			if not _relationship_keys_exist(
					model,
					foreign_key.referenced_column,
					related,
					foreign_key.column,
			):
				continue
			var name := _inverse_name(related_table, foreign_key, incoming.size())
			inferred.append(
				GDSQLRelationshipDefinition.has_one(
					name,
					related.model_script,
					foreign_key.column,
					foreign_key.referenced_column,
				)
				if related_table.has_unique_key(foreign_key.column)
				else GDSQLRelationshipDefinition.has_many(
					name,
					related.model_script,
					foreign_key.column,
					foreign_key.referenced_column,
				),
			)
	return inferred


static func describe(
		table: GDSQLTableDefinition,
		database: GDSQLDatabaseDefinition,
) -> Array[String]:
	var descriptions: Array[String] = []
	if table == null or database == null:
		return descriptions
	for foreign_key in table.foreign_keys:
		var matching_target_count := _foreign_keys_to(
			table,
			foreign_key.referenced_table,
		).size()
		descriptions.append(
			"belongs_to %s · %s → %s.%s" % [
				_belongs_to_name(foreign_key, matching_target_count),
				foreign_key.column,
				foreign_key.referenced_table,
				foreign_key.referenced_column,
			],
		)
	for related_table in database.tables:
		var incoming := _foreign_keys_to(related_table, table.name)
		for foreign_key in incoming:
			descriptions.append(
				"%s %s · %s → %s.%s" % [
					"has_one" if related_table.has_unique_key(foreign_key.column) \
							else "has_many",
					_inverse_name(related_table, foreign_key, incoming.size()),
					foreign_key.referenced_column,
					related_table.name,
					foreign_key.column,
				],
			)
	return descriptions


func _find_model(
		definitions: Array[GDSQLModelDefinition],
		role: StringName,
		table_name: StringName,
) -> GDSQLModelDefinition:
	var found: GDSQLModelDefinition
	for candidate in definitions:
		if candidate.database_role != role or candidate.table_name != table_name:
			continue
		if found != null:
			return null
		found = candidate
	return found


func _relationship_keys_exist(
		model: GDSQLModel,
		local_key: StringName,
		related: GDSQLModelDefinition,
		related_key: StringName,
) -> bool:
	var related_model := related.model_script.new() as GDSQLModel
	return _has_property(model, local_key) \
			and related_model != null \
			and _has_property(related_model, related_key)


func _has_property(model: GDSQLModel, property_name: StringName) -> bool:
	for property in model.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


static func _foreign_keys_to(
		table: GDSQLTableDefinition,
		target_table: StringName,
) -> Array[GDSQLForeignKeyDefinition]:
	var matches: Array[GDSQLForeignKeyDefinition] = []
	for foreign_key in table.foreign_keys:
		if foreign_key.referenced_table == target_table:
			matches.append(foreign_key)
	return matches


static func _belongs_to_name(
		foreign_key: GDSQLForeignKeyDefinition,
		matching_target_count: int = 1,
) -> StringName:
	if matching_target_count <= 1:
		return StringName(_singularize(String(foreign_key.referenced_table)))
	var local_name := String(foreign_key.column)
	if local_name.ends_with("_id"):
		local_name = local_name.trim_suffix("_id")
	if local_name.is_empty():
		local_name = _singularize(String(foreign_key.referenced_table))
	return StringName(local_name)


static func _inverse_name(
		table: GDSQLTableDefinition,
		foreign_key: GDSQLForeignKeyDefinition,
		matching_key_count: int,
) -> StringName:
	var table_name := (
		_singularize(String(table.name))
		if table.has_unique_key(foreign_key.column)
		else String(table.name)
	)
	if matching_key_count <= 1:
		return StringName(table_name)
	return StringName("%s_%s" % [_belongs_to_name(foreign_key, 2), table_name])


static func _singularize(value: String) -> String:
	if value.ends_with("ies") and value.length() > 3:
		return value.left(-3) + "y"
	if value.ends_with("oes") and value.length() > 3:
		return value.left(-2)
	if value.ends_with("s") \
			and not value.ends_with("ss") \
			and not value.ends_with("us") \
			and not value.ends_with("is"):
		return value.left(-1)
	return value

class_name GDSQLMigrationDefinitionSerializer
extends RefCounted
## Converts typed migration definitions at the external-data boundary.

const FORMAT_VERSION := 1


static func encode(migration: GDSQLMigrationDefinition) -> Dictionary:
	if migration == null:
		return { }
	var steps: Array[Dictionary] = []
	for step in migration.steps:
		steps.append(_encode_step(step))
	return {
		"format_version": FORMAT_VERSION,
		"migration_id": migration.migration_id,
		"description": migration.description,
		"checksum": migration.checksum,
		"steps": steps,
	}


static func decode(payload: Dictionary) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if int(payload.get("format_version", 0)) != FORMAT_VERSION:
		return _error(
			result,
			&"GDSQL_MIGRATION_DEFINITION_FORMAT_UNSUPPORTED",
			"Authored migration format is missing or unsupported.",
		)
	var raw_steps: Variant = payload.get("steps")
	if not raw_steps is Array:
		return _invalid(result)
	var steps: Array[GDSQLSchemaMigrationStep] = []
	for raw_step in raw_steps:
		if not raw_step is Dictionary:
			return _invalid(result)
		var decoded_step := _decode_step(raw_step)
		result.diagnostics.merge(decoded_step.diagnostics)
		if not decoded_step.is_successful():
			return result
		steps.append(decoded_step.get_value() as GDSQLSchemaMigrationStep)
	var migration := GDSQLMigrationDefinition.new(
		String(payload.get("migration_id", "")),
		String(payload.get("description", "")),
		steps,
	)
	var stored_checksum := String(payload.get("checksum", ""))
	if not migration.is_valid():
		return _invalid(result)
	if stored_checksum != migration.checksum:
		return _error(
			result,
			&"GDSQL_MIGRATION_HISTORY_CHECKSUM_MISMATCH",
			"Authored migration '%s' changed after its checksum was recorded." \
					% migration.migration_id,
		)
	result.value = migration
	return result


static func _encode_step(step: GDSQLSchemaMigrationStep) -> Dictionary:
	if step == null:
		return { }
	var alterations: Array[Dictionary] = []
	for alteration in step.alterations:
		alterations.append(_encode_alteration(alteration))
	return {
		"table_name": String(step.table_name),
		"alterations": alterations,
	}


static func _decode_step(payload: Dictionary) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var raw_alterations: Variant = payload.get("alterations")
	if not raw_alterations is Array:
		return _invalid(result)
	var alterations: Array[GDSQLTableAlteration] = []
	for raw_alteration in raw_alterations:
		if not raw_alteration is Dictionary:
			return _invalid(result)
		var alteration := _decode_alteration(raw_alteration)
		if alteration == null:
			return _invalid(result)
		alterations.append(alteration)
	var step := GDSQLSchemaMigrationStep.new(
		StringName(payload.get("table_name", "")),
		alterations,
	)
	if not step.is_valid():
		return _invalid(result)
	result.value = step
	return result


static func _encode_alteration(alteration: GDSQLTableAlteration) -> Dictionary:
	if alteration == null:
		return { }
	return {
		"kind": alteration.kind,
		"column": _encode_column(alteration.column),
		"column_name": String(alteration.column_name),
		"new_column_name": String(alteration.new_column_name),
		"index": _encode_index(alteration.index),
		"index_name": String(alteration.index_name),
		"foreign_key": _encode_foreign_key(alteration.foreign_key),
		"foreign_key_name": String(alteration.foreign_key_name),
		"value": alteration.value,
		"enabled": alteration.enabled,
		"generation": alteration.generation,
		"resource_ownership": alteration.resource_ownership,
		"column_names": PackedStringArray(alteration.column_names),
	}


static func _decode_alteration(payload: Dictionary) -> GDSQLTableAlteration:
	var kind := int(payload.get("kind", -1))
	if kind < GDSQLTableAlteration.Kind.ADD_COLUMN \
			or kind > GDSQLTableAlteration.Kind.REORDER_COLUMNS:
		return null
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = kind as GDSQLTableAlteration.Kind
	alteration.column = _decode_column(payload.get("column", { }))
	alteration.column_name = StringName(payload.get("column_name", ""))
	alteration.new_column_name = StringName(payload.get("new_column_name", ""))
	alteration.index = _decode_index(payload.get("index", { }))
	alteration.index_name = StringName(payload.get("index_name", ""))
	alteration.foreign_key = _decode_foreign_key(payload.get("foreign_key", { }))
	alteration.foreign_key_name = StringName(payload.get("foreign_key_name", ""))
	alteration.value = payload.get("value")
	alteration.enabled = bool(payload.get("enabled", false))
	alteration.generation = int(
		payload.get("generation", GDSQLColumnDefinition.Generation.NONE),
	) as GDSQLColumnDefinition.Generation
	alteration.resource_ownership = int(
		payload.get("resource_ownership", GDSQLResourceOwnership.Mode.OWNED),
	)
	alteration.column_names = _string_names(payload.get("column_names", []))
	return alteration if _has_required_shape(alteration) else null


static func _has_required_shape(alteration: GDSQLTableAlteration) -> bool:
	match alteration.kind:
		GDSQLTableAlteration.Kind.ADD_COLUMN:
			return alteration.column != null
		GDSQLTableAlteration.Kind.RENAME_COLUMN:
			return alteration.column_name != &"" and alteration.new_column_name != &""
		GDSQLTableAlteration.Kind.DROP_COLUMN:
			return alteration.column_name != &""
		GDSQLTableAlteration.Kind.ADD_INDEX:
			return alteration.index != null
		GDSQLTableAlteration.Kind.DROP_INDEX:
			return alteration.index_name != &""
		GDSQLTableAlteration.Kind.ADD_FOREIGN_KEY:
			return alteration.foreign_key != null
		GDSQLTableAlteration.Kind.DROP_FOREIGN_KEY:
			return alteration.foreign_key_name != &""
		GDSQLTableAlteration.Kind.SET_COLUMN_DEFAULT, \
		GDSQLTableAlteration.Kind.CLEAR_COLUMN_DEFAULT, \
		GDSQLTableAlteration.Kind.SET_COLUMN_NULLABLE, \
		GDSQLTableAlteration.Kind.SET_COLUMN_UNIQUE, \
		GDSQLTableAlteration.Kind.SET_COLUMN_AUTO_INCREMENT, \
		GDSQLTableAlteration.Kind.SET_COLUMN_GENERATION, \
		GDSQLTableAlteration.Kind.SET_RESOURCE_OWNERSHIP:
			return alteration.column_name != &""
		GDSQLTableAlteration.Kind.REORDER_COLUMNS:
			return not alteration.column_names.is_empty()
	return false


static func _encode_column(column: GDSQLColumnDefinition) -> Dictionary:
	if column == null:
		return { }
	return {
		"name": String(column.name),
		"data_type": column.data_type,
		"nullable": column.nullable,
		"unique": column.unique,
		"auto_increment": column.auto_increment,
		"has_default": column.has_default(),
		"default": column.get_default_value(),
		"generation": column.generation,
		"resource_ownership": column.resource_ownership,
		"resource_class": String(column.resource_type.resource_class) \
				if column.resource_type != null else "",
		"resource_script": column.resource_type.script_path \
				if column.resource_type != null else "",
	}


static func _decode_column(value: Variant) -> GDSQLColumnDefinition:
	if not value is Dictionary or value.is_empty():
		return null
	var payload := value as Dictionary
	var data_type := int(payload.get("data_type", TYPE_NIL)) as Variant.Type
	var resource_type: GDSQLResourceTypeConstraint
	if data_type == TYPE_OBJECT:
		resource_type = GDSQLResourceTypeConstraint.from_serialized(
			StringName(payload.get("resource_class", "")),
			String(payload.get("resource_script", "")),
		)
	var column := GDSQLColumnDefinition.new(
		StringName(payload.get("name", "")),
		data_type,
		bool(payload.get("nullable", true)),
		bool(payload.get("unique", false)),
		bool(payload.get("auto_increment", false)),
		null,
		resource_type,
	)
	column.generation = int(
		payload.get("generation", GDSQLColumnDefinition.Generation.NONE),
	) as GDSQLColumnDefinition.Generation
	column.resource_ownership = int(
		payload.get("resource_ownership", GDSQLResourceOwnership.Mode.OWNED),
	)
	if bool(payload.get("has_default", false)):
		column.set_default(payload.get("default"))
	return column


static func _encode_index(index: GDSQLIndexDefinition) -> Dictionary:
	if index == null:
		return { }
	return {
		"name": String(index.name),
		"columns": PackedStringArray(index.columns),
		"unique": index.unique,
	}


static func _decode_index(value: Variant) -> GDSQLIndexDefinition:
	if not value is Dictionary or value.is_empty():
		return null
	var payload := value as Dictionary
	return GDSQLIndexDefinition.new(
		StringName(payload.get("name", "")),
		_string_names(payload.get("columns", [])),
		bool(payload.get("unique", false)),
	)


static func _encode_foreign_key(
		foreign_key: GDSQLForeignKeyDefinition,
) -> Dictionary:
	if foreign_key == null:
		return { }
	return {
		"name": String(foreign_key.name),
		"column": String(foreign_key.column),
		"referenced_table": String(foreign_key.referenced_table),
		"referenced_column": String(foreign_key.referenced_column),
		"on_delete": foreign_key.on_delete,
		"on_update": foreign_key.on_update,
	}


static func _decode_foreign_key(value: Variant) -> GDSQLForeignKeyDefinition:
	if not value is Dictionary or value.is_empty():
		return null
	var payload := value as Dictionary
	return GDSQLForeignKeyDefinition.new(
		StringName(payload.get("name", "")),
		StringName(payload.get("column", "")),
		StringName(payload.get("referenced_table", "")),
		StringName(payload.get("referenced_column", "")),
		int(payload.get("on_delete", GDSQLForeignKeyDefinition.Action.RESTRICT)) \
				as GDSQLForeignKeyDefinition.Action,
		int(payload.get("on_update", GDSQLForeignKeyDefinition.Action.RESTRICT)) \
				as GDSQLForeignKeyDefinition.Action,
	)


static func _string_names(value: Variant) -> Array[StringName]:
	var names: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for item in value:
			names.append(StringName(item))
	return names


static func _invalid(result: GDSQLOperationResult) -> GDSQLOperationResult:
	return _error(
		result,
		&"GDSQL_MIGRATION_DEFINITION_INVALID",
		"Authored migration data does not describe a valid typed definition.",
	)


static func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result

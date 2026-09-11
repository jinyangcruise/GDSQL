class_name GDSQLContentOverlayLoader
extends RefCounted
## Applies ordered package layers without mutating their source definitions or rows.

const DEFAULT_SOURCE_DATABASE := &"game_content"
const DEFAULT_EFFECTIVE_DATABASE := &"effective_content"

var _layer_reader: GDSQLContentPackageLayerReader


func _init(layer_reader: GDSQLContentPackageLayerReader) -> void:
	_layer_reader = layer_reader


func build_effective_database(
		ordered_packages: Array[GDSQLContentPackageSource],
		source_database_name: StringName = DEFAULT_SOURCE_DATABASE,
		effective_database_name: StringName = DEFAULT_EFFECTIVE_DATABASE,
) -> GDSQLContentOverlayResult:
	var result := GDSQLContentOverlayResult.new()
	if _layer_reader == null:
		_add_error(
			result,
			&"GDSQL_CONTENT_LAYER_READER_REQUIRED",
			"Content overlay construction requires a package layer reader.",
		)
		return result
	if ordered_packages.is_empty():
		_add_error(
			result,
			&"GDSQL_CONTENT_PACKAGE_ORDER_REQUIRED",
			"Content overlay construction requires an ordered base package.",
		)
		return result
	if source_database_name == &"" or effective_database_name == &"":
		_add_error(
			result,
			&"GDSQL_CONTENT_DATABASE_NAME_REQUIRED",
			"Source and effective content database names are required.",
		)
		return result
	var layers: Array[GDSQLContentPackageLayer] = []
	for package in ordered_packages:
		var loaded := _layer_reader.read_layer(package, source_database_name)
		result.diagnostics.merge(loaded.diagnostics)
		if loaded.is_successful():
			layers.append(loaded.get_value() as GDSQLContentPackageLayer)
	if not result.is_successful():
		return result
	return _compose(layers, effective_database_name, result)


func _compose(
		layers: Array[GDSQLContentPackageLayer],
		effective_database_name: StringName,
		result: GDSQLContentOverlayResult,
) -> GDSQLContentOverlayResult:
	var definitions: Dictionary[StringName, GDSQLTableDefinition] = { }
	var rows_by_table: Dictionary[StringName, Dictionary] = { }
	var owners_by_table: Dictionary[StringName, Dictionary] = { }
	var schema_owners: Dictionary[StringName, StringName] = { }
	for layer in layers:
		if not _validate_layer(layer, result):
			continue
		for source_table in layer.table_definitions:
			if definitions.has(source_table.name):
				if not _schemas_match(definitions[source_table.name], source_table):
					_add_error(
						result,
						&"GDSQL_CONTENT_SCHEMA_CONFLICT",
						"Package '%s' supplies a schema for table '%s' that conflicts with package '%s'." % [
							layer.source.manifest.package_id,
							source_table.name,
							schema_owners[source_table.name],
						],
					)
				continue
			definitions[source_table.name] = _copy_table(
				source_table,
				effective_database_name,
			)
			rows_by_table[source_table.name] = { }
			owners_by_table[source_table.name] = { }
			schema_owners[source_table.name] = layer.source.manifest.package_id
		if not result.is_successful():
			continue
		for operation in layer.operations:
			_apply_operation(
				layer,
				operation,
				definitions,
				rows_by_table,
				owners_by_table,
				result,
			)
	if not result.is_successful():
		return result
	if definitions.is_empty():
		_add_error(
			result,
			&"GDSQL_CONTENT_DATABASE_EMPTY",
			"The selected package layers do not define any content tables.",
		)
		return result
	var database := GDSQLDatabaseDefinition.new()
	database.name = effective_database_name
	var table_names: Array[StringName] = definitions.keys()
	table_names.sort()
	var snapshot := GDSQLContentDatabaseSnapshot.new(database)
	for table_name in table_names:
		var table := definitions[table_name]
		var table_snapshot := GDSQLTableSnapshot.new()
		table_snapshot.primary_key = table.primary_key
		var identities: Array = rows_by_table[table_name].keys()
		identities.sort_custom(_identity_precedes)
		for identity in identities:
			table_snapshot.rows.append(rows_by_table[table_name][identity].duplicate_record())
		database.tables.append(table)
		snapshot.tables.append(table_snapshot)
	result.set_database(snapshot)
	return result


func _validate_layer(
		layer: GDSQLContentPackageLayer,
		result: GDSQLContentOverlayResult,
) -> bool:
	if layer != null and layer.source != null and layer.source.manifest != null:
		return true
	_add_error(
		result,
		&"GDSQL_CONTENT_LAYER_INVALID",
		"A content package layer is missing its source manifest.",
	)
	return false


func _apply_operation(
		layer: GDSQLContentPackageLayer,
		operation: GDSQLContentRowOperation,
		definitions: Dictionary[StringName, GDSQLTableDefinition],
		rows_by_table: Dictionary[StringName, Dictionary],
		owners_by_table: Dictionary[StringName, Dictionary],
		result: GDSQLContentOverlayResult,
) -> void:
	if operation == null or not definitions.has(operation.table_name):
		_add_error(
			result,
			&"GDSQL_CONTENT_OPERATION_TABLE_UNKNOWN",
			"Package '%s' targets unknown table '%s'." % [
				layer.source.manifest.package_id,
				operation.table_name if operation != null else &"",
			],
		)
		return
	var table := definitions[operation.table_name]
	if operation.identity == null:
		_add_error(
			result,
			&"GDSQL_CONTENT_ROW_ID_REQUIRED",
			"Package '%s' supplies an empty identity for table '%s'." % [
				layer.source.manifest.package_id,
				table.name,
			],
		)
		return
	var rows: Dictionary = rows_by_table[table.name]
	var owners: Dictionary = owners_by_table[table.name]
	if operation.kind == GDSQLContentRowOperation.Kind.REMOVE:
		if not rows.erase(operation.identity):
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_CONTENT_REMOVAL_TARGET_MISSING",
					"Package '%s' removes missing row '%s' from table '%s'." % [
						layer.source.manifest.package_id,
						operation.identity,
						table.name,
					],
					GDSQLQueryDiagnostic.Severity.WARNING,
				),
			)
		else:
			result.add_provenance(_origin(layer, operation))
			owners.erase(operation.identity)
		return
	if operation.kind != GDSQLContentRowOperation.Kind.UPSERT or operation.row == null:
		_add_error(
			result,
			&"GDSQL_CONTENT_ROW_OPERATION_INVALID",
			"Package '%s' supplies an invalid row operation for table '%s'." % [
				layer.source.manifest.package_id,
				table.name,
			],
		)
		return
	if not _validate_row(table, operation, layer, result):
		return
	var origin := _origin(layer, operation)
	if rows.has(operation.identity) and owners.has(operation.identity):
		var previous := owners[operation.identity] as GDSQLContentRowProvenance
		result.add_conflict(
			GDSQLContentRowConflict.new(
				table.name,
				operation.identity,
				previous,
				origin,
			),
		)
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_CONTENT_ROW_OVERRIDE",
				"Package '%s' replaces row '%s' in table '%s' from package '%s'." % [
					origin.package_id,
					operation.identity,
					table.name,
					previous.package_id,
				],
				GDSQLQueryDiagnostic.Severity.INFO,
			),
		)
	rows[operation.identity] = operation.row.duplicate_record()
	owners[operation.identity] = origin
	result.add_provenance(origin)


func _origin(
		layer: GDSQLContentPackageLayer,
		operation: GDSQLContentRowOperation,
) -> GDSQLContentRowProvenance:
	return GDSQLContentRowProvenance.new(
		operation.table_name,
		operation.identity,
		layer.source.manifest.package_id,
		layer.source.manifest.version,
		operation.kind,
	)


func _validate_row(
		table: GDSQLTableDefinition,
		operation: GDSQLContentRowOperation,
		layer: GDSQLContentPackageLayer,
		result: GDSQLContentOverlayResult,
) -> bool:
	var row := operation.row
	if table.primary_key == &"" or not row.has_column(table.primary_key) \
			or row.get_value(table.primary_key) != operation.identity:
		_add_error(
			result,
			&"GDSQL_CONTENT_ROW_ID_INVALID",
			"Package '%s' row identity does not match primary key '%s' in table '%s'." % [
				layer.source.manifest.package_id,
				table.primary_key,
				table.name,
			],
		)
		return false
	for column_name in row.values:
		if not table.has_column(StringName(column_name)):
			_add_error(
				result,
				&"GDSQL_CONTENT_ROW_COLUMN_UNKNOWN",
				"Package '%s' row contains unknown column '%s' in table '%s'." % [
					layer.source.manifest.package_id,
					column_name,
					table.name,
				],
			)
			return false
	for column in table.columns:
		if not row.has_column(column.name):
			if column.nullable:
				continue
			_add_error(
				result,
				&"GDSQL_CONTENT_ROW_COLUMN_REQUIRED",
				"Package '%s' row is missing required column '%s' in table '%s'." % [
					layer.source.manifest.package_id,
					column.name,
					table.name,
				],
			)
			return false
		if not column.accepts_value(row.get_value(column.name)):
			_add_error(
				result,
				&"GDSQL_CONTENT_ROW_COLUMN_TYPE_MISMATCH",
				"Package '%s' column '%s' expects %s." % [
					layer.source.manifest.package_id,
					column.name,
					column.display_type_name(),
				],
			)
			return false
	return true


func _schemas_match(
		left: GDSQLTableDefinition,
		right: GDSQLTableDefinition,
) -> bool:
	if left.primary_key != right.primary_key or left.columns.size() != right.columns.size() \
			or left.indexes.size() != right.indexes.size():
		return false
	for left_column in left.columns:
		var right_column := right.get_column(left_column.name)
		if right_column == null or not _columns_match(left_column, right_column):
			return false
	for left_index in left.indexes:
		var right_index := right.get_index(left_index.name)
		if right_index == null or left_index.columns != right_index.columns \
				or left_index.unique != right_index.unique:
			return false
	return true


func _columns_match(
		left: GDSQLColumnDefinition,
		right: GDSQLColumnDefinition,
) -> bool:
	if left.data_type != right.data_type or left.nullable != right.nullable \
			or left.unique != right.unique or left.auto_increment != right.auto_increment \
			or left.generation != right.generation or left.has_default() != right.has_default():
		return false
	if left.has_default() and left.get_default_value() != right.get_default_value():
		return false
	if left.resource_type == null:
		return right.resource_type == null
	return left.resource_type.is_equivalent_to(right.resource_type)


func _copy_table(
		source: GDSQLTableDefinition,
		database_name: StringName,
) -> GDSQLTableDefinition:
	var copy := GDSQLTableDefinition.new(source.name, source.primary_key)
	copy.database_name = database_name
	for column in source.columns:
		var resource_type: GDSQLResourceTypeConstraint
		if column.resource_type != null:
			resource_type = GDSQLResourceTypeConstraint.from_serialized(
				column.resource_type.resource_class,
				column.resource_type.script_path,
			)
		var column_copy := GDSQLColumnDefinition.new(
			column.name,
			column.data_type,
			column.nullable,
			column.unique,
			column.auto_increment,
			null,
			resource_type,
		)
		column_copy.generation = column.generation
		if column.has_default():
			column_copy.set_default(column.get_default_value())
		copy.add_column(column_copy)
	for index in source.indexes:
		copy.add_index(GDSQLIndexDefinition.new(index.name, index.columns, index.unique))
	return copy


func _identity_precedes(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return typeof(left) < typeof(right)
	if left is int or left is float:
		return left < right
	return String(left) < String(right)


func _add_error(
		result: GDSQLContentOverlayResult,
		code: StringName,
		message: String,
) -> void:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))

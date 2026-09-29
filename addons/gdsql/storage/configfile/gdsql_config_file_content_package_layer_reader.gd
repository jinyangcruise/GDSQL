class_name GDSQLConfigFileContentPackageLayerReader
extends GDSQLContentPackageLayerReader
## Decodes package schemas, rows, and explicit removals from ConfigFile data.

const OVERLAYS_FILE := "overlays.cfg"
const REMOVE_PREFIX := "remove:"


func read_layer(
		source: GDSQLContentPackageSource,
		database_name: StringName,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if source == null or source.manifest == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_CONTENT_PACKAGE_SOURCE_INVALID",
				"A package source with a manifest is required.",
			),
		)
		return result
	var layer := GDSQLContentPackageLayer.new(source, database_name)
	result.value = layer
	var resolver := GDSQLDatabasePathResolver.new(source.get_data_root())
	var codec := GDSQLGodotVariantCodec.new()
	var catalog := GDSQLConfigFileCatalogService.new(resolver, codec)
	var database := catalog.get_database(database_name)
	if database == null:
		if source.manifest.kind == GDSQLContentPackageKind.Kind.BASE_GAME:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_CONTENT_BASE_DATABASE_NOT_FOUND",
					"Base package '%s' does not contain database '%s'." % [
						source.manifest.package_id,
						database_name,
					],
				),
			)
	else:
		_read_database(layer, database, resolver, codec)
	_read_removals(layer, result)
	return result


func _read_database(
		layer: GDSQLContentPackageLayer,
		database: GDSQLDatabaseDefinition,
		resolver: GDSQLDatabasePathResolver,
		codec: GDSQLGodotVariantCodec,
) -> void:
	var storage := GDSQLConfigFileTableStorage.new(
		resolver,
		GDSQLConfigFileCache.new(),
		codec,
	)
	database.tables.sort_custom(
		func(left: GDSQLTableDefinition, right: GDSQLTableDefinition) -> bool:
			return String(left.name) < String(right.name),
	)
	for table in database.tables:
		layer.table_definitions.append(table)
		var snapshot := storage.read_table(table, null)
		for row in snapshot.rows:
			layer.add_upsert(table.name, row.get_value(table.primary_key), row)


func _read_removals(
		layer: GDSQLContentPackageLayer,
		result: GDSQLOperationResult,
) -> void:
	var path := layer.source.package_root.path_join(OVERLAYS_FILE)
	if not FileAccess.file_exists(path):
		return
	var config := ConfigFile.new()
	if config.load(path) != OK:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_CONTENT_OVERLAYS_UNREADABLE",
				"Could not read package overlay operations at '%s'." % path,
			),
		)
		return
	for section in config.get_sections():
		if not section.begins_with(REMOVE_PREFIX):
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_CONTENT_OVERLAY_SECTION_INVALID",
					"Unknown overlay operation section '%s'." % section,
				),
			)
			continue
		var target := section.trim_prefix(REMOVE_PREFIX).split(":", false)
		if target.size() != 2 or StringName(target[0]) != layer.database_name \
				or not String(target[1]).is_valid_identifier():
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_CONTENT_REMOVAL_TARGET_INVALID",
					"Removal section '%s' must target '<database>:<table>'." % section,
				),
			)
			continue
		if not config.has_section_key(section, "ids"):
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_CONTENT_REMOVAL_IDS_REQUIRED",
					"Removal section '%s' requires an ids array." % section,
				),
			)
			continue
		var identities: Variant = config.get_value(section, "ids")
		if not _is_identity_collection(identities):
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_CONTENT_REMOVAL_IDS_INVALID",
					"Removal section '%s' ids must be an Array or packed integer/string array." \
							% section,
				),
			)
			continue
		for identity in identities:
			layer.add_removal(StringName(target[1]), identity)


func _is_identity_collection(value: Variant) -> bool:
	return value is Array or value is PackedStringArray or value is PackedInt32Array \
			or value is PackedInt64Array

class_name GDSQLCatalogChangePlan
extends RefCounted
## Read-only preview data for one validated table catalog operation.
##
## The source fingerprint prevents applying a preview after the table schema
## changed. Alteration intents are treated as immutable after preview.

enum Kind {
	ALTER_TABLE,
	CREATE_TABLE,
	RENAME_TABLE,
	DROP_TABLE,
}

var kind := Kind.ALTER_TABLE
var database_name: StringName
var table_name: StringName
var alterations: Array[GDSQLTableAlteration] = []
var table_definition: GDSQLTableDefinition
var new_table_name: StringName
var source_catalog_fingerprint: int
var affected_rows: int
var destructive: bool
var summaries: Array[String] = []


func _init(
		target_database: StringName = &"",
		target_table: StringName = &"",
		requested_alterations: Array[GDSQLTableAlteration] = [],
		fingerprint: int = 0,
		row_count: int = 0,
) -> void:
	database_name = target_database
	table_name = target_table
	alterations = requested_alterations.duplicate()
	source_catalog_fingerprint = fingerprint
	affected_rows = row_count
	for alteration in alterations:
		if alteration == null:
			continue
		destructive = destructive or alteration.is_destructive()
		summaries.append(alteration.describe())


static func for_create_table(
		target_database: StringName,
		table: GDSQLTableDefinition,
) -> GDSQLCatalogChangePlan:
	var plan := GDSQLCatalogChangePlan.new(
		target_database,
		table.name if table != null else &"",
	)
	plan.kind = Kind.CREATE_TABLE
	plan.table_definition = table
	plan.summaries = ["Create table '%s'." % plan.table_name]
	return plan


static func for_rename_table(
		target_database: StringName,
		current_name: StringName,
		target_name: StringName,
		fingerprint: int,
		row_count: int,
) -> GDSQLCatalogChangePlan:
	var plan := GDSQLCatalogChangePlan.new(
		target_database,
		current_name,
		[],
		fingerprint,
		row_count,
	)
	plan.kind = Kind.RENAME_TABLE
	plan.new_table_name = target_name
	plan.summaries = ["Rename table '%s' to '%s'." % [current_name, target_name]]
	return plan


static func for_drop_table(
		target_database: StringName,
		table_to_drop: StringName,
		fingerprint: int,
		row_count: int,
) -> GDSQLCatalogChangePlan:
	var plan := GDSQLCatalogChangePlan.new(
		target_database,
		table_to_drop,
		[],
		fingerprint,
		row_count,
	)
	plan.kind = Kind.DROP_TABLE
	plan.destructive = true
	plan.summaries = ["Drop table '%s' and its %d row(s)." % [table_to_drop, row_count]]
	return plan


func requires_confirmation() -> bool:
	return destructive

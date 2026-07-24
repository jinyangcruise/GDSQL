class_name GDSQLCatalogChangePlan
extends RefCounted
## Read-only preview data for a validated table alteration request.
##
## The source fingerprint prevents applying a preview after the table schema
## changed. Alteration intents are treated as immutable after preview.

var database_name: StringName
var table_name: StringName
var alterations: Array[GDSQLTableAlteration] = []
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


func requires_confirmation() -> bool:
	return destructive

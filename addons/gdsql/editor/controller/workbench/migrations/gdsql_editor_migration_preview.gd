class_name GDSQLEditorMigrationPreview
extends RefCounted
## Editor handoff for one previewed migration and its authored-history state.

var registration_name: StringName
var migration_stream: StringName
var definition: GDSQLMigrationDefinition
var plan: GDSQLMigrationCatalogPlan
var expected_history_count: int
var definition_persisted: bool


func _init(
		target_registration: StringName = &"",
		stream: StringName = &"",
		migration_definition: GDSQLMigrationDefinition = null,
		migration_plan: GDSQLMigrationCatalogPlan = null,
		history_count: int = 0,
		is_persisted: bool = false,
) -> void:
	registration_name = target_registration
	migration_stream = stream
	definition = migration_definition
	plan = migration_plan
	expected_history_count = history_count
	definition_persisted = is_persisted


func is_valid() -> bool:
	return registration_name != &"" \
			and migration_stream != &"" \
			and definition != null \
			and definition.is_valid() \
			and plan != null \
			and plan.migration == definition \
			and expected_history_count >= 0


func is_destructive() -> bool:
	return plan != null and plan.requires_confirmation()


func affected_rows() -> int:
	return plan.affected_rows() if plan != null else 0


func summaries() -> Array[String]:
	return plan.summaries() if plan != null else []

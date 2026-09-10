class_name GDSQLModelCompatibilityInspectorTest
extends GdUnitTestSuite

func test_compatible_model_matches_table_identity_and_properties() -> void:
	var report := GDSQLModelCompatibilityInspector.new().inspect(
		CompatibleHero,
		_hero_table(),
		GDSQLDatabaseRegistry.CONTENT_ROLE,
	)

	assert_bool(report.is_compatible()).is_true()
	assert_object(report.definition).is_not_null()
	assert_array(report.relationship_summaries).is_empty()


func test_reports_missing_and_incompatible_properties() -> void:
	var report := GDSQLModelCompatibilityInspector.new().inspect(
		StaleHero,
		_hero_table(),
		GDSQLDatabaseRegistry.CONTENT_ROLE,
	)
	var codes := _diagnostic_codes(report)

	assert_bool(report.is_compatible()).is_false()
	assert_array(codes).contains(
		[
			&"GDSQL_MODEL_COMPATIBILITY_TYPE_MISMATCH",
			&"GDSQL_MODEL_COMPATIBILITY_PROPERTY_MISSING",
		],
	)


func test_reports_model_identity_mismatches() -> void:
	var report := GDSQLModelCompatibilityInspector.new().inspect(
		WrongIdentityHero,
		_hero_table(),
		GDSQLDatabaseRegistry.CONTENT_ROLE,
	)
	var codes := _diagnostic_codes(report)

	assert_array(codes).contains(
		[
			&"GDSQL_MODEL_COMPATIBILITY_ROLE_MISMATCH",
			&"GDSQL_MODEL_COMPATIBILITY_TABLE_MISMATCH",
			&"GDSQL_MODEL_COMPATIBILITY_PRIMARY_KEY_MISMATCH",
		],
	)


func test_relationship_summary_exposes_the_related_database_role() -> void:
	var report := GDSQLModelCompatibilityInspector.new().inspect(
		SaveHero,
		_save_hero_table(),
		GDSQLDatabaseRegistry.SAVE_ROLE,
	)

	assert_bool(report.is_compatible()).is_true()
	assert_str(report.relationship_summaries[0]).contains("content.heroes")
	assert_str(report.relationship_summaries[0]).contains("hero_id → id")


func _diagnostic_codes(report: GDSQLModelCompatibilityReport) -> Array[StringName]:
	var codes: Array[StringName] = []
	for diagnostic in report.diagnostics.entries:
		codes.append(diagnostic.code)
	return codes


func _hero_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	table.add_column(GDSQLColumnDefinition.new(&"level", TYPE_INT, false))
	return table


func _save_hero_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"hero_state", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false))
	table.add_column(GDSQLColumnDefinition.new(&"hero_id", TYPE_INT, false))
	return table


class CompatibleHero extends GDSQLContentModel:
	var id: int
	var name: String
	var level: int


	func table_name() -> StringName:
		return &"heroes"


class StaleHero extends GDSQLContentModel:
	var id: int
	var name: int


	func table_name() -> StringName:
		return &"heroes"


class WrongIdentityHero extends GDSQLSaveModel:
	var id: int
	var name: String
	var level: int


	func table_name() -> StringName:
		return &"characters"


	func primary_key() -> StringName:
		return &"uuid"


class SaveHero extends GDSQLSaveModel:
	var id: int
	var hero_id: int


	func table_name() -> StringName:
		return &"hero_state"


	func relationships() -> Array[GDSQLRelationshipDefinition]:
		return [
			GDSQLRelationshipDefinition.belongs_to(
				&"definition",
				CompatibleHero,
				&"hero_id",
			),
		]

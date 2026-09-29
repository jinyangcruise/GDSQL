class_name GDSQLModelCompatibilityInspectorTest
extends GdUnitTestSuite

func test_compatible_model_matches_role_and_properties_without_instantiation() -> void:
	var report := GDSQLModelCompatibilityInspector.new().inspect(
		CompatibleHero,
		_hero_table(),
		GDSQLDatabaseRegistry.CONTENT_ROLE,
	)

	assert_bool(report.is_compatible()).is_true()


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


func test_reports_role_inheritance_mismatch() -> void:
	var report := GDSQLModelCompatibilityInspector.new().inspect(
		WrongIdentityHero,
		_hero_table(),
		GDSQLDatabaseRegistry.CONTENT_ROLE,
	)
	var codes := _diagnostic_codes(report)

	assert_array(codes).contains(
		[&"GDSQL_MODEL_COMPATIBILITY_ROLE_MISMATCH"],
	)


func test_does_not_execute_user_relationship_declarations() -> void:
	var report := GDSQLModelCompatibilityInspector.new().inspect(
		RelationshipDeclarationIsRuntimeOnly,
		_hero_table(),
		GDSQLDatabaseRegistry.CONTENT_ROLE,
	)

	assert_bool(report.is_compatible()).is_true()


func test_reports_a_specific_error_when_the_script_is_unavailable() -> void:
	var report := GDSQLModelCompatibilityInspector.new().inspect(
		null,
		_hero_table(),
		GDSQLDatabaseRegistry.CONTENT_ROLE,
	)

	assert_bool(report.is_compatible()).is_false()
	assert_array(_diagnostic_codes(report)).contains(
		[&"GDSQL_MODEL_COMPATIBILITY_SCRIPT_UNAVAILABLE"],
	)


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


class RelationshipDeclarationIsRuntimeOnly extends GDSQLContentModel:
	var id: int
	var name: String
	var level: int


	func table_name() -> StringName:
		return &"heroes"


	func relationships() -> Array[GDSQLRelationshipDefinition]:
		assert(false, "Editor compatibility must not execute user model methods.")
		return []

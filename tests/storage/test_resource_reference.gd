class_name GDSQLResourceReferenceTest
extends GdUnitTestSuite

const REFERENCED_ICON_PATH := "res://addons/gdsql/editor/workspace/icons/key.svg"


class CountingResolver:
	extends GDSQLResourceResolver

	var calls := 0
	var resolved_resource: Resource


	func _init(resource: Resource) -> void:
		resolved_resource = resource


	func resolve(_reference: GDSQLResourceReference) -> GDSQLOperationResult:
		calls += 1
		var result := GDSQLOperationResult.new()
		result.value = resolved_resource
		return result


func test_reference_decoding_does_not_materialize_the_asset() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var resolver := CountingResolver.new(icon)
	var codec := GDSQLGodotVariantCodec.new(resolver)
	var column := _referenced_column(icon)
	var encoded: Variant = codec.encode(icon, column)

	var reference := codec.decode_reference(encoded)

	assert_object(reference).is_not_null()
	assert_str(reference.fallback_path).is_equal(REFERENCED_ICON_PATH)
	assert_int(resolver.calls).is_zero()


func test_compatibility_decoding_materializes_through_injected_resolver() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var resolver := CountingResolver.new(icon)
	var codec := GDSQLGodotVariantCodec.new(resolver)
	var column := _referenced_column(icon)
	var encoded: Variant = codec.encode(icon, column)

	var decoded: Variant = codec.decode(encoded, column)

	assert_object(decoded).is_same(icon)
	assert_int(resolver.calls).is_equal(1)


func test_missing_reference_returns_a_structured_diagnostic() -> void:
	var reference := GDSQLResourceReference.new()
	reference.fallback_path = "res://missing/gdsql-resource-stage-a.tres"

	var result := GDSQLGodotResourceResolver.new().resolve(reference)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)) \
			.is_equal("GDSQL_RESOURCE_REFERENCE_MISSING")
	assert_object(result.diagnostics.entries[0].related_object).is_same(reference)


func _referenced_column(prototype: Resource) -> GDSQLColumnDefinition:
	var column := GDSQLColumnDefinition.new(&"icon", TYPE_OBJECT, false)
	column.resource_type = GDSQLResourceTypeConstraint.from_resource(prototype)
	column.resource_ownership = GDSQLResourceOwnership.Mode.REFERENCED
	return column

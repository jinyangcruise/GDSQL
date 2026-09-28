class_name GDSQLGodotVariantCodec
extends RefCounted

const ENCODED_TYPE_KEY := "__gdsql_encoded_type__"
const NULL_TYPE := "null"
const RESOURCE_REFERENCE_TYPE := "resource_reference"
const RESOURCE_LOCATOR_KEY := "locator"

var _resource_resolver: GDSQLResourceResolver


func _init(resource_resolver: GDSQLResourceResolver = null) -> void:
	_resource_resolver = (
		resource_resolver
		if resource_resolver != null
		else GDSQLGodotResourceResolver.new()
	)


func encode(value: Variant, column: GDSQLColumnDefinition = null) -> Variant:
	if value == null:
		return { ENCODED_TYPE_KEY: NULL_TYPE }
	if value is GDSQLResourceReference and column != null \
			and column.resource_ownership == GDSQLResourceOwnership.Mode.REFERENCED:
		return {
			ENCODED_TYPE_KEY: RESOURCE_REFERENCE_TYPE,
			RESOURCE_LOCATOR_KEY: (value as GDSQLResourceReference).to_dictionary(),
		}
	if value is Resource and column != null \
			and column.resource_ownership == GDSQLResourceOwnership.Mode.REFERENCED:
		var reference := GDSQLResourceReference.from_resource(value, column.resource_type)
		if reference == null:
			return { ENCODED_TYPE_KEY: NULL_TYPE }
		return {
			ENCODED_TYPE_KEY: RESOURCE_REFERENCE_TYPE,
			RESOURCE_LOCATOR_KEY: reference.to_dictionary(),
		}
	if value is Resource:
		return value.duplicate(true)
	return value


func decode(value: Variant, column: GDSQLColumnDefinition = null) -> Variant:
	if value is Dictionary \
			and value.size() == 1 \
			and value.get(ENCODED_TYPE_KEY) == NULL_TYPE:
		return null
	if value is Dictionary and value.get(ENCODED_TYPE_KEY) == RESOURCE_REFERENCE_TYPE \
			and value.get(RESOURCE_LOCATOR_KEY) is Dictionary:
		var reference := decode_reference(value)
		if reference == null:
			return null
		var resolution := _resource_resolver.resolve(reference)
		var resource := resolution.get_value() as Resource if resolution.is_successful() else null
		if resource != null and column != null and not column.accepts_value(resource):
			return null
		return resource
	return value


func decode_reference(value: Variant) -> GDSQLResourceReference:
	if not value is Dictionary \
			or value.get(ENCODED_TYPE_KEY) != RESOURCE_REFERENCE_TYPE \
			or not value.get(RESOURCE_LOCATOR_KEY) is Dictionary:
		return null
	return GDSQLResourceReference.from_dictionary(value.get(RESOURCE_LOCATOR_KEY))


func can_encode(value: Variant, column: GDSQLColumnDefinition) -> bool:
	if value == null or column == null:
		return true
	if value is GDSQLResourceReference:
		return column.resource_ownership == GDSQLResourceOwnership.Mode.REFERENCED \
				and (value as GDSQLResourceReference).is_valid()
	if not value is Resource \
			or column.resource_ownership == GDSQLResourceOwnership.Mode.OWNED:
		return true
	return GDSQLResourceReference.from_resource(value, column.resource_type) != null

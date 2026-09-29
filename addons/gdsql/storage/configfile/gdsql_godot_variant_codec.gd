class_name GDSQLGodotVariantCodec
extends RefCounted

const ENCODED_TYPE_KEY := "__gdsql_encoded_type__"
const NULL_TYPE := "null"
const RESOURCE_REFERENCE_TYPE := "resource_reference"
const RESOURCE_LOCATOR_KEY := "locator"


func encode(value: Variant, column: GDSQLColumnDefinition = null) -> Variant:
	if value == null:
		return { ENCODED_TYPE_KEY: NULL_TYPE }
	if value is Resource and column != null \
			and column.resource_ownership == GDSQLResourceOwnership.Mode.REFERENCED:
		var locator := GDSQLResourceLocator.from_resource(value, column.resource_type)
		if locator == null:
			return { ENCODED_TYPE_KEY: NULL_TYPE }
		return {
			ENCODED_TYPE_KEY: RESOURCE_REFERENCE_TYPE,
			RESOURCE_LOCATOR_KEY: locator.to_dictionary(),
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
		var locator := GDSQLResourceLocator.from_dictionary(value.get(RESOURCE_LOCATOR_KEY))
		var resource := locator.resolve() if locator != null else null
		if resource != null and column != null and not column.accepts_value(resource):
			return null
		return resource
	return value


func can_encode(value: Variant, column: GDSQLColumnDefinition) -> bool:
	if value == null or not value is Resource or column == null \
			or column.resource_ownership == GDSQLResourceOwnership.Mode.OWNED:
		return true
	return GDSQLResourceLocator.from_resource(value, column.resource_type) != null

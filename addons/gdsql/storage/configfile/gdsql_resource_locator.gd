class_name GDSQLResourceLocator
extends RefCounted
## Versioned locator for a Resource that is owned outside table storage.

const FORMAT_VERSION := 1
const PROJECT_SCOPE := &"project"
const PACKAGE_SCOPE := &"package"
const EXTERNAL_SCOPE := &"external"

var scope := PROJECT_SCOPE
var uid := ""
var fallback_path := ""
var expected_type := &"Resource"


static func from_resource(
		resource: Resource,
		resource_type: GDSQLResourceTypeConstraint,
) -> GDSQLResourceLocator:
	if resource == null or resource.resource_path.is_empty():
		return null
	var locator := GDSQLResourceLocator.new()
	locator.fallback_path = resource.resource_path
	locator.scope = (
		PROJECT_SCOPE
		if locator.fallback_path.begins_with("res://")
		else EXTERNAL_SCOPE
	)
	locator.expected_type = (
			resource_type.picker_base_type()
			if resource_type != null and resource_type.is_valid()
			else &"Resource"
	)
	var resource_uid := ResourceLoader.get_resource_uid(locator.fallback_path)
	if resource_uid != ResourceUID.INVALID_ID:
		locator.uid = ResourceUID.id_to_text(resource_uid)
	return locator


static func from_dictionary(data: Dictionary) -> GDSQLResourceLocator:
	if int(data.get("version", 0)) != FORMAT_VERSION:
		return null
	var locator := GDSQLResourceLocator.new()
	locator.scope = StringName(data.get("scope", ""))
	locator.uid = String(data.get("uid", ""))
	locator.fallback_path = String(data.get("path", ""))
	locator.expected_type = StringName(data.get("expected_type", "Resource"))
	return locator if locator.is_valid() else null


func is_valid() -> bool:
	return scope in [PROJECT_SCOPE, PACKAGE_SCOPE, EXTERNAL_SCOPE] \
			and (not uid.is_empty() or not fallback_path.is_empty())


func to_dictionary() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"scope": String(scope),
		"uid": uid,
		"path": fallback_path,
		"expected_type": String(expected_type),
	}


func resolve() -> Resource:
	var path := ""
	if not uid.is_empty():
		var resource_uid := ResourceUID.text_to_id(uid)
		if resource_uid != ResourceUID.INVALID_ID and ResourceUID.has_id(resource_uid):
			path = ResourceUID.get_id_path(resource_uid)
	if path.is_empty():
		path = fallback_path
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path)

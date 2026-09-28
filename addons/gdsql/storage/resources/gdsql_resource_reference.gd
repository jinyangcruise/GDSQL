class_name GDSQLResourceReference
extends RefCounted
## Storage-neutral identity for a Resource owned outside table storage.
##
## This value never loads the referenced asset. Backends may encode it
## differently while preserving its scope, UID, fallback path, and expected
## Resource type.

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
) -> GDSQLResourceReference:
	if resource == null or resource.resource_path.is_empty():
		return null
	var reference := GDSQLResourceReference.new()
	reference.fallback_path = resource.resource_path
	reference.scope = (
		PROJECT_SCOPE
		if reference.fallback_path.begins_with("res://")
		else EXTERNAL_SCOPE
	)
	reference.expected_type = (
		resource_type.picker_base_type()
		if resource_type != null and resource_type.is_valid()
		else &"Resource"
	)
	var resource_uid := ResourceLoader.get_resource_uid(reference.fallback_path)
	if resource_uid != ResourceUID.INVALID_ID:
		reference.uid = ResourceUID.id_to_text(resource_uid)
	return reference


static func from_dictionary(data: Dictionary) -> GDSQLResourceReference:
	if int(data.get("version", 0)) != FORMAT_VERSION:
		return null
	var reference := GDSQLResourceReference.new()
	reference.scope = StringName(data.get("scope", ""))
	reference.uid = String(data.get("uid", ""))
	reference.fallback_path = String(data.get("path", ""))
	reference.expected_type = StringName(data.get("expected_type", "Resource"))
	return reference if reference.is_valid() else null


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

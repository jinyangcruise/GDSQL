class_name GDSQLEditorContentPreviewService
extends RefCounted
## Resolves content models for editor previews without exposing mutation APIs.

var _models: GDSQLModelContext


func _init(model_context: GDSQLModelContext) -> void:
	assert(model_context != null)
	_models = model_context


func load(model_script: Script, identifier_text: String) -> GDSQLOperationResult:
	if model_script == null or not model_script.can_instantiate():
		return _failure(
			&"GDSQL_CONTENT_PREVIEW_MODEL_REQUIRED",
			"Choose a content model script that can be instantiated.",
		)
	var candidate: Variant = model_script.new()
	if not candidate is GDSQLContentModel:
		return _failure(
			&"GDSQL_CONTENT_PREVIEW_CONTENT_MODEL_REQUIRED",
			"Editor previews only accept models that extend GDSQLContentModel.",
		)
	var registered := _models.register_model(model_script)
	if not registered.is_successful():
		return registered
	var definition := registered.get_value() as GDSQLModelDefinition
	var identifier := _parse_identifier(candidate as GDSQLModel, definition, identifier_text)
	if not identifier.is_successful():
		return identifier
	var found := _models.find(model_script, identifier.get_value())
	if not found.is_successful():
		return found
	if found.get_value() == null:
		return _failure(
			&"GDSQL_CONTENT_PREVIEW_ROW_NOT_FOUND",
			"No '%s' content row uses identifier '%s'." % [
				definition.table_name,
				identifier_text,
			],
		)
	return found


func _parse_identifier(
		model: GDSQLModel,
		definition: GDSQLModelDefinition,
		identifier_text: String,
) -> GDSQLOperationResult:
	if identifier_text.is_empty():
		return _failure(
			&"GDSQL_CONTENT_PREVIEW_IDENTIFIER_REQUIRED",
			"Enter the content row's stable identifier.",
		)
	var property_type := TYPE_NIL
	for property in model.get_property_list():
		if StringName(property.get("name", "")) == definition.primary_key:
			property_type = property.get("type", TYPE_NIL) as Variant.Type
			break
	var result := GDSQLOperationResult.new()
	match property_type:
		TYPE_INT:
			if not identifier_text.is_valid_int():
				return _failure(
					&"GDSQL_CONTENT_PREVIEW_IDENTIFIER_INVALID",
					"Identifier '%s' must be an integer." % identifier_text,
				)
			result.value = identifier_text.to_int()
		TYPE_STRING:
			result.value = identifier_text
		TYPE_STRING_NAME:
			result.value = StringName(identifier_text)
		_:
			return _failure(
				&"GDSQL_CONTENT_PREVIEW_IDENTIFIER_TYPE_UNSUPPORTED",
				"Content preview identifiers currently support int, String, and StringName primary keys.",
			)
	return result


func _failure(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result

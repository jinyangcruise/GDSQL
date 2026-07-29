class_name GDSQLContextActionHub
extends RefCounted
## Owns action behavior and availability for one editor context.

signal actions_changed

var context_id: StringName
var _definitions: Dictionary[StringName, GDSQLEditorActionDefinition] = { }
var _handlers: Dictionary[StringName, Callable] = { }
var _enabled: Dictionary[StringName, bool] = { }
var _visible: Dictionary[StringName, bool] = { }


func _init(id: StringName = &"") -> void:
	context_id = id


func add_action(
		definition: GDSQLEditorActionDefinition,
		handler: Callable,
) -> GDSQLOperationResult:
	if definition == null or definition.id == &"":
		return _error(
			&"GDSQL_EDITOR_ACTION_DEFINITION_REQUIRED",
			"An editor action requires a definition with a stable identifier.",
		)
	if not handler.is_valid():
		return _error(
			&"GDSQL_EDITOR_ACTION_HANDLER_REQUIRED",
			"Editor action '%s' requires a valid handler." % definition.id,
		)
	if _definitions.has(definition.id):
		return _error(
			&"GDSQL_EDITOR_ACTION_ALREADY_REGISTERED",
			"Editor action '%s' is already registered in context '%s'." \
					% [definition.id, context_id],
		)
	_definitions[definition.id] = definition
	_handlers[definition.id] = handler
	_enabled[definition.id] = true
	_visible[definition.id] = true
	actions_changed.emit()
	var result := GDSQLOperationResult.new()
	result.value = definition
	return result


func has_action(action_id: StringName) -> bool:
	return _definitions.has(action_id)


func get_action(action_id: StringName) -> GDSQLEditorActionDefinition:
	return _definitions.get(action_id)


func get_actions() -> Array[GDSQLEditorActionDefinition]:
	var actions: Array[GDSQLEditorActionDefinition] = []
	for definition in _definitions.values():
		actions.append(definition)
	actions.sort_custom(
		func(
				left: GDSQLEditorActionDefinition,
				right: GDSQLEditorActionDefinition,
		) -> bool:
			if left.group == right.group:
				return left.order < right.order
			return String(left.group) < String(right.group),
	)
	return actions


func set_action_enabled(action_id: StringName, enabled: bool) -> void:
	if not has_action(action_id) or is_action_enabled(action_id) == enabled:
		return
	_enabled[action_id] = enabled
	actions_changed.emit()


func is_action_enabled(action_id: StringName) -> bool:
	return bool(_enabled.get(action_id, false))


func set_action_visible(action_id: StringName, visible: bool) -> void:
	if not has_action(action_id) or is_action_visible(action_id) == visible:
		return
	_visible[action_id] = visible
	actions_changed.emit()


func is_action_visible(action_id: StringName) -> bool:
	return bool(_visible.get(action_id, false))


func invoke(
		action_id: StringName,
		arguments: Array = [],
) -> GDSQLOperationResult:
	if not has_action(action_id):
		return _error(
			&"GDSQL_EDITOR_ACTION_NOT_FOUND",
			"Editor action '%s' is not registered in context '%s'." \
					% [action_id, context_id],
		)
	if not is_action_visible(action_id) or not is_action_enabled(action_id):
		return _error(
			&"GDSQL_EDITOR_ACTION_UNAVAILABLE",
			"Editor action '%s' is unavailable in context '%s'." \
					% [action_id, context_id],
		)
	var handler: Callable = _handlers[action_id]
	var value: Variant = handler.callv(arguments)
	if value is GDSQLOperationResult:
		return value
	var result := GDSQLOperationResult.new()
	result.value = value
	return result


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result

class_name GDSQLEditorActionHub
extends RefCounted
## Routes stable editor actions to the context that owns their behavior.
##
## Global actions remain available for every editor surface. The active
## context can contribute or override actions while a document has focus.

signal actions_changed
signal action_invoked(
		action_id: StringName,
		result: GDSQLOperationResult,
)

const GLOBAL_CONTEXT := &"global"

var active_context_id: StringName = GLOBAL_CONTEXT

var _contexts: Dictionary[StringName, GDSQLContextActionHub] = { }


func register_context(context: GDSQLContextActionHub) -> GDSQLOperationResult:
	if context == null or context.context_id == &"":
		return _error(
			&"GDSQL_EDITOR_ACTION_CONTEXT_REQUIRED",
			"An editor action context requires a stable identifier.",
		)
	if _contexts.has(context.context_id):
		return _error(
			&"GDSQL_EDITOR_ACTION_CONTEXT_ALREADY_REGISTERED",
			"Editor action context '%s' is already registered." \
					% context.context_id,
		)
	_contexts[context.context_id] = context
	context.actions_changed.connect(_on_context_actions_changed)
	actions_changed.emit()
	var result := GDSQLOperationResult.new()
	result.value = context
	return result


func unregister_context(context_id: StringName) -> void:
	var context := _contexts.get(context_id) as GDSQLContextActionHub
	if context == null:
		return
	if context.actions_changed.is_connected(_on_context_actions_changed):
		context.actions_changed.disconnect(_on_context_actions_changed)
	_contexts.erase(context_id)
	if active_context_id == context_id:
		active_context_id = GLOBAL_CONTEXT
	actions_changed.emit()


func set_active_context(context_id: StringName) -> GDSQLOperationResult:
	if not _contexts.has(context_id):
		return _error(
			&"GDSQL_EDITOR_ACTION_CONTEXT_NOT_FOUND",
			"Editor action context '%s' is not registered." % context_id,
		)
	active_context_id = context_id
	actions_changed.emit()
	var result := GDSQLOperationResult.new()
	result.value = _contexts[context_id]
	return result


func get_action(action_id: StringName) -> GDSQLEditorActionDefinition:
	var active := _contexts.get(active_context_id) as GDSQLContextActionHub
	if active != null and active.has_action(action_id):
		return active.get_action(action_id)
	var global := _contexts.get(GLOBAL_CONTEXT) as GDSQLContextActionHub
	if global != null:
		return global.get_action(action_id)
	return null


func get_actions() -> Array[GDSQLEditorActionDefinition]:
	var actions: Array[GDSQLEditorActionDefinition] = []
	var seen: Dictionary[StringName, bool] = { }
	var global := _contexts.get(GLOBAL_CONTEXT) as GDSQLContextActionHub
	if global != null:
		for definition in global.get_actions():
			actions.append(definition)
			seen[definition.id] = true
	var active := _contexts.get(active_context_id) as GDSQLContextActionHub
	if active != null and active != global:
		for definition in active.get_actions():
			if seen.has(definition.id):
				for index in range(actions.size()):
					if actions[index].id == definition.id:
						actions[index] = definition
						break
			else:
				actions.append(definition)
	return actions


func is_action_enabled(action_id: StringName) -> bool:
	var context := _resolve_context(action_id)
	return context != null and context.is_action_enabled(action_id)


func is_action_visible(action_id: StringName) -> bool:
	var context := _resolve_context(action_id)
	return context != null and context.is_action_visible(action_id)


func invoke(
		action_id: StringName,
		arguments: Array = [],
) -> GDSQLOperationResult:
	var context := _resolve_context(action_id)
	var result: GDSQLOperationResult
	if context == null:
		result = _error(
			&"GDSQL_EDITOR_ACTION_NOT_FOUND",
			"Editor action '%s' is not available in the active context." \
					% action_id,
		)
	else:
		result = context.invoke(action_id, arguments)
	action_invoked.emit(action_id, result)
	return result


func _resolve_context(action_id: StringName) -> GDSQLContextActionHub:
	var active := _contexts.get(active_context_id) as GDSQLContextActionHub
	if active != null and active.has_action(action_id):
		return active
	var global := _contexts.get(GLOBAL_CONTEXT) as GDSQLContextActionHub
	if global != null and global.has_action(action_id):
		return global
	return null


func _on_context_actions_changed() -> void:
	actions_changed.emit()


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result

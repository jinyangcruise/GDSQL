class_name GDSQLEditorActionRegistrar
extends RefCounted
## Registers stable GDSQL action metadata with supplied behavior handlers.

func register_global_actions(
		action_hub: GDSQLEditorActionHub,
		handlers: Dictionary[StringName, Callable],
) -> GDSQLOperationResult:
	if action_hub == null:
		return _error(
			&"GDSQL_EDITOR_ACTION_HUB_REQUIRED",
			"Global editor actions require an action hub.",
		)
	var context := GDSQLContextActionHub.new(
		GDSQLEditorActionHub.GLOBAL_CONTEXT,
	)
	var registered := action_hub.register_context(context)
	if not registered.is_successful():
		return registered

	var result := GDSQLOperationResult.new()
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.CREATE_DATABASE,
		"Create Database",
		"Create a database under a selected data root.",
		&"Add",
		0,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.CREATE_TABLE,
		"Create Table",
		"Create a table in the active database.",
		&"Add",
		5,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.REMOVE_REGISTRATION,
		"Remove Database",
		"Forget a database registration while leaving its files unchanged.",
		&"Remove",
		6,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.DROP_TABLE,
		"Delete Table",
		"Delete a table and its stored rows.",
		&"Remove",
		8,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.DISCOVER_PROJECT,
		"Discover Project",
		"Discover databases under res://data.",
		&"Folder",
		10,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.REFRESH_DATABASES,
		"Refresh",
		"Refresh registered database metadata.",
		&"Reload",
		20,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.OPEN_REGISTRATION,
		"Open Database",
		"Open the selected database registration.",
		&"Database",
		30,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.SELECT_TABLE,
		"Open Table",
		"Select a table in the active database.",
		&"ListSelect",
		40,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.SHOW_WELCOME,
		"Welcome",
		"Show the GDSQL welcome page.",
		&"Home",
		50,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.SHOW_SAVE_SLOTS,
		"Save Slots",
		"Create, inspect, and select the active save slot.",
		&"Save",
		55,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.CREATE_SAVE_SLOT,
		"New Save Slot",
		"Create a writable save database with recommended defaults.",
		&"Add",
		56,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.SELECT_SAVE_SLOT,
		"Use Save Slot",
		"Bind a registered database as the active save role.",
		&"Favorites",
		57,
		result,
	)
	_register(
		context,
		handlers,
		GDSQLEditorActionIds.DELETE_SAVE_SLOT,
		"Delete Save Slot Data",
		"Permanently delete one validated standard save-slot database.",
		&"Remove",
		58,
		result,
	)
	result.value = context
	return result


func _register(
		context: GDSQLContextActionHub,
		handlers: Dictionary[StringName, Callable],
		action_id: StringName,
		label: String,
		tooltip: String,
		icon_name: StringName,
		order: int,
		result: GDSQLOperationResult,
) -> void:
	var handler: Callable = handlers.get(action_id, Callable())
	if not handler.is_valid():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_EDITOR_ACTION_HANDLER_REQUIRED",
				"Editor action '%s' requires a valid handler." % action_id,
			),
		)
		return
	var added := context.add_action(
		GDSQLEditorActionDefinition.new(
			action_id,
			label,
			tooltip,
			icon_name,
			&"database",
			order,
		),
		handler,
	)
	result.diagnostics.merge(added.diagnostics)


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result

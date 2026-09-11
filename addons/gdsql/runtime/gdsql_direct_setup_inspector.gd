class_name GDSQLDirectSetupInspector
extends RefCounted
## Evaluates the supported content + active-save profile without accessing files.

const CONTENT_DATABASE := &"content_database"
const CONTENT_TABLE := &"content_table"
const CONTENT_ROW := &"content_row"
const ACTIVE_SAVE := &"active_save"
const MODEL_BINDING := &"model_binding"
const RUNTIME_ADAPTER := &"runtime_adapter"


static func inspect_runtime(
		snapshot: GDSQLDatabaseRegistrySnapshot,
) -> GDSQLDirectSetupReport:
	return _inspect(snapshot, [], false, 0, false)


static func inspect_editor(
		snapshot: GDSQLDatabaseRegistrySnapshot,
		inspections: Array[GDSQLDatabaseInspection],
		model_count: int,
		runtime_adapter_configured: bool,
) -> GDSQLDirectSetupReport:
	return _inspect(
		snapshot,
		inspections,
		true,
		model_count,
		runtime_adapter_configured,
	)


static func _inspect(
		snapshot: GDSQLDatabaseRegistrySnapshot,
		inspections: Array[GDSQLDatabaseInspection],
		include_editor_checks: bool,
		model_count: int,
		runtime_adapter_configured: bool,
) -> GDSQLDirectSetupReport:
	var report := GDSQLDirectSetupReport.new()
	var content := _registration_for_role(snapshot, GDSQLDatabaseRegistry.CONTENT_ROLE)
	var content_inspection := _inspection_for(content, inspections)
	report.add_check(_content_database_check(snapshot, content, content_inspection, include_editor_checks))
	if include_editor_checks:
		report.add_check(_content_table_check(content_inspection))
		report.add_check(_content_row_check(content_inspection))
	var save := _registration_for_role(snapshot, GDSQLDatabaseRegistry.SAVE_ROLE)
	var save_inspection := _inspection_for(save, inspections)
	report.add_check(_active_save_check(snapshot, save, save_inspection, include_editor_checks))
	if include_editor_checks:
		report.add_check(
			GDSQLDirectSetupCheck.new(
				MODEL_BINDING,
				"Model binding",
				model_count > 0,
				(
						"%d user-owned model binding(s) found." % model_count
						if model_count > 0
						else "Open a content table and use Model to generate its first typed binding."
				),
				GDSQLDirectSetupCheck.ACTION_OPEN_CONTENT_TABLE,
			),
		)
		report.add_check(
			GDSQLDirectSetupCheck.new(
				RUNTIME_ADAPTER,
				"Runtime adapter",
				runtime_adapter_configured,
				(
						"GDSQLRuntime is installed as the project autoload."
						if runtime_adapter_configured
						else "Install gdsql_runtime_node.tscn as the GDSQLRuntime autoload."
				),
				GDSQLDirectSetupCheck.ACTION_INSTALL_RUNTIME,
			),
		)
	return report


static func _content_database_check(
		snapshot: GDSQLDatabaseRegistrySnapshot,
		registration: GDSQLDatabaseRegistration,
		inspection: GDSQLDatabaseInspection,
		require_catalog: bool,
) -> GDSQLDirectSetupCheck:
	var issue := _role_issue(snapshot, GDSQLDatabaseRegistry.CONTENT_ROLE, registration)
	if issue.is_empty() and not registration.data_root.begins_with("res://"):
		issue = "Content role should use an authored res:// data root."
	if issue.is_empty() and require_catalog and (inspection == null or not inspection.catalog_exists):
		issue = "The content registration does not contain a readable database catalog."
	return GDSQLDirectSetupCheck.new(
		CONTENT_DATABASE,
		"Content database",
		issue.is_empty(),
		(
				"Content role resolves to '%s' under %s." % [
					registration.database_name,
					registration.data_root,
				]
				if issue.is_empty()
				else issue
		),
		GDSQLDirectSetupCheck.ACTION_CREATE_DATABASE,
	)


static func _active_save_check(
		snapshot: GDSQLDatabaseRegistrySnapshot,
		registration: GDSQLDatabaseRegistration,
		inspection: GDSQLDatabaseInspection,
		require_catalog: bool,
) -> GDSQLDirectSetupCheck:
	var issue := _role_issue(snapshot, GDSQLDatabaseRegistry.SAVE_ROLE, registration)
	if issue.is_empty() and not registration.data_root.begins_with("user://"):
		issue = "Save role should use a writable user:// data root."
	if issue.is_empty() and require_catalog and (inspection == null or not inspection.catalog_exists):
		issue = "The active save registration does not contain a readable database catalog."
	return GDSQLDirectSetupCheck.new(
		ACTIVE_SAVE,
		"Active save",
		issue.is_empty(),
		(
				"Save role resolves to '%s' under %s." % [
					registration.database_name,
					registration.data_root,
				]
				if issue.is_empty()
				else issue
		),
		GDSQLDirectSetupCheck.ACTION_MANAGE_SAVE_SLOTS,
	)


static func _content_table_check(
		inspection: GDSQLDatabaseInspection,
) -> GDSQLDirectSetupCheck:
	var ready_tables := _ready_tables(inspection)
	return GDSQLDirectSetupCheck.new(
		CONTENT_TABLE,
		"First table",
		not ready_tables.is_empty(),
		(
				"%d content table(s) have schema and storage." % ready_tables.size()
				if not ready_tables.is_empty()
				else "Open the content database, then add and save its first table."
		),
		GDSQLDirectSetupCheck.ACTION_OPEN_CONTENT_DATABASE,
	)


static func _content_row_check(
		inspection: GDSQLDatabaseInspection,
) -> GDSQLDirectSetupCheck:
	var rows := 0
	for table in _ready_tables(inspection):
		rows += table.row_count
	return GDSQLDirectSetupCheck.new(
		CONTENT_ROW,
		"First content row",
		rows > 0,
		(
				"The content database contains %d stored row(s)." % rows
				if rows > 0
				else "Open a content table and add its first row."
		),
		GDSQLDirectSetupCheck.ACTION_OPEN_CONTENT_TABLE,
	)


static func _role_issue(
		snapshot: GDSQLDatabaseRegistrySnapshot,
		role: StringName,
		registration: GDSQLDatabaseRegistration,
) -> String:
	if snapshot == null:
		return "Database registry metadata is unavailable."
	var selected_name := _registration_name_for_role(snapshot, role)
	if selected_name == &"":
		return "Database role '%s' has no active binding." % role
	if registration == null:
		return "Database role '%s' points to missing registration '%s'." % [
			role,
			selected_name,
		]
	if registration.database_name == &"" or registration.data_root.is_empty():
		return "Registration '%s' is missing its database name or data root." % registration.name
	if not GDSQLStorageBackendIds.is_implemented(registration.storage_backend_id):
		return "Registration '%s' uses unavailable storage backend '%s'." % [
			registration.name,
			registration.storage_backend_id,
		]
	return ""


static func _registration_for_role(
		snapshot: GDSQLDatabaseRegistrySnapshot,
		role: StringName,
) -> GDSQLDatabaseRegistration:
	if snapshot == null:
		return null
	var selected_name := _registration_name_for_role(snapshot, role)
	for registration in snapshot.registrations:
		if registration.name == selected_name:
			return registration
	return null


static func _registration_name_for_role(
		snapshot: GDSQLDatabaseRegistrySnapshot,
		role: StringName,
) -> StringName:
	var selected_name := &""
	for binding in snapshot.role_bindings:
		if binding.role == role:
			selected_name = binding.registration_name
	return selected_name


static func _inspection_for(
		registration: GDSQLDatabaseRegistration,
		inspections: Array[GDSQLDatabaseInspection],
) -> GDSQLDatabaseInspection:
	if registration == null:
		return null
	for inspection in inspections:
		if inspection.registration != null and inspection.registration.name == registration.name:
			return inspection
	return null


static func _ready_tables(
		inspection: GDSQLDatabaseInspection,
) -> Array[GDSQLTableInspection]:
	var tables: Array[GDSQLTableInspection] = []
	if inspection == null:
		return tables
	for table in inspection.tables:
		if table.schema_exists and table.storage_exists:
			tables.append(table)
	return tables

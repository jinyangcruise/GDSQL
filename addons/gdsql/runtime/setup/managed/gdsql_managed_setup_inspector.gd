class_name GDSQLManagedSetupInspector
extends RefCounted
## Evaluates managed setup state supplied by editor/runtime composition roots.

const BASE_PACKAGE := &"base_package"
const BASE_TABLE := &"base_table"
const BASE_ROW := &"base_row"
const EFFECTIVE_CACHE := &"effective_cache"
const ACTIVE_SAVE := &"active_save"
const MODEL_BINDING := &"model_binding"
const RUNTIME_ADAPTER := &"runtime_adapter"


static func inspect_editor(
		base_source: GDSQLContentPackageSource,
		base_inspection: GDSQLDatabaseInspection,
		cache_manifest: GDSQLContentCacheManifest,
		snapshot: GDSQLDatabaseRegistrySnapshot,
		model_count: int,
		runtime_adapter_configured: bool,
) -> GDSQLManagedSetupReport:
	var report := GDSQLManagedSetupReport.new()
	report.add_check(_base_package_check(base_source, base_inspection))
	var ready_tables := _ready_tables(base_inspection)
	report.add_check(
		GDSQLSetupCheck.new(
			BASE_TABLE,
			"Base content table",
			not ready_tables.is_empty(),
			(
					"%d base table(s) have schema and storage." % ready_tables.size()
					if not ready_tables.is_empty()
					else "Create the base content database, then add its first table."
			),
			GDSQLSetupCheck.ACTION_OPEN_BASE_DATABASE,
		),
	)
	var rows := 0
	for table in ready_tables:
		rows += table.row_count
	report.add_check(
		GDSQLSetupCheck.new(
			BASE_ROW,
			"First base row",
			rows > 0,
			(
					"The base package contains %d stored row(s)." % rows
					if rows > 0
					else "Open a base content table and add its first row."
			),
			GDSQLSetupCheck.ACTION_OPEN_BASE_TABLE,
		),
	)
	report.add_check(_cache_check(cache_manifest))
	report.add_check(_save_check(snapshot))
	report.add_check(
		GDSQLSetupCheck.new(
			MODEL_BINDING,
			"Model binding",
			model_count > 0,
			(
					"%d user-owned model binding(s) found." % model_count
					if model_count > 0
					else "Open a base table and generate its first typed model binding."
			),
			GDSQLSetupCheck.ACTION_OPEN_BASE_TABLE,
		),
	)
	report.add_check(
		GDSQLSetupCheck.new(
			RUNTIME_ADAPTER,
			"Runtime adapter",
			runtime_adapter_configured,
			(
					"GDSQLRuntime is installed as the project autoload."
					if runtime_adapter_configured
					else "Install GDSQLRuntime before managed startup is enabled."
			),
			GDSQLSetupCheck.ACTION_INSTALL_RUNTIME,
		),
	)
	return report


static func _base_package_check(
		base_source: GDSQLContentPackageSource,
		inspection: GDSQLDatabaseInspection,
) -> GDSQLSetupCheck:
	var complete := base_source != null and inspection != null and inspection.catalog_exists
	return GDSQLSetupCheck.new(
		BASE_PACKAGE,
		"Base package",
		complete,
		(
				"Base package '%s' contains the '%s' database." % [
					base_source.manifest.package_id,
					inspection.registration.database_name,
				]
				if complete
				else "Create a valid base package and its content database."
		),
		GDSQLSetupCheck.ACTION_OPEN_MANAGED_CONTENT,
	)


static func _cache_check(manifest: GDSQLContentCacheManifest) -> GDSQLSetupCheck:
	return GDSQLSetupCheck.new(
		EFFECTIVE_CACHE,
		"Effective content",
		manifest != null,
		(
				"%d package(s) are cached as '%s'." % [
					manifest.packages.size(),
					manifest.effective_database_name,
				]
				if manifest != null
				else "Validate packages and build the effective-content cache."
		),
		GDSQLSetupCheck.ACTION_OPEN_MANAGED_CONTENT,
	)


static func _save_check(snapshot: GDSQLDatabaseRegistrySnapshot) -> GDSQLSetupCheck:
	var registration: GDSQLDatabaseRegistration
	if snapshot != null:
		var selected := &""
		for binding in snapshot.role_bindings:
			if binding.role == GDSQLDatabaseRegistry.SAVE_ROLE:
				selected = binding.registration_name
		for candidate in snapshot.registrations:
			if candidate.name == selected:
				registration = candidate
	var complete := registration != null and registration.data_root.begins_with("user://")
	return GDSQLSetupCheck.new(
		ACTIVE_SAVE,
		"Active save",
		complete,
		(
				"Save role resolves to '%s'." % registration.database_name
				if complete
				else "Create or select a writable save slot for runtime state."
		),
		GDSQLSetupCheck.ACTION_MANAGE_SAVE_SLOTS,
	)


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

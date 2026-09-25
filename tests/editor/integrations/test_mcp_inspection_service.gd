class_name GDSQLMcpInspectionServiceTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")
const BridgeContext = preload(
	"res://addons/gdsql/editor/integrations/mcp/gdsql_mcp_bridge_context.gd"
)
const Handler = preload(
	"res://addons/gdsql/editor/integrations/mcp/gdsql_godot_ai_mcp_handler.gd"
)
const Adapter = preload(
	"res://addons/gdsql/editor/integrations/mcp/gdsql_godot_ai_mcp_adapter.gd"
)

var _root: String
var _settings_path: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_root = create_temp_dir("gdsql_mcp_inspection_%d" % _test_index)
	_settings_path = _root.path_join("settings.cfg")


func test_capabilities_are_bounded_and_versioned() -> void:
	var service := _service()

	var result := service.get_capabilities()

	assert_bool(result.is_successful()).is_true()
	var payload := result.get_value() as Dictionary
	assert_str(payload["surface_version"]).is_equal("1.0.0")
	assert_bool(payload["ok"]).is_true()
	assert_bool(payload["data"]["limits"]["row_values_exposed"]).is_false()
	assert_int(payload["data"]["tools"].size()).is_equal(3)
	assert_str(payload["data"]["selected_profile"]).is_equal("direct")
	assert_str(JSON.stringify(payload)).is_not_empty()


func test_schema_inspection_lists_registrations_without_host_paths() -> void:
	var service := _service()

	var result := service.inspect_schema()

	assert_bool(result.is_successful()).is_true()
	var payload := result.get_value() as Dictionary
	assert_str(payload["data"]["kind"]).is_equal("registrations")
	assert_int(payload["data"]["items"].size()).is_equal(2)
	var content := payload["data"]["items"][0] as Dictionary
	assert_str(content["name"]).is_equal("content")
	assert_str(content["data_root"]).is_equal(_root.path_join("content"))
	assert_bool(String(content["data_root"]).begins_with("/")).is_false()


func test_table_detail_exposes_constraints_but_never_rows() -> void:
	var service := _service()

	var result := service.inspect_schema(&"content", &"loadouts")

	assert_bool(result.is_successful()).is_true()
	var payload := result.get_value() as Dictionary
	var table := payload["data"]["table"] as Dictionary
	assert_str(table["name"]).is_equal("loadouts")
	assert_int(table["row_count"]).is_equal(1)
	assert_int(table["foreign_keys"].size()).is_equal(1)
	assert_str(table["foreign_keys"][0]["referenced_table"]).is_equal("heroes")
	assert_bool(table.has("rows")).is_false()
	assert_str(JSON.stringify(payload)).not_contains("Sword")


func test_setup_inspection_projects_ordered_checks() -> void:
	var service := _service()

	var result := service.inspect_setup(&"selected")

	assert_bool(result.is_successful()).is_true()
	var payload := result.get_value() as Dictionary
	assert_str(payload["data"]["selected_profile"]).is_equal("direct")
	assert_str(payload["data"]["inspected_profile"]).is_equal("direct")
	assert_bool(payload["data"]["checks"].is_empty()).is_false()
	assert_str(payload["data"]["checks"][0]["id"]).is_equal("content_database")


func test_schema_inspection_rejects_unknown_targets_and_bad_limits() -> void:
	var service := _service()

	var missing := service.inspect_schema(&"missing")
	var bad_limit := service.inspect_schema(&"", &"", "", 0)

	assert_bool(missing.is_successful()).is_false()
	assert_str(String(missing.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MCP_REGISTRATION_NOT_FOUND",
	)
	assert_bool(bad_limit.is_successful()).is_false()
	assert_str(String(bad_limit.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MCP_LIMIT_INVALID",
	)


func test_lazy_handler_uses_attached_inspection_service() -> void:
	var service := _service()
	BridgeContext.attach(service)
	var handler := Handler.new()

	var response := handler.capabilities({ }, null)
	var invalid := handler.inspect_setup({ "unknown": true }, null)

	assert_str(response["status"] if response.has("status") else "ok").is_equal("ok")
	assert_str(response["data"]["surface_version"]).is_equal("1.0.0")
	assert_str(invalid["status"]).is_equal("error")
	assert_str(invalid["error"]["code"]).is_equal("INVALID_PARAMS")
	BridgeContext.detach(service)


func test_godot_ai_specs_follow_the_published_contract() -> void:
	var service := _service()
	var adapter := Adapter.new(service)
	assert_bool(adapter.call("_load_godot_ai_contract")).is_true()
	adapter.call("_refresh_registry")
	var specs := adapter.call("_build_specs") as Array

	assert_bool(specs.is_typed()).is_true()
	assert_int(specs.size()).is_equal(3)
	for spec in specs:
		assert_bool((spec.call("validate") as Array).is_empty()).is_true()
		assert_bool(spec.get("promoted")).is_true()
		assert_bool(spec.get("requires_writable")).is_false()
		assert_bool(spec.get("deferred")).is_false()
		assert_bool(spec.get("undoable")).is_false()
	adapter.shutdown()
	adapter.free()


func _service() -> GDSQLMcpInspectionService:
	var content_root := _root.path_join("content")
	var save_root := _root.path_join("save")
	var heroes := GDSQLTableDefinition.new(&"heroes", &"id") \
			.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true)) \
			.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	var loadouts := GDSQLTableDefinition.new(&"loadouts", &"id") \
			.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true)) \
			.add_column(GDSQLColumnDefinition.new(&"hero_id", TYPE_INT, false)) \
			.add_column(GDSQLColumnDefinition.new(&"label", TYPE_STRING, false)) \
			.add_foreign_key(
				GDSQLForeignKeyDefinition.new(
					&"fk_loadouts_hero",
					&"hero_id",
					&"heroes",
					&"id",
				),
			)
	var content := TestDatabase.create_database_with_tables(
		content_root,
		[heroes, loadouts],
		&"content",
	)
	TestDatabase.insert_rows(
		content,
		[{ &"id": 1, &"name": "Knight" }],
		&"heroes",
	)
	TestDatabase.insert_rows(
		content,
		[{ &"id": 1, &"hero_id": 1, &"label": "Sword" }],
		&"loadouts",
	)
	TestDatabase.create_database(
		save_root,
		GDSQLTableDefinition.new(&"state", &"id") \
				.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true)),
		&"save",
	)
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.assign(
		[
			GDSQLDatabaseRegistration.new(&"content", &"content", content_root),
			GDSQLDatabaseRegistration.new(&"save", &"save", save_root),
		],
	)
	snapshot.role_bindings.assign(
		[
			GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.CONTENT_ROLE, &"content"),
			GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.SAVE_ROLE, &"save"),
		],
	)
	var registry := GDSQLDatabaseRegistry.new(
		GDSQLConfigFileDatabaseRegistryStore.new(_root.path_join("registry.cfg")),
	)
	assert_bool(registry.save_snapshot(snapshot).is_successful()).is_true()
	var workbench := GDSQLWorkbench.new(registry, GDSQLConfigFileDatabaseExplorer.new())
	assert_bool(workbench.load().is_successful()).is_true()
	var profile_store := GDSQLConfigFileSetupProfileStore.new(_settings_path)
	assert_bool(
		profile_store.save_profile(GDSQLSetupProfile.Kind.DIRECT).is_successful(),
	).is_true()
	return GDSQLMcpInspectionService.new(
		workbench,
		profile_store,
		GDSQLConfigFileManagedContentConfigurationStore.new(_settings_path),
		GDSQLConfigFileContentPackageManifestStore.new(),
		GDSQLConfigFileContentCacheStore.new(_root.path_join("cache")),
		GDSQLConfigFileDatabaseExplorer.new(),
		func() -> int: return 1,
		func() -> bool: return true,
	)

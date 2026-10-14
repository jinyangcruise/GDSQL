@tool
extends Node
## Optional reload-safe registration with Godot-AI's custom-tool registry.

const Context := preload("res://addons/gdsql/editor/integrations/mcp/gdsql_mcp_bridge_context.gd")
const GODOT_AI_REGISTRY := "res://addons/godot_ai/custom_tools/mcp_tool_registry.gd"
const GODOT_AI_SPEC := "res://addons/godot_ai/custom_tools/mcp_custom_tool_spec.gd"
const SOURCE_PATH := "res://addons/gdsql/plugin.cfg"
const HANDLER_PATH := (
		"res://addons/gdsql/editor/integrations/mcp/gdsql_godot_ai_mcp_handler.gd"
)
const POLL_SECONDS := 0.5

var _inspection_service: GDSQLMcpInspectionService
var _authoring_service: GDSQLMcpAuthoringService
var _registry_script: Script
var _spec_script: Script
var _registry: Variant
var _poll_elapsed := 0.0


func _init(
		inspection_service: GDSQLMcpInspectionService,
		authoring_service: GDSQLMcpAuthoringService = null,
) -> void:
	_inspection_service = inspection_service
	_authoring_service = authoring_service
	Context.attach(inspection_service, authoring_service)


func _ready() -> void:
	set_process(true)
	_refresh_registry()


func shutdown() -> void:
	set_process(false)
	_release_registry()
	Context.detach(_inspection_service, _authoring_service)
	_inspection_service = null
	_authoring_service = null


func _process(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed < POLL_SECONDS:
		return
	_poll_elapsed = 0.0
	_refresh_registry()


func _refresh_registry() -> void:
	if not _load_godot_ai_contract():
		_adopt_registry(null)
		return
	var current: Variant = _registry_script.call("get_instance")
	_adopt_registry(current)


func _adopt_registry(current: Variant) -> void:
	if current == _registry and is_instance_valid(_registry):
		return
	_release_registry()
	if not _is_registry_compatible(current):
		return
	_registry = current
	if _registry.has_signal("registry_ready") \
			and not _registry.is_connected("registry_ready", _on_registry_ready):
		_registry.connect("registry_ready", _on_registry_ready)
	if bool(_registry.call("is_ready")):
		_register_tools()


func _load_godot_ai_contract() -> bool:
	if not ResourceLoader.exists(GODOT_AI_REGISTRY) or not ResourceLoader.exists(GODOT_AI_SPEC):
		return false
	if _registry_script == null:
		_registry_script = load(GODOT_AI_REGISTRY) as Script
	if _spec_script == null:
		_spec_script = load(GODOT_AI_SPEC) as Script
	return _registry_script != null and _spec_script != null


func _disconnect_registry() -> void:
	if is_instance_valid(_registry) and _registry.has_signal("registry_ready") \
			and _registry.is_connected("registry_ready", _on_registry_ready):
		_registry.disconnect("registry_ready", _on_registry_ready)


func _release_registry() -> void:
	_disconnect_registry()
	if is_instance_valid(_registry) and _registry.has_method("unregister_source"):
		_registry.call("unregister_source", SOURCE_PATH)
	_registry = null


func _is_registry_compatible(candidate: Variant) -> bool:
	return is_instance_valid(candidate) \
			and candidate.has_method("is_ready") \
			and candidate.has_method("batch_register") \
			and candidate.has_method("unregister_source")


func _on_registry_ready() -> void:
	_register_tools()


func _register_tools() -> void:
	if not is_instance_valid(_registry) or _spec_script == null:
		return
	if not bool(_registry.call("batch_register", _build_specs())):
		push_error("GDSQL: Godot-AI custom tool registration failed.")


func _build_specs() -> Array:
	var specs := [
		_spec(
			"gdsql_capabilities",
			"Describe the installed GDSQL agent surface, limits, and selected setup profile.",
			&"capabilities",
			{ "type": "object", "additionalProperties": false },
		),
		_spec(
			"gdsql_inspect_setup",
			"Inspect the current GDSQL Direct or Managed Content setup checklist without changing the project.",
			&"inspect_setup",
			{
				"type": "object",
				"additionalProperties": false,
				"properties": {
					"profile": {
						"type": "string",
						"enum": ["selected", "direct", "managed"],
						"default": "selected",
					},
				},
			},
		),
		_spec(
			"gdsql_inspect_models",
			"List GDSQL model bindings or inspect one binding's static compatibility and relationships without executing user code.",
			&"inspect_models",
			{
				"type": "object",
				"additionalProperties": false,
				"properties": {
					"registration": { "type": "string" },
					"table": { "type": "string" },
					"cursor": { "type": "string" },
					"limit": {
						"type": "integer",
						"minimum": 1,
						"maximum": GDSQLMcpInspectionService.MAX_LIMIT,
						"default": GDSQLMcpInspectionService.DEFAULT_LIMIT,
					},
				},
			},
		),
		_spec(
			"gdsql_inspect_schema",
			"List registered GDSQL databases and tables or inspect one table schema. Row values are never returned.",
			&"inspect_schema",
			{
				"type": "object",
				"additionalProperties": false,
				"properties": {
					"registration": { "type": "string" },
					"table": { "type": "string" },
					"cursor": { "type": "string" },
					"limit": {
						"type": "integer",
						"minimum": 1,
						"maximum": GDSQLMcpInspectionService.MAX_LIMIT,
						"default": GDSQLMcpInspectionService.DEFAULT_LIMIT,
					},
				},
			},
		),
	]
	if _authoring_service != null:
		specs.append(
			_spec(
				"gdsql_query_rows",
				"Query bounded scalar row data with structured WHERE, ordering, and opaque cursor pagination.",
				&"query_rows",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["registration", "table"],
					"properties": {
						"registration": { "type": "string", "minLength": 1 },
						"table": { "type": "string", "minLength": 1 },
						"columns": {
							"type": "array",
							"items": { "type": "string" },
							"uniqueItems": true,
						},
						"where": { "type": "object" },
						"order_by": {
							"type": "array",
							"maxItems": 8,
							"items": {
								"type": "object",
								"required": ["column"],
								"additionalProperties": false,
								"properties": {
									"column": { "type": "string" },
									"direction": { "type": "string", "enum": ["asc", "desc"] },
								},
							},
						},
						"cursor": { "type": "string" },
						"limit": {
							"type": "integer",
							"minimum": 1,
							"maximum": GDSQLMcpAuthoringService.MAX_LIMIT,
							"default": GDSQLMcpAuthoringService.DEFAULT_LIMIT,
						},
					},
				},
			),
		)
		specs.append(
			_spec(
				"gdsql_preview_row_mutation",
				"Validate and preview a bounded scalar insert, update, or delete. Returns a short-lived confirmation handle and changes nothing.",
				&"preview_row_mutation",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["operation", "registration", "table"],
					"properties": {
						"operation": { "type": "string", "enum": ["insert", "update", "delete"] },
						"registration": { "type": "string", "minLength": 1 },
						"table": { "type": "string", "minLength": 1 },
						"rows": { "type": "array", "maxItems": GDSQLMcpAuthoringService.MAX_MUTATION_ROWS },
						"primary_keys": { "type": "array", "maxItems": GDSQLMcpAuthoringService.MAX_MUTATION_ROWS },
					},
				},
				true,
			),
		)
		specs.append(
			_spec(
				"gdsql_commit_row_mutation",
				"Commit one previewed GDSQL row mutation using its one-use confirmation handle.",
				&"commit_row_mutation",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["handle", "confirm"],
					"properties": {
						"handle": { "type": "string", "minLength": 1 },
						"confirm": { "type": "boolean" },
					},
				},
				true,
				30_000,
			),
		)
		specs.append(
			_spec(
				"gdsql_preview_schema_mutation",
				"Validate and preview one registered GDSQL table schema mutation. Returns a short-lived confirmation handle and changes nothing.",
				&"preview_schema_mutation",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["operation", "registration", "table"],
					"properties": {
						"operation": {
							"type": "string",
							"enum": ["create_table", "rename_table", "drop_table", "alter_table"],
						},
						"registration": { "type": "string", "minLength": 1 },
						"table": { "type": ["string", "object"] },
						"new_name": { "type": "string" },
						"alterations": {
							"type": "array",
							"maxItems": 32,
							"items": { "type": "object" },
						},
					},
				},
				true,
			),
		)
		specs.append(
			_spec(
				"gdsql_commit_schema_mutation",
				"Commit one previewed GDSQL table schema mutation using its one-use confirmation handle.",
				&"commit_schema_mutation",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["handle", "confirm"],
					"properties": {
						"handle": { "type": "string", "minLength": 1 },
						"confirm": { "type": "boolean" },
					},
				},
				true,
				30_000,
			),
		)
		specs.append(
			_spec(
				"gdsql_preview_database_mutation",
				"Validate and preview creation, rename, unregistration, or destruction of a registered GDSQL database without accepting arbitrary paths.",
				&"preview_database_mutation",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["operation", "registration"],
					"properties": {
						"operation": {
							"type": "string",
							"enum": [
								"create_database", "rename_database",
								"unregister_database", "destroy_database",
							],
						},
						"registration": { "type": "string", "minLength": 1 },
						"database": { "type": "string" },
						"location": {
							"type": "string",
							"enum": ["project_data", "settings", "registration_root"],
						},
						"root_registration": { "type": "string" },
						"storage_backend": {
							"type": "string",
							"enum": ["configfile", "memory"],
						},
						"new_name": { "type": "string" },
					},
				},
				true,
			),
		)
		specs.append(
			_spec(
				"gdsql_commit_database_mutation",
				"Commit one previewed registered-database lifecycle mutation using its one-use confirmation handle.",
				&"commit_database_mutation",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["handle", "confirm"],
					"properties": {
						"handle": { "type": "string", "minLength": 1 },
						"confirm": { "type": "boolean" },
					},
				},
				true,
				30_000,
			),
		)
		specs.append(
			_spec(
				"gdsql_preview_migration",
				"Preview the next pending migration, or validate a new ordered schema/data migration without writing.",
				&"preview_migration",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["registration"],
					"properties": {
						"registration": { "type": "string", "minLength": 1 },
						"migration_id": { "type": "string" },
						"description": { "type": "string" },
						"steps": {
							"type": "array",
							"minItems": 1,
							"maxItems": 16,
							"items": { "type": "object" },
						},
					},
				},
				true,
				30_000,
			),
		)
		specs.append(
			_spec(
				"gdsql_commit_migration",
				"Persist and apply one previewed GDSQL migration using its one-use confirmation handle.",
				&"commit_migration",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["handle", "confirm"],
					"properties": {
						"handle": { "type": "string", "minLength": 1 },
						"confirm": { "type": "boolean" },
					},
				},
				true,
				30_000,
			),
		)
		specs.append(
			_spec(
				"gdsql_preview_model_mutation",
				"Preview generated model sources or register/remove a save-to-content model reference without executing user code.",
				&"preview_model_mutation",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["operation"],
					"properties": {
						"operation": {
							"type": "string",
							"enum": [
								"generate_model",
								"register_content_reference",
								"remove_content_reference",
							],
						},
						"registration": { "type": "string" },
						"table": { "type": "string" },
						"class_name": { "type": "string" },
						"role": { "type": "string" },
						"model_root": { "type": "string" },
						"source_registration": { "type": "string" },
						"source_table": { "type": "string" },
						"source_column": { "type": "string" },
						"target_registration": { "type": "string" },
						"target_table": { "type": "string" },
						"target_column": { "type": "string" },
						"target_model_class": { "type": "string" },
						"relationship_name": { "type": "string" },
					},
				},
				true,
				30_000,
			),
		)
		specs.append(
			_spec(
				"gdsql_commit_model_mutation",
				"Commit one previewed model-source or cross-role reference mutation using its one-use confirmation handle.",
				&"commit_model_mutation",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["handle", "confirm"],
					"properties": {
						"handle": { "type": "string", "minLength": 1 },
						"confirm": { "type": "boolean" },
					},
				},
				true,
				30_000,
			),
		)
		specs.append(
			_spec(
				"gdsql_preview_setup_mutation",
				"Preview profile, role, runtime, save-slot, or Managed Content cache setup.",
				&"preview_setup_mutation",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["operation"],
					"properties": {
						"operation": {
							"type": "string",
							"enum": [
								"select_profile", "bind_role", "install_runtime_adapter",
								"create_save_slot", "delete_save_slot", "build_managed_cache",
							],
						},
						"profile": { "type": "string", "enum": ["direct", "managed"] },
						"role": {
							"type": "string",
							"enum": ["content", "save", "settings"],
						},
						"registration": { "type": "string", "minLength": 1 },
						"save_slot": { "type": "string", "minLength": 1 },
						"storage_backend": {
							"type": "string",
							"enum": ["configfile", "memory"],
						},
					},
				},
				true,
				30_000,
			),
		)
		specs.append(
			_spec(
				"gdsql_commit_setup_mutation",
				"Commit one unchanged setup mutation preview using its one-use confirmation handle.",
				&"commit_setup_mutation",
				{
					"type": "object",
					"additionalProperties": false,
					"required": ["handle", "confirm"],
					"properties": {
						"handle": { "type": "string", "minLength": 1 },
						"confirm": { "type": "boolean" },
					},
				},
				true,
				30_000,
			),
		)
	return Array(
		specs,
		TYPE_OBJECT,
		&"RefCounted",
		_spec_script,
	)


func _spec(
		name: String,
		description: String,
		method: StringName,
		schema: Dictionary,
		requires_writable: bool = false,
		timeout_ms: int = 4500,
) -> Variant:
	var spec: Variant = _spec_script.new()
	spec.set("name", name)
	spec.set("description", description)
	spec.set("params_schema", schema)
	spec.set("script_path", HANDLER_PATH)
	spec.set("method", method)
	spec.set("source_path", SOURCE_PATH)
	spec.set("source", "GDSQL")
	spec.set("promoted", true)
	spec.set("timeout_ms", timeout_ms)
	spec.set("deferred", false)
	spec.set("requires_writable", requires_writable)
	spec.set("undoable", false)
	return spec

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

var _service: GDSQLMcpInspectionService
var _registry_script: Script
var _spec_script: Script
var _registry: Variant
var _poll_elapsed := 0.0


func _init(service: GDSQLMcpInspectionService) -> void:
	_service = service
	Context.attach(service)


func _ready() -> void:
	set_process(true)
	_refresh_registry()


func shutdown() -> void:
	set_process(false)
	_disconnect_registry()
	if is_instance_valid(_registry):
		_registry.call("unregister_source", SOURCE_PATH)
	_registry = null
	Context.detach(_service)
	_service = null


func _process(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed < POLL_SECONDS:
		return
	_poll_elapsed = 0.0
	_refresh_registry()


func _refresh_registry() -> void:
	if not _load_godot_ai_contract():
		if is_instance_valid(_registry):
			_disconnect_registry()
			_registry = null
		return
	var current: Variant = _registry_script.call("get_instance")
	if current == _registry:
		return
	_disconnect_registry()
	_registry = current
	if not is_instance_valid(_registry):
		return
	if _registry.has_signal("registry_ready"):
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


func _on_registry_ready() -> void:
	_register_tools()


func _register_tools() -> void:
	if not is_instance_valid(_registry) or _spec_script == null:
		return
	if not bool(_registry.call("batch_register", _build_specs())):
		push_error("GDSQL: Godot-AI custom tool registration failed.")


func _build_specs() -> Array:
	return Array(
		[
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
		],
		TYPE_OBJECT,
		&"RefCounted",
		_spec_script,
	)


func _spec(
		name: String,
		description: String,
		method: StringName,
		schema: Dictionary,
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
	spec.set("timeout_ms", 4500)
	spec.set("deferred", false)
	spec.set("requires_writable", false)
	spec.set("undoable", false)
	return spec

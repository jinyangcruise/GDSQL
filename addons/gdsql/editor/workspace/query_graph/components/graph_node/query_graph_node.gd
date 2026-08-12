@tool
class_name GDSQLQueryGraphNode
extends GraphNode
## Shared presentation base for query-graph operation and result nodes.
##
## The base owns titlebar presentation and emits removal intent. The containing
## graph editor remains responsible for disconnecting and freeing the node.

signal remove_requested
signal expand_requested

const HEADER_SCENE := preload(
	"res://addons/gdsql/editor/workspace/query_graph/components/graph_node/query_graph_node_header.tscn"
)

@export var show_close_button := true:
	set(value):
		show_close_button = value
		if _titlebar_header != null:
			_titlebar_header.set_close_visible(value)

var _titlebar_header: GDSQLQueryGraphNodeHeader
var _close_enabled := true


func _ready() -> void:
	_install_header()


func get_header_actions_host() -> HBoxContainer:
	_install_header()
	return _titlebar_header.get_actions_host() if _titlebar_header != null else null


func add_header_action(control: Control) -> void:
	_install_header()
	if _titlebar_header != null:
		_titlebar_header.add_action_control(control)


func set_close_enabled(enabled: bool) -> void:
	_close_enabled = enabled
	_install_header()
	if _titlebar_header != null:
		_titlebar_header.set_close_enabled(_close_enabled)


func _install_header() -> void:
	if _titlebar_header != null and is_instance_valid(_titlebar_header):
		return
	var titlebar := get_titlebar_hbox()
	if titlebar == null:
		return
	var existing := titlebar.get_node_or_null("QueryGraphNodeHeader") \
			as GDSQLQueryGraphNodeHeader
	if existing != null:
		_titlebar_header = existing
	else:
		_titlebar_header = HEADER_SCENE.instantiate() as GDSQLQueryGraphNodeHeader
		titlebar.add_child(_titlebar_header)
	_titlebar_header.set_close_visible(show_close_button)
	_titlebar_header.set_close_enabled(_close_enabled)
	if not _titlebar_header.close_requested.is_connected(_on_close_requested):
		_titlebar_header.close_requested.connect(_on_close_requested)
	if not _titlebar_header.expand_requested.is_connected(_on_expand_requested):
		_titlebar_header.expand_requested.connect(_on_expand_requested)


func _on_close_requested() -> void:
	remove_requested.emit()


func _on_expand_requested() -> void:
	expand_requested.emit()

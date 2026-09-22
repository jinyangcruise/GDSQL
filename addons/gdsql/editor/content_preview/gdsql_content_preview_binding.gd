@tool
class_name GDSQLContentPreviewBinding
extends Resource
## Maps one content-model property onto a transient preview-scene node.

@export var model_property: StringName
@export var target_node: NodePath = NodePath(".")
@export var target_property: StringName

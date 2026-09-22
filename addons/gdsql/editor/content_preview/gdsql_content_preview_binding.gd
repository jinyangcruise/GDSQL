@tool
class_name GDSQLContentPreviewBinding
extends Resource
## Maps one content-model property onto a transient preview-scene node.

## Property declared by the selected content model, such as `name` or `texture`.
@export var model_property: StringName
## Target node relative to the preview-scene root. Use `.` for the root itself.
@export var target_node: NodePath = NodePath(".")
## Compatible property on the target node. No value conversion is performed.
@export var target_property: StringName

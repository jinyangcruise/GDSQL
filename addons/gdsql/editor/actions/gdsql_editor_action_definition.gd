class_name GDSQLEditorActionDefinition
extends RefCounted
## Presentation metadata for one stable editor action.
##
## The definition can be reused by toolbars, menus, context actions, and
## shortcuts. Behavior remains in the context hub that registers it.

enum Kind {
	ACTION,
	TOGGLE,
	SEPARATOR,
}

var id: StringName
var label: String
var tooltip: String
var icon_name: StringName
var group: StringName
var order: int
var kind: Kind


func _init(
		action_id: StringName = &"",
		action_label: String = "",
		action_tooltip: String = "",
		action_icon_name: StringName = &"",
		action_group: StringName = &"",
		action_order: int = 0,
		action_kind: Kind = Kind.ACTION,
) -> void:
	id = action_id
	label = action_label
	tooltip = action_tooltip
	icon_name = action_icon_name
	group = action_group
	order = action_order
	kind = action_kind

@tool
extends VSplitContainer
class_name SQLFile

@onready var _code_edit: CodeEdit = $VBoxContainer/CodeEdit

var code_edit: CodeEdit:
	get:
		return _code_edit

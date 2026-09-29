@tool
extends HBoxContainer
## One registered save-to-content editor picker binding.

signal remove_requested(reference: GDSQLEditorContentReference)
signal snippet_copied(reference: GDSQLEditorContentReference)

var _reference: GDSQLEditorContentReference


func _ready() -> void:
	%Copy.pressed.connect(_copy_snippet)
	%Remove.pressed.connect(_request_remove)


func configure(reference: GDSQLEditorContentReference) -> void:
	_reference = reference
	%Relationship.text = String(reference.relationship_name)
	%Connection.text = "%s → %s / %s.%s" % [
		reference.source_column_name,
		reference.target_database_name,
		reference.target_table_name,
		reference.target_column_name,
	]
	%Connection.tooltip_text = (
			"Target registration: %s\nTarget model: %s" % [
				reference.target_registration_name,
				reference.target_model_class,
			]
	)


func _copy_snippet() -> void:
	if _reference == null:
		return
	var snippet := _reference.build_relationship_snippet()
	if snippet.is_empty():
		return
	DisplayServer.clipboard_set(snippet)
	snippet_copied.emit(_reference)


func _request_remove() -> void:
	if _reference != null:
		remove_requested.emit(_reference)

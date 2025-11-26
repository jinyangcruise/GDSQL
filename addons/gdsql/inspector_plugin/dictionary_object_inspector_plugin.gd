extends EditorInspectorPlugin


func _can_handle(object: Object) -> bool:
	return object is GDSQL.DictionaryObject
	
func _parse_begin(object: Object) -> void:
	if object.has_method("get_custom_begin_control"):
		var contorl: Control = object.call("get_custom_begin_control")
		if contorl:
			add_custom_control(contorl)
			
func _parse_end(object: Object) -> void:
	if object.has_method("get_custom_end_control"):
		var contorl: Control = object.call("get_custom_end_control")
		if contorl:
			add_custom_control(contorl)
			#contorl.print_tree_pretty()

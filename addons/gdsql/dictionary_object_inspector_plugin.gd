extends EditorInspectorPlugin


func _can_handle(object: Object) -> bool:
	return object is DictionaryObject
	
func _parse_begin(object: Object) -> void:
	var save_button := Button.new()
	save_button.text = "SAVE"
	save_button.custom_minimum_size.y = 100
	# TODO 事件绑定
	add_custom_control(save_button)

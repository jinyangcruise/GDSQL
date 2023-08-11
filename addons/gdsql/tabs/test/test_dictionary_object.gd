extends Control

func _ready() -> void:
	var _hint_string = {
		"Data Type": {
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": ""
		},
		"Hint": {
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": ""
		},
		"Default(Expression)": {
			"hint": PROPERTY_HINT_EXPRESSION,
			"hint_string": ""
		},
		"Comment": {
			"hint": PROPERTY_HINT_MULTILINE_TEXT,
			"hint_string": ""
		},
	}
	var row := DictionaryObject.new([
		["Column Name", "Data Type", "Hint", "Hint String", "PK", "NN", "UQ", "AI", "Default(Expression)", "Comment"], 
		["idnew_table", TYPE_INT, PROPERTY_HINT_NONE , "", true, true, false, true, "", ""]
	], _hint_string)
	var list = row.get_property_list()
	for i in list:
		#if i.has("flags") and i["flags"] and i["flags"] & METHOD_FLAG_EDITOR:
		if i["usage"] & PROPERTY_USAGE_EDITOR:
			printt(i["name"], i["usage"], i["usage"] & PROPERTY_USAGE_EDITOR)
#https://github.com/godotengine/godot/blob/013e8e3afb982d4b230f0039b6dc248b48794ab9/editor/editor_inspector.cpp#L2970

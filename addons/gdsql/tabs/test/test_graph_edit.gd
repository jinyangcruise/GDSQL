extends GraphEdit

var SQLGraphNode= preload("res://addons/gdsql/tabs/sql_graph_node/graph_node.tscn")

func _on_button_pressed() -> void:
	var graph_node = SQLGraphNode.instantiate()
	var datas: Array[Array] = [
		["Union All", "Result"],
		["Left Join", null],
		[GDSQL.DictionaryObject.new({"Schema": "Six:6", "_password": ""}, {"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": "Zero,One,Three:3,Four,Six:6"}, "_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}}), null],
		[GDSQL.DictionaryObject.new({"Table": "", "_alias": ""}, {"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": "t1,t2,t3"}, "_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}}), null],
		[GDSQL.DictionaryObject.new({"Fields": ""}, {"Fields": {"hint": PROPERTY_HINT_MULTILINE_TEXT}}), null],
		[GDSQL.DictionaryObject.new({"Where": ""}, {"Where": {"hint": PROPERTY_HINT_MULTILINE_TEXT}}), null],
		[GDSQL.DictionaryObject.new({"Order By": "", "_order": "ASC"}, {"_order": {"hint": PROPERTY_HINT_ENUM, "hint_string": "ASC,DESC"}}), null],
		[GDSQL.DictionaryObject.new({"Offset": 0}), null],
		[GDSQL.DictionaryObject.new({"Limit": 0}), null],
	]
	graph_node.datas = datas
	graph_node.title = "Select"
	graph_node.set_meta("type", "select")
	graph_node.set_meta("node", true)
	add_child(graph_node)
	graph_node.selected = true
	graph_node.size.x = 600
	graph_node.position_offset = (get_rect().get_center() - graph_node.get_rect().size/2 + scroll_offset) / zoom

extends EditorInspectorPlugin

var xml_editor_window: Window

#func _parse_begin(object: Object) -> void:
	#var pc = PanelContainer.new()
	#var edit_btn = Button.new()
	#pc.add_child(edit_btn)
	#edit_btn.text = "Edit"
	#edit_btn.icon = EditorInterface.get_base_control().get_theme_icon("Edit", "EditorIcons")
	#edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	#edit_btn.pressed.connect(_on_edit_btn_pressed.bind(object.resource_path))
	#add_custom_control(pc)
#

func _can_handle(object: Object) -> bool:
	return object is GXML
	
func _parse_begin(object: Object) -> void:
	var pc = PanelContainer.new()
	var vbc = VBoxContainer.new()
	pc.add_child(vbc)
	
	var edit_btn = Button.new()
	vbc.add_child(edit_btn)
	edit_btn.text = "Edit"
	edit_btn.icon = EditorInterface.get_base_control().get_theme_icon("Edit", "EditorIcons")
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_btn.self_modulate = Color(1, 2, 1, 1)
	edit_btn.pressed.connect(_on_edit_btn_pressed.bind(object.resource_path))
	
	var tree = Tree.new()
	vbc.add_child(tree)
	var root = tree.create_item()
	tree.hide_root = true
	
	var loader = ResourceFormatLoaderXML.new()
	var gxml = loader._load(object.resource_path, "", false, ResourceLoader.CACHE_MODE_IGNORE) as GXML
	if gxml and gxml.root_item:
		parse_gxml_item(gxml.root_item, root, tree)
		tree.custom_minimum_size.y = min(1300, calculate_tree_height(root))
		tree.item_collapsed.connect(func(_item): tree.custom_minimum_size.y = min(1500, calculate_tree_height(root)))
		
	add_custom_control(pc)
	
func _on_edit_btn_pressed(path: String):
	xml_editor_window.open_file(path)
	
func parse_gxml_item(item: GDSQL.GXMLItem, parent_tree_item: TreeItem, tree: Tree):
	var tree_item = tree.create_item(parent_tree_item)
	# 看需不需要合并到一行显示
	if item.line == item.end_line:
		tree_item.set_text(0, "    " + parse_gxml_item_to_str(item))
		return
		
	var attrs = []
	for i in item.attrs:
		attrs.push_back(i + '="' + item.attrs[i] + '"')
		
	var other = ' '.join(attrs) + ('/>' if item.content.is_empty() else '>')
	if not attrs.is_empty():
		other = ' ' + other
	tree_item.set_text(0, '    <' + item.name + other)
	
	for i in item.content:
		if i is String:
			var s_item = tree.create_item(tree_item)
			s_item.set_text(0, '    ' + i.strip_edges())
		elif i is GDSQL.GXMLItem:
			parse_gxml_item(i, tree_item, tree)
			
	if not item.content.is_empty():
		var end_item = tree.create_item(tree_item)
		end_item.set_text(0, "</" + item.name + ">")
		
func parse_gxml_item_to_str(item: GDSQL.GXMLItem):
	var strs = ["<", item.name]
	if not item.attrs.is_empty():
		strs.push_back(" ")
	for i in item.attrs:
		strs.push_back(i + '="' + item.attrs[i] + '"')
	if not item.attrs.is_empty() and not item.content.is_empty():
		strs.push_back(">")
	for i in item.content:
		if i is String:
			strs.push_back(i)
		elif i is GDSQL.GXMLItem:
			strs.push_back(parse_gxml_item_to_str(i))
	if item.content.is_empty():
		strs.push_back("/>")
	else:
		strs.push_back("</")
		strs.push_back(item.name)
		strs.push_back(">")
	return "".join(strs)
		
func calculate_tree_height(node: TreeItem) -> int:
	# 如果节点是折叠的，则只计算当前节点的高度
	if node.collapsed or node.get_child_count() == 0:
		return 43 if node.get_parent() else 18
	# 如果节点是展开的，则递归计算所有子节点的高度
	else:
		var h = 0
		for child in node.get_children():
			h += calculate_tree_height(child)
		return (43 if node.get_parent() else 18) + h

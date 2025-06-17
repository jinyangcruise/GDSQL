extends Node
class_name GDSQLWorkbenchManagerClass

## 打开新建数据库标签页的信号
signal open_add_schema_tab
## 用户确认新建数据库的信号
signal user_confirm_add_schema(db_name: String, path: String, id: String)
## 系统确认新建数据库的信号
signal sys_confirm_add_schema(id: String)

## 打开修改数据库标签页的信号
signal open_alter_schema_tab(db_name: String, path: String)
## 用户确认修改数据库的信号
signal user_confirm_alter_schema(old_db_name: String, new_db_name: String, path: String, id: String)
## 系统确认修改数据库的信号
signal sys_confirm_alter_schema(id: String)

## 打开新建数据表标签页的信号
signal open_add_table_tab(db_name: String)
## 用户确认新建表的信号
signal user_confirm_add_table(sechema: String, table_name: String, comments: String, 
	password: String, valid_if_not_exist: bool, columns: Array, id: String)
## 系统确认新建数据表的信号
signal sys_confirm_add_table(id: String)

## 打开修改数据表标签页的信号
signal open_alter_table_tab(db_name: String, table_name: String)
## 用户确认修改数据表的信号
signal user_confirm_alter_table(sechema: String, old_table_name: String, new_table_name: String, 
	comments: String, valid_if_not_exist: bool, columns: Array, id: String)
## 系统确认修改数据表的信号
signal sys_confirm_alter_table(id: String)

## 打开数据表检查器页签的信号
signal open_table_inspector_tab(db_name: String, table_name: String)
## 打开数据表导出页签的信号
signal open_table_data_export_tab(db_name: String, table_name: String)
## 打开数据表导入页签的信号
signal open_table_data_import_tab(db_name: String, table_name: String)
## 请求用户输入数据表密码的信号
signal request_user_enter_password(db_name: String, table_name: String, try_password: String, callback: Callable, fail_callback: Callable)
## 是否需要用户输入某个表的密码
signal need_user_enter_password(db_name: String, table_name: String, try_password: String, result: Array)

## 打开临时数据导出页签的信号
signal open_select_data_export_tab(columns: Array, datas: Array)

## 打开生成Mapper页签的信号
signal open_mapper_graph_tab(info: Dictionary)

## 打开生成Mapper文件的信号
signal open_mapper_graph_file_tab(path: String)

## 请求新建某表
signal request_create_table(db_name: String, table_name: String, comment: String, password: String, column_infos: Array)
## 请求删除某表
signal request_drop_table(db_name: String, table_name: String)

## 发送到编辑器
signal send_to_editor(content: String)
## 发送到编辑器并执行的信号
signal send_to_editor_and_execute(title: String, info: Dictionary)

## 记录操作日志
signal add_log_history(status: String, begin_timestamp: String, action: String, message: String)

## 主界面引用。只有设定了该变量，才能使用run_in_plugin方法
var main_panel: Control

## 数据库配置
#databases = {
	#"db1": {
		#"data_path": conf.get_value(db_name, "data_path"),
		#"config_path": conf.get_value(db_name, "config_path"),
		#"tables": {
			#"table1": {
				#"comment": "",
				#"encrypted": "3423df23523fvsdgdfg",
				#"valid_if_not_exist": false,
				#"columns": [ # 可能为空
					#{
						#"AI": false,
						#"Column Name": "col1",
						#"Comment": "",
						#"Data Type": 4,
						#"Default(Expression)": "",
						#"Hint": 0,
						#"Hint String": "",
						#"NN": true,
						#"PK": false,
						#"UQ": false
					#}
				#]
			#}
		#},
		#"persistent": conf == _config_file, # 是否是持久化的
	#}
#}
var databases: Dictionary
var _inspector_search: LineEdit

## base_dao在query途中需要密码的情况时使用 [db_name, table_name]
var _request_password: Array

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		main_panel = null
		databases.clear()
		
		var root = EditorInterface.get_base_control().get_tree().get_root()
		var dialog_root = root.find_child("DialogRoot", false, false)
		if dialog_root:
			var dummy = Node.new()
			dialog_root.propagate_call("reparent", [dummy])
			dummy.remove_child(dialog_root)
			for i in dummy.get_children():
				if i is AcceptDialog:
					_clear_custom_dialog(i as AcceptDialog)
				else:
					i.print_tree_pretty()
					push_error("why there is a non-AcceptDialog (%s) here?!" % i.to_string())
			dialog_root.queue_free()
			
func _init() -> void:
	set_translation_domain("godot.editor")
	
## 返回某个节点是否运行在插件模式中。（脚本的@tool会让它运行在编辑器编辑界面中，而不是插件中，
## 可能导致信号多次绑定、额外数据被写入tscn中等问题）
func run_in_plugin(node: Node) -> bool:
	if main_panel == null:
		return false
	return node == main_panel or main_panel.is_ancestor_of(node)
	
func get_table_columns(db, table: String) -> Array:
	if databases:
		if table.ends_with(".gsql"):
			table = table.get_basename()
		return databases.get(db, {}).get("tables", {}).get(table, {})\
			.get("columns", [])
	return []
	
func get_table_columns_by_datapath(data_path, table: String) -> Array:
	if databases:
		if table.ends_with(".gsql"):
			table = table.get_basename()
		for db in databases:
			if databases[db]["data_path"] == data_path or \
			GDSQLUtils.globalize_path(databases[db]["data_path"]) == GDSQLUtils.globalize_path(data_path):
				return databases[db].get("tables", {}).get(table, {})\
					.get("columns", []).map(func(v): v["db_name"] = db; return v)
	return []
	
func get_table_valid_if_not_exist(data_path, table: String) -> bool:
	if databases:
		if table.ends_with(".gsql"):
			table = table.get_basename()
		for db in databases:
			if databases[db]["data_path"] == data_path or \
			GDSQLUtils.globalize_path(databases[db]["data_path"]) == GDSQLUtils.globalize_path(data_path):
				return databases[db].get("tables", {}).get(table, {}).get("valid_if_not_exist", false)
	return false
	
func _add_dialog(dialog: Window):
	var root = EditorInterface.get_base_control().get_tree().get_root()
	var dialog_root = root.find_child("DialogRoot", false, false)
	if dialog_root == null:
		dialog_root = Node.new()
		dialog_root.name = "DialogRoot"
		root.add_child(dialog_root, true)
	# 把新的对话框加到最深一层
	var p = dialog_root
	while p.get_child_count() > 0:
		for i: Window in p.get_children():
			if i and not i.is_queued_for_deletion():
				p = p.get_child(0)
				break
			else:
				# 能到这里说明上一个对话框正在关闭，把独占关闭一下，免得引擎报错，例如：
				# scene/main/window.cpp:886 - Attempting to make child window exclusive, 
				# but the parent window already has another exclusive child. This window: 
				# /root/DialogRoot/@ConfirmationDialog@23258, parent window: /root, 
				# current exclusive child window: /root/DialogRoot/@ConfirmationDialog@23219
				#printt("xxxxxxxxxxxxxx", p.get_child_count())
				#await root.create_tween().tween_interval(0.1).finished
				#dialog_root.print_tree_pretty()
				#printt("rrrrrrrr", dialog_root.get_root())
				i.exclusive = false
		break
	p.add_child(dialog)
	
func create_confirmation_dialog(msg: String, confirmed_callback: Callable = Callable(), canceled_callback: Callable = Callable()):
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = msg
	_add_dialog(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func():
		dialog.queue_free()
		if confirmed_callback.is_valid():
			confirmed_callback.call()
	, CONNECT_DEFERRED)
	dialog.canceled.connect(func():
		dialog.queue_free()
		if canceled_callback.is_valid():
			canceled_callback.call()
	, CONNECT_DEFERRED)
	
func create_accept_dialog(msg) -> void:
	if msg is Array:
		msg = " ".join(msg)
	var dialog := AcceptDialog.new()
	dialog.dialog_text = msg
	_add_dialog(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func():
		dialog.queue_free()
	, CONNECT_DEFERRED)
	dialog.close_requested.connect(func():
		dialog.queue_free()
	, CONNECT_DEFERRED)
	
var __property_old_parents = {}
var __custom_dialog_datas = {}
func _clear_custom_dialog(dialog: Window):
	if __property_old_parents.has(dialog):
		for i in __property_old_parents[dialog]:
			if i:
				disconnect_focused_propagate(i)
				if __property_old_parents[dialog][i].get_ref():
					i.reparent(__property_old_parents[dialog][i].get_ref())
				else:
					i.queue_free()
				
		__property_old_parents[dialog].clear()
	
	if dialog.is_node_ready() and __custom_dialog_datas.has(dialog):
		# 把自定义控件从树中剥离出来，不然会给下面的queue_free带来麻烦
		var datas = __custom_dialog_datas.get(dialog)
		if datas and !datas.is_empty():
			for arr in datas:
				for data in arr:
					if data is Control:
						if dialog.is_ancestor_of(data):
							data.get_parent_control().remove_child(data)
						
		var children = dialog.get_children()
		for i in children:
			if i and !i.is_queued_for_deletion():
				dialog.remove_child(i)
				i.queue_free()
				
	__property_old_parents.erase(dialog)
	__custom_dialog_datas.erase(dialog)
	dialog.hide()
	await get_tree().create_timer(1).timeout # For safety? After encountered several crash...
	if dialog:
		if dialog.get_parent():
			dialog.get_parent().remove_child(dialog)
		dialog.queue_free()
	
## 创建并弹出自定义对话框。
## 【datas】: 构建自定义对话框的数据，类似graph_node.gd，例如：
## [
## 		["please input somthing"],
## 		[dictObj1],
## 		[dictObj2],
## 		[contorl1],
## ]
## 注意：datas中的controls（不包括DictionaryObject）需要用户自行释放。
## 【confirmed_callback_before_close】：点击确定后执行的函数，必须返回一个长度为2的数组，第一个元素是布尔值，
## true表示保留对话框，false表示关闭对话框。第二个元素用于用户传递一些数据。
## 【canceled_callback_before_close】：点击取消或关闭按钮后执行的函数，必须返回一个长度为2的数组，
## 第一个元素是布尔值，true表示保留对话框，false表示关闭对话框。第二个元素用于用户传递一些数据。
## 【defered_callback】：对话框关闭后执行的函数。可以把对话框关闭后要执行的逻辑（比如释放自定义control等）
## 放入defered_callback中。需接收2个参数：
## 参数1：bool，true表示用户点击的是“确定”，false表示用户点击的是“取消”或“关闭”
## 参数2：请勿指定数据类型，其值等于confirmed_callback_before_close或canceled_callback_before_close返回数组的第二个元素。
func create_custom_dialog(datas: Array[Array],
confirmed_callback_before_close: Callable = Callable(), 
canceled_callback_before_close: Callable = Callable(),
defered_callback: Callable = Callable(),
ratio: float = 0.0) -> ConfirmationDialog:
	var inspect_change = false # 是否检查了某个obj
	var dialog := ConfirmationDialog.new()
	dialog.dialog_hide_on_ok = false
	__custom_dialog_datas[dialog] = datas
	__property_old_parents[dialog] = {}
	# 确定
	dialog.confirmed.connect(func():
		var close = true
		var ret
		if confirmed_callback_before_close.is_valid():
			ret = await confirmed_callback_before_close.call()
			assert(ret is Array and ret.size() == 2 and ret[0] is bool, 
				"Return value of confirmed_callback_before_close must be a 2-elements-array(first element must be a bool)!")
			if ret[0] == true:
				close = false
				
		if close:
			_clear_custom_dialog(dialog)
			if defered_callback.is_valid():
				defered_callback.call(true, ret[1] if ret is Array else null)
	, CONNECT_DEFERRED)
	# 取消、关闭（关闭也会触发canceled）
	dialog.canceled.connect(func():
		var close = true
		var ret
		if canceled_callback_before_close.is_valid():
			ret = await canceled_callback_before_close.call()
			assert(ret is Array and ret.size() == 2 and ret[0] is bool, 
				"Return value of canceled_callback_before_close must be a 2-elements-array(first element must be a bool)!")
			if ret[0] == true:
				close = false
				
		if close:
			_clear_custom_dialog(dialog)
			if defered_callback.is_valid():
				defered_callback.call(false, ret[1] if ret is Array else null)
	, CONNECT_DEFERRED)
	_add_dialog(dialog)
	if ratio == 0:
		dialog.popup_centered()
	else:
		dialog.popup_centered_ratio(ratio)
		
	var vbox_container = VBoxContainer.new()
	#vbox_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dialog.add_child(vbox_container)
	
	for arr in datas:
		var hb = HBoxContainer.new()
		#var has_content = false
		for data in arr:
			if data == null:
				hb.add_child(Control.new())
			else:
				if data is bool:
					#has_content = true
					var cb = CheckBox.new()
					cb.button_pressed = data
					cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					hb.add_child(cb)
				elif data is String or data is int or data is float:
					if data is String and data == "":
						hb.add_child(Control.new())
					else:
						#has_content = true
						var label = Label.new()
						label.text = str(data)
						label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
						label.localize_numeral_system = false
						label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						hb.add_child(label)
				elif data is DictionaryObject:
					#has_content = true
					# 一些控件依赖inspector，为了简化，所有情况都使用inspector。
					# 比如：EditorPropertyResource，如果不放到一个inspector中的话，reparent的时候（它想折叠资源）会报错，影响体验。
					var inspector = EditorInspector.new()
					inspector.queue_redraw()
					inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
					inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
					hb.add_child(inspector)
					
					# 允许用户使用垂直方式排列属性（默认横向）
					var p_container
					if data.get_meta("align", "horizontal") == "vertical":
						p_container = VBoxContainer.new()
					else:
						p_container = HBoxContainer.new()
					p_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					p_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
					hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					inspector.add_child(p_container)
					
					# 去掉筛选属性里的文字，否则有些属性不会被渲染出来
					if not _inspector_search:
						var editor_inspector = EditorInterface.get_inspector()
						var inspector_dock = editor_inspector.get_parent()
						var line_edits = inspector_dock.find_children("@LineEdit*", "LineEdit", true, false)
						for l: LineEdit in line_edits:
							if l.placeholder_text in ["Filter Properties", tr("Filter Properties")]:
								_inspector_search = l
								break
					assert(_inspector_search != null, "Cannot find inspector search!")
					var old_search_content = _inspector_search.text
					_inspector_search.text = ""
					
					EditorInterface.inspect_object(data)
					inspect_change = true
					var properties = data._get_property_list()\
						#.filter(func(v):
						#return not (v["usage"] & PROPERTY_USAGE_CATEGORY or v["usage"] & PROPERTY_USAGE_GROUP \
							#or v["usage"] & PROPERTY_USAGE_SUBGROUP))
						.map(func(v): return v["name"])
					var editor_properties = EditorInterface.get_inspector().find_children("@EditorProperty*", "", true, false)
					var v_box_container = get_inspector_main_vbox()
					for i in v_box_container.get_children(true):
						var need = false
						for editor_property in editor_properties:
							if editor_property is not EditorProperty:
								continue
								
							var prop_name = (editor_property as EditorProperty).get_edited_property()
							if prop_name not in properties:
								continue
								
							if i.is_ancestor_of(editor_property):
								need = true
								break
								
						if need:
							__property_old_parents[dialog][i] = weakref(v_box_container)
							i.reparent(p_container, false)
							i.size_flags_horizontal = Control.SIZE_EXPAND_FILL
							
					for editor_property in editor_properties:
						if editor_property is not EditorProperty:
							continue
							
						var prop_name = (editor_property as EditorProperty).get_edited_property()
						if prop_name not in properties:
							continue
							
						# 只有让检查器显示这个属性，才能修改这个属性。否则修改的是检查器当前显示的属性。
						connect_focused_propagate(editor_property, data)
						editor_property.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						editor_property.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
						
						# 下划线开头的隐藏label。隐藏方法是把控件整个添加到一个能按比例隐藏子控件的控件中
						if prop_name.begins_with("_") and not editor_property.name.contains("EditorPropertyMultilineText")\
						and not editor_property.name.contains("EditorPropertyArray"):
							__property_old_parents[editor_property] = weakref(editor_property.get_parent())
							var container = preload("res://addons/gdsql/tabs/sql_graph_node/cut_control.tscn").instantiate()
							container.name += str(randi() % 100)
							container.invisible_ratio = 0.5
							container.set_meta("cut_control", true)
							editor_property.add_sibling(container)
							container.control = editor_property
							
					# 恢复原来的筛选属性
					_inspector_search.text = old_search_content
				elif data is Control:
					#has_content = true
					if data.get_parent() and data.get_parent() != hb:
						data.reparent(hb)
					else:
						hb.add_child(data)
		#if hb.get_child_count() == 0 or not has_content:
		hb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		#else:
			#hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox_container.add_child(hb)
		
	# 自动聚焦到第一个输入组件上
	var editable_control = _find_editable_control(vbox_container)
	if editable_control:
		editable_control.grab_focus()
		
	# 注册回车键的输入组件
	var last_line_edit = _find_last_line_edit(vbox_container)
	if last_line_edit:
		dialog.register_text_enter(last_line_edit)
		
	# 检视一下null，否则会停留在检查某个dictionary_object，导致修改最后一条属性的时候可能会产生显示上的不统一
	if inspect_change:
		EditorInterface.inspect_object(null)
		
	return dialog
	
## 创建并弹出自定义对话框。
## 【datas】: 构建自定义对话框的数据，类似graph_node.gd，例如：
## [
## 		["please input somthing"],
## 		[dictObj1],
## 		[dictObj2],
## 		[contorl1],
## ]
## 注意：datas中的controls（不包括DictionaryObject）需要用户自行释放。
## 【confirmed_callback_before_close】：点击确定后执行的函数，必须返回一个长度为2的数组，第一个元素是布尔值，
## true表示保留对话框，false表示关闭对话框。第二个元素用于用户传递一些数据。
## 【canceled_callback_before_close】：点击取消或关闭按钮后执行的函数，必须返回一个长度为2的数组，
## 第一个元素是布尔值，true表示保留对话框，false表示关闭对话框。第二个元素用于用户传递一些数据。
## 【defered_callback】：对话框关闭后执行的函数。可以把对话框关闭后要执行的逻辑（比如释放自定义control等）
## 放入defered_callback中。需接收2个参数：
## 参数1：bool，true表示用户点击的是“确定”，false表示用户点击的是“取消”或“关闭”
## 参数2：请勿指定数据类型，其值等于confirmed_callback_before_close或canceled_callback_before_close返回数组的第二个元素。
func create_custom_popup_panel(datas: Array[Array],
position: Vector2,
canceled_callback_before_close: Callable = Callable(),
defered_callback: Callable = Callable(),
min_size: Vector2i = Vector2i.ZERO) -> PopupPanel:
	#var dialog := ConfirmationDialog.new()
	var dialog := PopupPanel.new()
	#dialog.dialog_hide_on_ok = false
	__custom_dialog_datas[dialog] = datas
	__property_old_parents[dialog] = {}
	dialog.popup_hide.connect(func():
		var close = true
		var ret
		if canceled_callback_before_close.is_valid():
			ret = await canceled_callback_before_close.call()
			assert(ret is Array and ret.size() == 2 and ret[0] is bool, 
				"Return value of canceled_callback_before_close must be a 2-elements-array(first element must be a bool)!")
			if ret[0] == true:
				close = false
				
		if close:
			_clear_custom_dialog(dialog)
			if defered_callback.is_valid():
				defered_callback.call(false, ret[1] if ret is Array else null)
	, CONNECT_DEFERRED)
	_add_dialog(dialog)
	
	var vbox_container = VBoxContainer.new()
	vbox_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dialog.add_child(vbox_container)
	
	for arr in datas:
		var hb = HBoxContainer.new()
		#var has_content = false
		for data in arr:
			if data == null:
				hb.add_child(Control.new())
				hb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			else:
				if data is bool:
					hb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
					#has_content = true
					var cb = CheckBox.new()
					cb.button_pressed = data
					cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					hb.add_child(cb)
				elif data is String or data is int or data is float:
					hb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
					if data is String and data == "":
						hb.add_child(Control.new())
					else:
						#has_content = true
						var label = Label.new()
						label.text = str(data)
						label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
						label.localize_numeral_system = false
						label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						hb.add_child(label)
				elif data is DictionaryObject:
					#has_content = true
					hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
					# 一些控件依赖inspector，为了简化，所有情况都使用inspector。
					# 比如：EditorPropertyResource，如果不放到一个inspector中的话，reparent的时候（它想折叠资源）会报错，影响体验。
					var inspector = EditorInspector.new()
					inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
					hb.add_child(inspector)
					
					var v_box = VBoxContainer.new()
					v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					v_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
					inspector.add_child(v_box)
					
					# 去掉筛选属性里的文字，否则有些属性不会被渲染出来
					if not _inspector_search:
						var editor_inspector = EditorInterface.get_inspector()
						var inspector_dock = editor_inspector.get_parent()
						var line_edits = inspector_dock.find_children("@LineEdit*", "LineEdit", true, false)
						for l: LineEdit in line_edits:
							if l.placeholder_text in ["Filter Properties", tr("Filter Properties")]:
								_inspector_search = l
								break
					assert(_inspector_search != null, "Cannot find inspector search!")
					var old_search_content = _inspector_search.text
					_inspector_search.text = ""
					
					EditorInterface.inspect_object(data)
					# 全部展开（方便用户修改数据）
					await EditorInterface.get_base_control().get_tree().process_frame
					for i: MenuButton in EditorInterface.get_inspector().get_parent().\
						find_children("@MenuButton*", "MenuButton", true, false):
						if i.tooltip_text in ["Manage object properties.", tr("Manage object properties.")]:
							i.get_popup().emit_signal("id_pressed", 12) # 12 is for EXPAND_ALL, @see editor\inspector_dock.h
							break
							
					var plist = data._get_property_list().filter(func(v):
						return not (v["usage"] & PROPERTY_USAGE_CATEGORY or v["usage"] & PROPERTY_USAGE_GROUP \
							or v["usage"] & PROPERTY_USAGE_SUBGROUP))
					var properties = plist.map(func(v): return v["name"])
					
					if properties.size() < 5:
						inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
						inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
						
					var editor_properties = EditorInterface.get_inspector().find_children("@EditorProperty*", "", true, false)
					# 只改一条属性，则不用显示属性名称（某些情况除外，比如多行文本、数组）
					if properties.size() == 1 and plist[0].hint != PROPERTY_HINT_MULTILINE_TEXT and \
					plist[0].type != TYPE_ARRAY:
						for editor_property in editor_properties:
							if editor_property is not EditorProperty:
								continue
								
							var prop_name = (editor_property as EditorProperty).get_edited_property()
							if prop_name not in properties:
								continue
								
							editor_property.size_flags_horizontal = Control.SIZE_EXPAND_FILL
							__property_old_parents[dialog][editor_property] = weakref(editor_property.get_parent())
							var container = preload("res://addons/gdsql/tabs/sql_graph_node/cut_control.tscn").instantiate()
							container.name += str(randi() % 100)
							container.invisible_ratio = 0.5
							container.control = editor_property
							v_box.add_child(container)
					else:
						min_size.x *= 2
						var v_box_container = get_inspector_main_vbox()
						for i in v_box_container.get_children(true):
							var need = false
							for editor_property in editor_properties:
								if editor_property is not EditorProperty:
									continue
									
								var prop_name = (editor_property as EditorProperty).get_edited_property()
								if prop_name not in properties:
									continue
									
								if i.is_ancestor_of(editor_property):
									need = true
									break
									
							if need:
								__property_old_parents[dialog][i] = weakref(v_box_container)
								i.reparent(v_box)
								
					for editor_property in editor_properties:
						if editor_property is not EditorProperty:
							continue
							
						var prop_name = (editor_property as EditorProperty).get_edited_property()
						if prop_name not in properties:
							continue
							
						# 只有让检查器显示这个属性，才能修改这个属性。否则修改的是检查器当前显示的属性。
						connect_focused_propagate(editor_property, data)
						
					_inspector_search.text = old_search_content
				elif data is Control:
					hb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
					#has_content = true
					if data.get_parent() and data.get_parent() != hb:
						data.reparent(hb)
					else:
						hb.add_child(data)
		#if hb.get_child_count() == 0 or not has_content:
		#hb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		#else:
			#hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox_container.add_child(hb)
		
	# 自动聚焦到第一个输入组件上
	var editable_control = _find_editable_control(vbox_container)
	if editable_control:
		editable_control.grab_focus()
		
	# 注册回车键的输入组件
	#var last_line_edit = _find_last_line_edit(vbox_container)
	#if last_line_edit:
		#dialog.register_text_enter(last_line_edit)
		
	dialog.position = position
	dialog.min_size = min_size
	dialog.popup()
	return dialog
	
## 弹出用户提供的对话框或window
## 【confirmed_callback_before_close】：点击确定后执行的函数，必须返回一个长度为2的数组，第一个元素是布尔值，
## true表示保留对话框，false表示关闭对话框。第二个元素用于用户传递一些数据。
## 【canceled_callback_before_close】：点击取消或关闭按钮后执行的函数，必须返回一个长度为2的数组，
## 第一个元素是布尔值，true表示保留对话框，false表示关闭对话框。第二个元素用于用户传递一些数据。
## 【defered_callback】：对话框关闭后执行的函数。可以把对话框关闭后要执行的逻辑（比如释放自定义control等）
## 放入defered_callback中。需接收2个参数：
## 参数1：bool，true表示用户点击的是“确定”，false表示用户点击的是“取消”或“关闭”
## 参数2：请勿指定数据类型，其值等于confirmed_callback_before_close或canceled_callback_before_close返回数组的第二个元素。
func popup_user_dialog(dialog: Window, 
confirmed_callback_before_close: Callable = Callable(), 
canceled_callback_before_close: Callable = Callable(),
defered_callback: Callable = Callable(),
ratio: float = 0.0):
	__property_old_parents[dialog] = {}
	# 确定
	if dialog.has_signal("confirmed"):
		dialog.confirmed.connect(func():
			var close = true
			var ret
			if confirmed_callback_before_close.is_valid():
				ret = await confirmed_callback_before_close.call()
				assert(ret is Array and ret.size() == 2 and ret[0] is bool, 
					"Return value of confirmed_callback_before_close must be a 2-elements-array(first element must be a bool)!")
				if ret[0] == true:
					close = false
					
			if close:
				_clear_custom_dialog(dialog)
				if defered_callback.is_valid():
					defered_callback.call(true, ret[1] if ret is Array else null)
		, CONNECT_DEFERRED)
	# 取消、关闭（关闭也会触发canceled）
	if dialog.has_signal("canceled"):
		dialog.canceled.connect(func():
			var close = true
			var ret
			if canceled_callback_before_close.is_valid():
				ret = await canceled_callback_before_close.call()
				assert(ret is Array and ret.size() == 2 and ret[0] is bool, 
					"Return value of canceled_callback_before_close must be a 2-elements-array(first element must be a bool)!")
				if ret[0] == true:
					close = false
					
			if close:
				_clear_custom_dialog(dialog)
				if defered_callback.is_valid():
					defered_callback.call(false, ret[1] if ret is Array else null)
		, CONNECT_DEFERRED)
	_add_dialog(dialog)
	if ratio == 0:
		dialog.popup_centered()
	else:
		dialog.popup_centered_ratio(ratio)
		
func _find_editable_control(control: Node) -> Control:
	if control is LineEdit:
		control.select_all_on_focus = true
		return control
		
	if control is TextEdit:
		control.select_all()
		return control
		
	if control.name.contains("EditorSpinSlider"):
		control.focus_entered.connect(func():
			await control.get_tree().create_timer(0.1).timeout
			var popup = (control.find_parent("@PopupPanel*") as PopupPanel)
			if popup == null:
				return
			var e = InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
			e.pressed = true
			e.position = control.global_position + control.size/2
			popup.push_input(e)
			await control.get_tree().create_timer(0.1).timeout
			e = InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
			e.pressed = false
			e.position = control.global_position + control.size/2
			popup.push_input(e)
		, CONNECT_ONE_SHOT)
		return control
		
	for i in control.get_children(true):
		var c = _find_editable_control(i)
		if c:
			return c
	return null
	
func _find_last_line_edit(control: Node) -> Control:
	var ret = null
	if control is LineEdit:
		ret = control
		
	for i in control.get_children(true):
		var c = _find_last_line_edit(i)
		if c:
			ret = c
	return ret
	
	
func connect_focused_propagate(control: Control, data):
	for child in control.get_children(true):
		if child is Control:
			connect_focused_propagate(child, data)
			if child.mouse_filter != Control.MOUSE_FILTER_IGNORE and child.has_signal("focus_entered"):
				if not (child as Control).is_connected("focus_entered", editor_property_focused):
					child.focus_entered.connect(editor_property_focused.bind(data), CONNECT_DEFERRED)
					
func disconnect_focused_propagate(control: Control):
	for child in control.get_children(true):
		if child is Control:
			disconnect_focused_propagate(child)
			if (child as Control).is_connected("focus_entered", editor_property_focused):
				child.focus_entered.disconnect(editor_property_focused)
				
func editor_property_focused(data):
	EditorInterface.inspect_object(data)
	
func need_request_password(db_name: String, table_name: String, try_password: String) -> bool:
	var result = []
	need_user_enter_password.emit(db_name, table_name, try_password, result)
	assert(not result.is_empty(), "Err occur!")
	if result[0]:
		_request_password.clear()
		_request_password.push_back(db_name)
		_request_password.push_back(table_name)
	return result[0]
	
func request_curr_password(result: Array):
	request_user_enter_password.emit(_request_password[0], _request_password[1], "", func():
		_request_password.clear()
		result[0] = true
	, func():
		result[0] = false
	)
	
func has_password_request() -> bool:
	return not _request_password.is_empty()
	
func get_password_request_table():
	return _request_password
	
static func get_inspector_main_vbox() -> VBoxContainer:
	# 4.4.dev5增加了一个功能，导致vbox有变化
	# Make possible to favorite properties in the inspector 
	# https://github.com/godotengine/godot/pull/97415
	if Engine.get_version_info().hex > 0x040400 or \
	ClassDB.class_has_signal(&"EditorProperty", &"property_favorited"):
		return EditorInterface.get_inspector().get_child(0, true).get_child(2, true)
	# 以前的版本：
	else:
		return EditorInterface.get_inspector().get_child(0, true)

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
	password: String, columns: Array, id: String)
## 系统确认新建数据表的信号
signal sys_confirm_add_table(id: String)

## 打开修改数据表标签页的信号
signal open_alter_table_tab(db_name: String, table_name: String)
## 用户确认修改数据表的信号
signal user_confirm_alter_table(sechema: String, old_table_name: String, new_table_name: String, 
	comments: String, columns: Array, id: String)
## 系统确认修改数据表的信号
signal sys_confirm_alter_table(id: String)

## 打开数据表检查器页签的信号
signal open_table_inspector_tab(db_name: String, table_name: String)
## 打开数据表导出页签的信号
signal open_table_data_export_tab(db_name: String, table_name: String)
## 打开数据表导入页签的信号
signal open_table_data_import_tab(db_name: String, table_name: String)
## 请求用户输入数据表密码的信号
signal request_user_enter_password(db_name: String, table_name: String, try_password: String, callback: Callable)

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
				#"comment": ""
				#"encrypted": "3423df23523fvsdgdfg"
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

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		main_panel = null
		databases.clear()
		
		var root = EditorInterface.get_base_control().get_tree().get_root()
		var dialog_root = root.find_child("DialogRoot", false, false)
		if dialog_root != null:
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

## 返回某个节点是否运行在插件模式中。（脚本的@tool会让它运行在编辑器编辑界面中，而不是插件中，
## 可能导致信号多次绑定、额外数据被写入tscn中等问题）
func run_in_plugin(node: Node) -> bool:
	if main_panel == null:
		return false
	return node == main_panel or main_panel.is_ancestor_of(node)

func get_table_columns(db, table) -> Array:
	if databases:
		return databases.get(db, {}).get("tables", {}).get(table, {})\
			.get("columns", [])
	return []
	
func _add_dialog(dialog: AcceptDialog):
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
			if i != null and not i.is_queued_for_deletion():
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
func _clear_custom_dialog(dialog: AcceptDialog):
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
			if i != null and !i.is_queued_for_deletion():
				dialog.remove_child(i)
				i.queue_free()
				
	__property_old_parents.erase(dialog)
	__custom_dialog_datas.erase(dialog)
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
defered_callback: Callable = Callable()):
	var dialog := ConfirmationDialog.new()
	dialog.dialog_hide_on_ok = false
	__custom_dialog_datas[dialog] = datas
	__property_old_parents[dialog] = {}
	# 确定
	dialog.confirmed.connect(func():
		var close = true
		var ret
		if confirmed_callback_before_close.is_valid():
			ret = confirmed_callback_before_close.call()
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
			ret = canceled_callback_before_close.call()
			assert(ret is Array and ret.size() == 2 and ret[0] is bool, 
				"Return value of canceled_callback_before_close must be a 2-elements-array(first element must be a bool)!")
			if ret == true:
				close = false
				
		if close:
			_clear_custom_dialog(dialog)
			if defered_callback.is_valid():
				defered_callback.call(false, ret[1] if ret is Array else null)
	, CONNECT_DEFERRED)
	_add_dialog(dialog)
	dialog.popup_centered()
	
	var vbox_container = VBoxContainer.new()
	vbox_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(vbox_container)
	
	for arr in datas:
		var hb = HBoxContainer.new()
		var has_content = false
		for data in arr:
			if data == null:
				hb.add_child(Control.new())
			else:
				if data is String or data is int or data is float:
					if data is String and data == "":
						hb.add_child(Control.new())
					else:
						has_content = true
						var label = Label.new()
						label.text = str(data)
						label.auto_translate = false
						label.localize_numeral_system = false
						label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						hb.add_child(label)
				elif data is DictionaryObject:
					has_content = true
					EditorInterface.inspect_object(data)
					var properties = data._get_property_list().map(func(v): return v["name"])
					var editor_properties = EditorInterface.get_inspector().find_children("@EditorProperty*", "", true, false)
					for i in properties.size():
						# 下划线开头的隐藏label。隐藏方法是把控件整个添加到一个能按比例隐藏子控件的控件中
						var editor_property = editor_properties[i]
						# 只有让检查器显示这个属性，才能修改这个属性。否则修改的是检查器当前显示的属性。
						connect_focused_propagate(editor_property, data)
						__property_old_parents[dialog][editor_property] = weakref(editor_property.get_parent())
						editor_property.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						editor_property.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
						if (properties[i] as String).begins_with("_"):
							var container = preload("res://addons/gdsql/tabs/sql_graph_node/cut_control.tscn").instantiate()
							container.invisible_ratio = 0.5
							container.control = editor_property
							hb.add_child(container)
						else:
							editor_property.reparent(hb)
							
				elif data is Control:
					has_content = true
					if data.get_parent() != null and data.get_parent() != hb:
						data.reparent(hb)
					else:
						hb.add_child(data)
		if hb.get_child_count() == 0 or not has_content:
			hb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		else:
			hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox_container.add_child(hb)
		
	# 自动聚焦到第一个输入组件上
	var editable_control = _find_editable_control(vbox_container)
	if editable_control != null:
		editable_control.grab_focus()
		
	# 注册回车键的输入组件
	var last_line_edit = _find_last_line_edit(vbox_container)
	if last_line_edit != null:
		dialog.register_text_enter(last_line_edit)
		
func _find_editable_control(control: Node) -> Control:
	if control is LineEdit or control is TextEdit:
		return control
		
	for i in control.get_children(true):
		var c = _find_editable_control(i)
		if c != null:
			return c
	return null
	
func _find_last_line_edit(control: Node) -> Control:
	var ret = null
	if control is LineEdit:
		ret = control
		
	for i in control.get_children(true):
		var c = _find_last_line_edit(i)
		if c != null:
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

## 执行一个表达式
## target：环境对象。比如command里使用的一些函数、变量是在target里定义的
## command：表达式
## variable_names：参数名称列表
## variable_values：参数值列表
func evaluate_command(target: Object, command: String, variable_names = [], variable_values = []):
	var expression = Expression.new()
	var error = expression.parse(command, variable_names)
	if error != OK:
		push_error(expression.get_error_text())
		return null
		
	return expression.execute(variable_values, target, false)

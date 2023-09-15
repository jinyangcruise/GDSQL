extends Node
class_name GDSQLWorkbenchManagerClass

## 打开新建数据库标签页的信号
signal open_add_schema_tab
## 用户确认新建数据库的信号
signal user_confirm_add_schema(db_name: String, path: String, save: bool, id: String)
## 系统确认新建数据库的信号
signal sys_confirm_add_schema(id: String)

## 打开修改数据库标签页的信号
signal open_alter_schema_tab(db_name: String, path: String, save: bool)
## 用户确认修改数据库的信号
signal user_confirm_alter_schema(old_db_name: String, new_db_name: String, path: String, save: bool, id: String)
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

## 发送到编辑器
signal send_to_editor(content: String)
## 发送到编辑器并执行的信号
signal send_to_editor_and_execute(title: String, info: Dictionary)

## 记录操作日志
signal add_log_history(status: String, begin_timestamp: String, action: String, message: String)

## 数据库配置
#databases = {
	#"db1": {
		#"name": conf.get_value(db_name, "name"),
		#"path": conf.get_value(db_name, "path"),
		#"table_items": {
			#"table1": {
				#"table_name": "",
				#"file_name": "",
				#"path": ""
				#"comment": ""
				#"encrypted": false/true
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

func get_table_columns(db, table) -> Array:
	if databases:
		return databases.get(db, {}).get("table_items", {}).get(table, {})\
			.get("columns", [])
	return []

func create_confirmation_dialog(msg: String, confirmed_callback: Callable = Callable(), canceled_callback: Callable = Callable()):
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = msg
	if confirmed_callback.is_valid():
		dialog.confirmed.connect(confirmed_callback)
	if canceled_callback.is_valid():
		dialog.canceled.connect(canceled_callback)
	EditorInterface.get_base_control().get_tree().get_root().add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(func():
		if canceled_callback.is_valid():
			canceled_callback.call()
		dialog.queue_free()
	)
	
func create_accept_dialog(msg: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.dialog_text = msg
	EditorInterface.get_base_control().get_tree().get_root().add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(func():
		dialog.queue_free()
	)
	
## 利用DictionaryObject来产生自定义对话框。类似graph_node.gd
## [
## 		["please input somthing"],
## 		[dictObj1],
## 		[dictObj2],
## 		[contorl1],
## ]
func create_custom_dialog(datas: Array[Array], confirmed_callback: Callable = Callable(), canceled_callback: Callable = Callable()):
	var dialog := ConfirmationDialog.new()
	if confirmed_callback.is_valid():
		dialog.confirmed.connect(confirmed_callback)
	if canceled_callback.is_valid():
		dialog.canceled.connect(canceled_callback)
	EditorInterface.get_base_control().get_tree().get_root().add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(func():
		if canceled_callback.is_valid():
			canceled_callback.call()
		dialog.queue_free()
	)
	
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
	
func connect_focused_propagate(control: Control, data):
	for child in control.get_children(true):
		if child is Control:
			connect_focused_propagate(child, data)
			if child.mouse_filter != Control.MOUSE_FILTER_IGNORE and child.has_signal("focus_entered"):
				if not (child as Control).is_connected("focus_entered", editor_property_focused):
					child.focus_entered.connect(editor_property_focused.bind(data))
					
func editor_property_focused(data):
	EditorInterface.inspect_object(data)

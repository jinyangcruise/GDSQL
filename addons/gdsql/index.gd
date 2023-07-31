@tool
extends MarginContainer

## 通过该信号可以把需要在检查器中查看的对象发送给EditorInterface
signal inspect_object(object: Object, for_property: String, inspector_only: bool)

@onready var tree_databases: Tree = $VBoxContainer/HSplitContainer/VBoxContainer/TreeDatabases
@onready var tab_container: TabContainer = $VBoxContainer/HSplitContainer/VSplitContainer/TabContainer
@onready var log_table: VBoxContainer = $VBoxContainer/HSplitContainer/VSplitContainer/Control/VBoxContainer/LogTable


func _ready() -> void:
	tree_databases.new_schema.connect(tab_container.add_tab_new_schema) # 发出新建数据库的请求
	tree_databases.alter_schema.connect(tab_container.add_tab_alter_schema) # 发出修改数据库的请求
	tab_container.add_new_schema.connect(tree_databases.add_db_to_config) # 确认新增数据库的信息
	tree_databases.add_db_to_config_success.connect(tab_container.close_content_window) # 确认新增数据库成功
	tab_container.alter_old_schema.connect(tree_databases.modify_db_to_config) # 确认修改数据库的信息
	tree_databases.modify_db_to_config_success.connect(tab_container.close_content_window) # 确认修改数据库成功
	tree_databases.new_table.connect(tab_container.add_tab_new_table) # 发出新建数据表的请求
	tab_container.add_new_table.connect(tree_databases.add_table_to_config) # 确认新增数据表
	tree_databases.send_to_editor.connect(tab_container.receive_content) # 发出发送到编辑器内容的请求
	tree_databases.send_to_editor_and_execute.connect(tab_container.receive_content_and_execute) # 发出发送到编辑器内容并执行的请求
	
	tab_container.inspect_object.connect(transfer_inspect_object)
	log_table.inspect_object.connect(transfer_inspect_object)
	
	#var dic_obj := DictionaryObject.new({
		#"Status": true,
		#"#": 1,
		#"Time": "09:30:22",
		#"Action": "UPDATE T_USER SET UNAME = 'PETER' WHERE ID = 1",
		#"Message": "2 rows affected",
		#"Duration": "0.0001 sec",
	#})
	#log_table.datas = [dic_obj]

func _on_button_refresh_pressed() -> void:
	tree_databases.refresh()
	
func transfer_inspect_object(object: Object, for_property: String, inspector_only: bool):
	inspect_object.emit(object, for_property, inspector_only)

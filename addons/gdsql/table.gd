@tool
extends Control

@onready var header: MarginContainer = $VBoxContainer/Header
@onready var header_col_model: Control = $HSplitContainer/HeaderColModel
@onready var v_box_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer
@onready var row_model: HBoxContainer = $Models/RowModel
@onready var label_model: Label = $Models/LabelModel




@export var colums: Array[String]:
	set(val):
		colums = val
		if is_node_ready():
			reset_header()
			
@export var datas: Array[Array]:
	set(val):
		datas = val
		if is_node_ready():
			clear_rows()
			for data in datas:
				var d = data.duplicate()
				add_row(d)
		
		
@export var buttons: Array[Button] = []
var controls: Array = []

func _ready() -> void:
	reset_header()
	await await create_tween().tween_callback(func(): return).set_delay(1).finished
	datas = datas
	await await create_tween().tween_callback(func(): return).set_delay(0.5).finished
	realign_rows()
	

func reset_header():
	buttons.clear()
	controls.clear()
	
	if header.get_child_count() > 0:
		var h = header.get_child(0)
		header.remove_child(h)
		h.queue_free()
	
	var fake_columns = [""]
	fake_columns.append_array(colums)
	fake_columns.push_back("")
	
	var parent = header
	for i in fake_columns.size():
		var c: HSplitContainer = header_col_model.duplicate()
		parent.add_child(c)
		var split_container_dragger = c.get_child(c.get_child_count(true)-1, true)
		split_container_dragger.gui_input.connect(_on_dragger_gui_input.bind(c))
		var button = c.get_child(0)
		var control = c.get_child(1)
		if i == 0:
			button.hide()
			control.size_flags_stretch_ratio = 10000
			c.dragger_visibility = HSplitContainer.DRAGGER_HIDDEN_COLLAPSED
		elif i == fake_columns.size() - 2:
			button.size_flags_stretch_ratio = 10000
			c.dragger_visibility = HSplitContainer.DRAGGER_HIDDEN_COLLAPSED
		else:
			control.size_flags_stretch_ratio = fake_columns.size() - i - 2
			
		if i == fake_columns.size() - 1:
			button.hide()
			
		button.text = fake_columns[i]
		parent = control
		buttons.push_back(button)
		if i < fake_columns.size() - 1:
			controls.push_back(control)
		
		c.dragged.connect(_on_header_col_model_dragged.bind(c))
		
	# 把最后一个空control删掉，免得占空间
	parent.queue_free()
	clear_rows()
	
func _on_header_col_model_dragged(offset: int, h_split_container: HSplitContainer) -> void:
	var child_button: Button = h_split_container.get_child(0)
	var child_control = h_split_container.get_child(1)
	child_control.custom_minimum_size.x = 1
	await get_tree().process_frame
	await get_tree().process_frame
	var next_h_split_container: HSplitContainer = child_control.get_child(0)
	next_h_split_container.size.x = child_control.size.x
	realign_rows()
	
func add_row(data: Array):
	data.insert(0, "")
	data.push_back("")
	var a_row = row_model.duplicate()
	v_box_container.add_child(a_row)
	a_row.show()
	var control: Control
	for i in data.size():
		match typeof(data[i]):
			_:
				control = label_model.duplicate()
				control.text = str(data[i])
		
		a_row.add_child(control)
		if i == 0 or i == data.size() - 1:
			control.hide()
		control.size_flags_stretch_ratio = buttons[i].size.x + 4 # HSplitContainer间隔为8，两边各取一半
		
func clear_rows():
	while v_box_container.get_child_count() > 0:
		var r = v_box_container.get_child(0)
		v_box_container.remove_child(r)
		r.queue_free()
		
func realign_rows():
	for row in v_box_container.get_children():
		for i in row.get_child_count():
			row.get_child(i).size_flags_stretch_ratio = buttons[i].size.x + 4
		
func _on_button_pressed() -> void:
	realign_rows()
#	print_tree_pretty()
#	for button in buttons:
#		var parent = button.get_parent()
#		var splitCol = parent.get_parent()
#		printt(button.size_flags_horizontal, button.size.x, splitCol, splitCol.size_flags_horizontal, splitCol.size.x)
		
func _on_dragger_gui_input(event: InputEvent, split_container: HSplitContainer):
	# 让control不要自动填充
	if event is InputEventMouseButton:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			for control in controls:
				if control.size_flags_horizontal == Control.SIZE_EXPAND_FILL:
					control.custom_minimum_size = control.size
					control.size_flags_horizontal = Control.SIZE_FILL
		else:
			for control in controls:
				control.custom_minimum_size = control.size
			

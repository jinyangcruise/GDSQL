@tool
extends MarginContainer

signal row_clicked(row_index: int, mouse_button_index: int, data)
signal row_deleted(datas)

# ── Exports ──────────────────────────────────────────────────────────────────

## 表格是否可编辑（datas中的元素必须是DictionaryObject才有效）
@export var editable: bool = false
## 是否显示默认的右键菜单
@export var show_menu: bool = false
## 是否支持从右键菜单delete行
@export var support_delete_row: bool = false
## 是否支持多行选择（高亮）
@export var support_multi_rows_selected: bool = false
## 是否支持显示选择框
@export var support_select_border: bool = true
## 是否显示外纵向框架1\2\3\4...
@export var show_frame: bool = false
## 行的高度是否进行扩展并填充（v3固定行高，设为true相当于填充可用高度）
@export var row_expend_and_fill: bool = false
## 是否显示网格线（类似Excel）
@export var show_grid: bool = false:
	set(val):
		show_grid = val
		if is_node_ready():
			borders_overlay.queue_redraw()

## 每列的名称。注意：如果要正确显示tooltip，需要先设置column_tips，再设置columns
@export var columns: Array:
	set(val):
		columns = val
		if is_node_ready():
			rebuild_header()
			if datas.size() > 0:
				_on_scroll(scroll_container.scroll_vertical)

@export var label_max_lines_visible: int = 1:
	set(val):
		label_max_lines_visible = val
		if label_model:
			label_model.max_lines_visible = val

## 表头tooltip
@export var column_tips: Array = []

## 每列的初始宽度比例（分配剩余宽度用）
@export var ratios: Array[float] = []

## 表格中的数据
@export var datas: Array = []:
	set(val):
		datas = val
		if is_node_ready():
			clear_all()
			# 自动检测列名
			if columns.is_empty() and not datas.is_empty():
				var first = datas[0]
				if first is Dictionary:
					for key in first:
						columns.append(key)
					rebuild_header()
				elif first is GDSQL.DictionaryObject:
					for info in first._get_property_list():
						if first._is_hidden_prop(info["name"]):
							continue
						columns.append(info["name"])
					rebuild_header()
				elif first is Array:
					for i in first.size():
						columns.append("#%d" % i)
					rebuild_header()
			for d in datas:
				datas_flat.append(d)
			update_content_size()
			update_frame_col_width_if_needed()
			if columns.size() > 0:
				_on_scroll(scroll_container.scroll_vertical)

# ── Constants ───────────────────────────────────────────────────────────────

const ROW_HEIGHT := 28
const BUFFER_ROWS := 5
const MIN_COL_WIDTH := 30
const GRABBER_WIDTH := 5
const MAX_POOL_SIZE := 200

const HIGHTLIGHT_COLOR = Color(Color.MEDIUM_PURPLE, 0.788)
const DEFAULT_BORDER_BG = Color(1, 1, 1, 0.05)
const DEFAULT_BORDER_LINE = Color(0.25, 0.45, 0.82, 0.85)
const GRID_COLOR = Color(0.78, 0.78, 0.78, 0.35)

# ── Node references ─────────────────────────────────────────────────────────

var header_container: HBoxContainer
var scroll_container: ScrollContainer
var row_container: Control
var borders_overlay: Control
var popup_menu_text: PopupMenu

var label_model: Label
var texture_rect_model: TextureRect
var check_box_model: CheckBox
var row_panel_model: PanelContainer
var row_model: HBoxContainer

# ── State ───────────────────────────────────────────────────────────────────

var col_widths: Array[float] = []        # pixel widths per column (data cols only, no frame/empty)
var header_buttons: Array[Button] = []    # for data columns + frame column
var header_spacer: Control = null

var row_pool: Array[Control] = []         # pooled row nodes
var pool_in_use: Array[bool] = []
var first_visible_idx := 0
var last_visible_idx := -1

var datas_flat: Array = []                # working copy (mirror of datas)
var _entered_tree := false

var vbox_container: VBoxContainer
var overlay_wrapper: MarginContainer

# Selection / border state
var selected_borders: Array[Dictionary] = []
var last_selected_pos := Vector2i(0, 0)
var start_drag := false
var start_drag_with_ctrl := false
var exclude_mode := false
var exclude_border: Dictionary = {}
var exclude_border_active := false

var actual_row_height := ROW_HEIGHT

# Autofill state
var cornor_dragger: Control = null
var cornor_drag_start := false
var autofill_info: Dictionary = {}
var autofill_borders_positions: Array[Array] = []  # [[row, col], ...] for dashed border cells
var dash_border_scene: PackedScene = null

# Shortcut buttons (invisible, kept for keyboard shortcuts)
var button_select_all: Button
var button_edit: Button
var button_copy: Button
var button_paste: Button
var button_delete: Button
var button_delete_row: Button

var style_box_empty: StyleBoxEmpty

# ── Tree construction ───────────────────────────────────────────────────────

func _ready() -> void:
	_construct_tree()
	style_box_empty = StyleBoxEmpty.new()
	rebuild_header()
	await get_tree().process_frame
	# 初始布局完成后调整一次列宽（避免resized信号循环触发）
	_on_table_resized()

	if dash_border_scene == null:
		var s = load("res://addons/gdsql/table/dash_border.tscn")
		if s:
			dash_border_scene = s

	label_max_lines_visible = label_max_lines_visible

	# Trigger initial data load
	datas = datas

	# 等一帧让 VBoxContainer 重新布局（header 尺寸变化后需要）
	await get_tree().process_frame

	# 调整列宽并定位overlay
	_on_table_resized()
	_update_borders_overlay_size()
	scroll_container.resized.connect(_update_borders_overlay_size)

	# Scroll listener
	var v_bar = scroll_container.get_v_scroll_bar()
	v_bar.value_changed.connect(_on_scroll)
	v_bar.visibility_changed.connect(_on_vbar_visibility_changed)

func _construct_tree():
	vbox_container = VBoxContainer.new()
	vbox_container.name = "VBoxContainer"
	vbox_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vbox_container)

	# ── Models (template nodes, invisible) ──
	var models = HBoxContainer.new()
	models.name = "Models"
	models.visible = false
	vbox_container.add_child(models)

	row_panel_model = PanelContainer.new()
	row_panel_model.name = "RowPanelModel"
	models.add_child(row_panel_model)
	row_model = HBoxContainer.new()
	row_model.name = "RowModel"
	row_panel_model.add_child(row_model)

	label_model = Label.new()
	label_model.name = "LabelModel"
	label_model.mouse_filter = Control.MOUSE_FILTER_IGNORE
	models.add_child(label_model)

	texture_rect_model = TextureRect.new()
	texture_rect_model.name = "TextureRectModel"
	texture_rect_model.mouse_filter = Control.MOUSE_FILTER_IGNORE
	models.add_child(texture_rect_model)

	check_box_model = CheckBox.new()
	check_box_model.name = "CheckBoxModel"
	check_box_model.mouse_filter = Control.MOUSE_FILTER_PASS
	models.add_child(check_box_model)

	# ── Header (direct child of VBoxContainer) ──
	header_container = HBoxContainer.new()
	header_container.name = "HeaderContainer"
	header_container.add_theme_constant_override("separation", 0)
	header_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_container.add_child(header_container)

	# ── Scroll container (direct child, VBoxContainer handles layout) ──
	scroll_container = ScrollContainer.new()
	scroll_container.name = "ScrollContainer"
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb = StyleBoxEmpty.new()
	sb.content_margin_top = 2
	scroll_container.add_theme_stylebox_override("panel", sb)
	vbox_container.add_child(scroll_container)

	row_container = Control.new()
	row_container.name = "RowContainer"
	row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(row_container)

	# Mouse events on row_container for selection
	row_container.gui_input.connect(_on_row_container_gui_input)
	row_container.mouse_entered.connect(_on_data_area_mouse_entered)
	row_container.mouse_exited.connect(_on_data_area_mouse_exited)

	# Borders overlay — wrapped in MarginContainer so root layout can't override position
	overlay_wrapper = MarginContainer.new()
	overlay_wrapper.name = "OverlayWrapper"
	overlay_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_wrapper)

	borders_overlay = Control.new()
	borders_overlay.name = "BordersOverlay"
	borders_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	borders_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	borders_overlay.draw.connect(_on_borders_overlay_draw)
	overlay_wrapper.add_child(borders_overlay)

	# ── Popup menu ──
	popup_menu_text = PopupMenu.new()
	popup_menu_text.name = "PopupMenuText"
	var icon_copy = load("res://addons/gdsql/img/copy.svg")
	var icon_trash = load("res://addons/gdsql/img/trash-can.svg")
	popup_menu_text.add_item("Copy Field", 0)
	if icon_copy:
		popup_menu_text.set_item_icon(0, icon_copy)
	popup_menu_text.add_item("Copy Line", 1)
	popup_menu_text.add_item("Delete", 2)
	if icon_trash:
		popup_menu_text.set_item_icon(2, icon_trash)
	popup_menu_text.set_item_disabled(2, true)
	popup_menu_text.index_pressed.connect(_on_popup_menu_index_pressed)
	vbox_container.add_child(popup_menu_text)

	# ── Shortcut buttons (invisible) ──
	var shortcut_layer = Control.new()
	shortcut_layer.name = "ShortcutLayer"
	shortcut_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox_container.add_child(shortcut_layer)

	button_select_all = _make_shortcut_button(KEY_A | KEY_CTRL)
	button_select_all.pressed.connect(_on_button_select_all_pressed)
	shortcut_layer.add_child(button_select_all)

	button_edit = _make_shortcut_button(KEY_ENTER)
	button_edit.modulate.a = 0
	button_edit.pressed.connect(_on_button_edit_pressed)
	shortcut_layer.add_child(button_edit)

	button_copy = _make_shortcut_button(KEY_C | KEY_CTRL)
	button_copy.pressed.connect(_on_button_copy_pressed)
	shortcut_layer.add_child(button_copy)

	button_paste = _make_shortcut_button(KEY_V | KEY_CTRL)
	button_paste.pressed.connect(_on_button_paste_pressed)
	shortcut_layer.add_child(button_paste)

	button_delete = _make_shortcut_button(KEY_DELETE)
	button_delete.pressed.connect(_on_button_delete_pressed)
	shortcut_layer.add_child(button_delete)

	button_delete_row = _make_shortcut_button(KEY_DELETE | KEY_ALT)
	button_delete_row.pressed.connect(_on_button_delete_row_pressed)
	shortcut_layer.add_child(button_delete_row)

func _make_shortcut_button(shortcut_key: int) -> Button:
	var btn = Button.new()
	btn.flat = true
	var se = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", se)
	var sc = Shortcut.new()
	var ev = InputEventKey.new()
	ev.keycode = shortcut_key
	if shortcut_key & KEY_CTRL:
		ev.ctrl_pressed = true
		ev.keycode = shortcut_key & ~KEY_CTRL
	if shortcut_key & KEY_ALT:
		ev.alt_pressed = true
		ev.keycode = shortcut_key & ~KEY_ALT
	if shortcut_key & KEY_META:
		ev.meta_pressed = true
		ev.keycode = shortcut_key & ~KEY_META
	sc.events = [ev]
	btn.shortcut = sc
	btn.shortcut_context = self
	return btn

# ── Header construction ───────────────────────────────────────────────────

func rebuild_header():
	# Clear existing header
	for c in header_container.get_children():
		header_container.remove_child(c)
		c.queue_free()
	header_buttons.clear()

	var col_count = columns.size()
	var data_col_count = col_count
	var total_cols = data_col_count + int(show_frame)

	# Build col_widths
	col_widths.resize(total_cols)
	var available = _get_header_available_width()
	if ratios.is_empty():
		var w = max(MIN_COL_WIDTH, available / max(total_cols, 1))
		for i in total_cols:
			col_widths[i] = w
	else:
		var total_ratio = 0.0
		for r in ratios:
			total_ratio += r
		total_ratio = max(total_ratio, 0.001)
		var ratio_idx = 0
		for i in total_cols:
			if show_frame and i == 0:
				col_widths[i] = _update_frame_col_width()
			elif ratio_idx < ratios.size():
				col_widths[i] = max(MIN_COL_WIDTH, available * ratios[ratio_idx] / total_ratio)
				ratio_idx += 1
			else:
				col_widths[i] = MIN_COL_WIDTH

	# Build header: [frame_btn?, col_btn, col_btn, ..., spacer]
	for i in total_cols:
		var btn = Button.new()
		var is_frame = show_frame and i == 0
		var data_idx = i - int(show_frame)

		if is_frame:
			var arrow = load("res://addons/gdsql/img/right_and_down_arrow.svg")
			if arrow:
				btn.icon = arrow
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			btn.pressed.connect(_on_select_all_btn_pressed)
			col_widths[i] = _update_frame_col_width()
		elif data_idx >= 0 and data_idx < columns.size():
			btn.text = str(columns[data_idx])
			if column_tips.size() > data_idx and not column_tips[data_idx].is_empty():
				btn.tooltip_text = tr(column_tips[data_idx])
			var arrow_down = load("res://addons/gdsql/img/arrow_down.svg")
			if arrow_down:
				btn.mouse_entered.connect(DisplayServer.cursor_set_custom_image.bind(arrow_down, DisplayServer.CURSOR_HELP, Vector2(12, 12)))
			btn.pressed.connect(_on_header_col_pressed.bind(i))

		btn.custom_minimum_size.x = col_widths[i]
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btn.clip_text = true
		btn.add_theme_stylebox_override("focus", style_box_empty)
		header_container.add_child(btn)
		header_buttons.append(btn)
	# Spacer (fills remaining space)
	header_spacer = Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_container.add_child(header_spacer)

	# 通知 VBoxContainer 重新布局（header 尺寸变化后需要）
	vbox_container.queue_sort()


func _update_frame_col_width() -> float:
	if not show_frame or col_widths.is_empty():
		return 30.0
	var max_num = max(1, datas_flat.size())
	var w = max(48.0, len(str(max_num)) * 9.0 + 8.0)
	col_widths[0] = w
	return w

func update_frame_col_width_if_needed():
	if show_frame and not col_widths.is_empty():
		_update_frame_col_width()
		_apply_header_widths()
		sync_row_widths()


func _get_header_available_width() -> float:
	return max(100, header_container.size.x)

func _on_table_resized():
	if col_widths.is_empty():
		return
	# Redistribute proportionally
	var available = _get_header_available_width()
	var current_total = 0.0
	for w in col_widths:
		current_total += w
	if current_total < 1:
		return

	var ratio = available / current_total
	for i in col_widths.size():
		col_widths[i] = max(MIN_COL_WIDTH, col_widths[i] * ratio)
	_apply_header_widths()
	sync_row_widths()
	borders_overlay.queue_redraw()


func _update_borders_overlay_size():
	if is_instance_valid(overlay_wrapper) and is_instance_valid(scroll_container):
		var sp = scroll_container.position
		var ss = scroll_container.size
		overlay_wrapper.add_theme_constant_override("margin_left", sp.x)
		overlay_wrapper.add_theme_constant_override("margin_top", sp.y)
		overlay_wrapper.add_theme_constant_override("margin_right", max(0, overlay_wrapper.size.x - sp.x - ss.x))
		overlay_wrapper.add_theme_constant_override("margin_bottom", max(0, overlay_wrapper.size.y - sp.y - ss.y))

func _apply_header_widths():
	for i in min(header_buttons.size(), col_widths.size()):
		header_buttons[i].custom_minimum_size.x = col_widths[i]

# ── Header drag (position-based boundary detection) ──────────────────────

var _drag_col_idx := -1
var _drag_start_x := 0.0
var _drag_start_width := 0.0
var _drag_press_active := false

func _get_col_boundary_at_x(local_x: float) -> int:
	# Return the column index whose right edge is within GRABBER_WIDTH/2 of local_x, or -1.
	for i in range(col_widths.size()):
		if show_frame and i == 0:
			continue  # skip frame column
		var boundary = _get_col_x(i) + col_widths[i]
		if abs(local_x - boundary) <= GRABBER_WIDTH:
			return i
	return -1

func _input(event):
	if not is_node_ready() or not header_container.is_visible_in_tree():
		return
	var header_rect = Rect2(header_container.global_position, header_container.size)
	var mouse_global = get_global_mouse_position()
	var over_header = header_rect.has_point(mouse_global)

	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and over_header:
				var header_pos = mb.position - header_container.global_position
				var col_idx = _get_col_boundary_at_x(header_pos.x)
				if col_idx >= 0:
					_drag_col_idx = col_idx
					_drag_start_x = mouse_global.x
					_drag_start_width = col_widths[col_idx]
					_drag_press_active = true
					return  # don't let _gui_input see this event
			elif not mb.pressed:
				if _drag_press_active:
					call_deferred("_clear_drag_flag")
				_drag_col_idx = -1

	if event is InputEventMouseMotion:
		if _drag_col_idx >= 0:
			var dx = mouse_global.x - _drag_start_x
			var new_w = max(MIN_COL_WIDTH, _drag_start_width + dx)
			if new_w != col_widths[_drag_col_idx]:
				col_widths[_drag_col_idx] = new_w
				_apply_header_widths()
				sync_row_widths()
				_update_dragger_position()
				borders_overlay.queue_redraw()
		elif over_header:
			var header_pos = mouse_global - header_container.global_position
			var col_idx = _get_col_boundary_at_x(header_pos.x)
			var want_hsize = col_idx >= 0
			for btn in header_buttons:
				if want_hsize:
					btn.mouse_default_cursor_shape = Control.CURSOR_HSIZE
				elif show_frame and btn == header_buttons[0]:
					btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
				else:
					btn.mouse_default_cursor_shape = Control.CURSOR_HELP
		else:
			for btn in header_buttons:
				if show_frame and btn == header_buttons[0]:
					btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
				else:
					btn.mouse_default_cursor_shape = Control.CURSOR_HELP

func _clear_drag_flag():
	_drag_press_active = false
	_drag_col_idx = -1

func sync_row_widths():
	for row_node in row_pool:
		if row_node.visible:
			_apply_row_widths(row_node)

func _apply_row_widths(row_node: Control):
	var hbox = row_node.get_child(0) if row_node.get_child_count() > 0 else null
	if hbox == null:
		return
	var wi = 0
	for child in hbox.get_children():
		if not (child is PanelContainer):
			continue
		if wi >= col_widths.size():
			break
		child.custom_minimum_size.x = col_widths[wi]
		wi += 1

# ── Virtual Scrolling ─────────────────────────────────────────────────────

func update_content_size():
	var total_h = datas_flat.size() * actual_row_height
	row_container.custom_minimum_size.y = total_h

func _on_scroll(value: float):
	if datas_flat.is_empty():
		_hide_all_pool_rows()
		borders_overlay.queue_redraw()
		return

	var view_h = scroll_container.size.y
	if view_h <= 0:
		return

	var new_first = max(0, floor(value / actual_row_height) - BUFFER_ROWS)
	var new_last = min(datas_flat.size() - 1, ceil((value + view_h) / actual_row_height) + BUFFER_ROWS)

	if new_first == first_visible_idx and new_last == last_visible_idx:
		return  # no change

	first_visible_idx = new_first
	last_visible_idx = new_last

	_position_visible_rows()
	_update_borders_overlay_size()
	borders_overlay.queue_redraw()

func _position_visible_rows():
	var needed = last_visible_idx - first_visible_idx + 1
	_ensure_pool_size(needed)

	# 第一步：分配数据到所有可见行
	for i in range(needed):
		var data_idx = first_visible_idx + i
		var row = row_pool[i]
		_assign_row_data(row, data_idx)
		_apply_row_widths(row)

	# 第二步：从第一行测量实际行高
	actual_row_height = ROW_HEIGHT
	if needed > 0 and is_instance_valid(row_pool[0]):
		var first_row = row_pool[0]
		var min_size = first_row.get_combined_minimum_size()
		actual_row_height = max(ROW_HEIGHT, min_size.y)

	# 第三步：定位所有可见行
	for i in range(needed):
		var data_idx = first_visible_idx + i
		var row = row_pool[i]
		row.visible = true
		pool_in_use[i] = true
		row.position = Vector2(0, data_idx * actual_row_height)
		row.size = Vector2(row_container.size.x, actual_row_height)

	for i in range(needed, row_pool.size()):
		row_pool[i].visible = false
		pool_in_use[i] = false


func _dump_row_debug():
	pass

func _dump_border_debug():
	print("=== BORDER DEBUG (using _get_col_x) ====")
	print("overlay gpos=", borders_overlay.global_position, " size=", borders_overlay.size)
	print("scroll gpos=", scroll_container.global_position)
	print("scroll_val=", scroll_container.scroll_vertical)
	print("actual_row_height=", actual_row_height)
	for bi in selected_borders.size():
		var b = selected_borders[bi]
		var rect = b["rect"] as Rect2
		print("border[", bi, "] start=", b["start"], " rect=", rect)
		for r in range(int(rect.position.x), int(rect.end.x)):
			var y0 = r * actual_row_height - scroll_container.scroll_vertical
			if y0 + actual_row_height < 0 or y0 > scroll_container.size.y:
				continue
			for c in range(int(rect.position.y), int(rect.end.y)):
				var x0 = _get_col_x(c)
				var cell_global = borders_overlay.global_position + Vector2(x0, y0)
				print("  cell[", r, ",", c, "] local=", Vector2(x0, y0), " global=", cell_global, " w=", col_widths[c], " h=", actual_row_height)
	print("=== END BORDER DEBUG ====")
func _hide_all_pool_rows():
	for i in range(row_pool.size()):
		row_pool[i].visible = false
		pool_in_use[i] = false

func _ensure_pool_size(needed: int):
	var target = min(MAX_POOL_SIZE, max(needed, 10))
	while row_pool.size() < target:
		var row = _create_row_node()
		row_pool.append(row)
		pool_in_use.append(true)
		row.visible = false
		row_container.add_child(row)

func _create_row_node() -> Control:
	var row = PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = ROW_HEIGHT
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_stylebox_override("panel", style_box_empty)

	# Build cell containers for each column + frame column
	var hbox = HBoxContainer.new()
	hbox.name = "RowHBox"
	hbox.add_theme_constant_override("separation", 0)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.custom_minimum_size.y = ROW_HEIGHT
	row.add_child(hbox)

	var total_cols = columns.size() + int(show_frame)
	for i in total_cols:
		var cell = PanelContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		cell.add_theme_stylebox_override("panel", style_box_empty)

		var is_frame = show_frame and i == 0
		if is_frame:
			cell.custom_minimum_size.x = col_widths[i] if i < col_widths.size() else 48.0
			var line_btn = Button.new()
			line_btn.flat = false
			line_btn.mouse_default_cursor_shape = Control.CURSOR_HELP
			line_btn.add_theme_font_size_override("font_size", 12)
			var arrow_right = load("res://addons/gdsql/img/arrow_right.svg")
			if arrow_right:
				line_btn.mouse_entered.connect(DisplayServer.cursor_set_custom_image.bind(arrow_right, DisplayServer.CURSOR_HELP, Vector2(12, 12)))
			cell.add_child(line_btn)
		else:
			cell.custom_minimum_size.x = col_widths[i] if i < col_widths.size() else float(MIN_COL_WIDTH)

		hbox.add_child(cell)
	return row

func _assign_row_data(row_node: Control, data_idx: int):
	var hbox = row_node.get_child(0) if row_node.get_child_count() > 0 else null
	if hbox == null:
		return

	var data = datas_flat[data_idx]
	if data == null:
		return

	row_node.set_meta("data_index", data_idx)
	row_node.set_meta("data", data)

	var data_arr = _data_to_array(data)

	var col_offset = int(show_frame)
	var data_col = 0
	for cell in hbox.get_children():
		if not (cell is PanelContainer):
			continue  # skip spacers
		if col_offset > 0:
			# Frame column
			col_offset -= 1
			var btn = cell.get_child(0) if cell.get_child_count() > 0 else null
			if btn is Button:
				btn.text = str(data_idx + 1)
				# Disconnect old, connect new
				if btn.pressed.is_connected(_on_frame_btn_pressed):
					btn.pressed.disconnect(_on_frame_btn_pressed)
				btn.pressed.connect(_on_frame_btn_pressed.bind(data_idx, btn))
			continue

		if data_col >= data_arr.size():
			data_col += 1
			continue

		# Clear existing children
		for c in cell.get_children():
			cell.remove_child(c)
			if not c is Button:
				c.queue_free()

		var value = data_arr[data_col]
		var ctl = _create_cell_control(value, data, data_col)
		if ctl:
			ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_child(ctl)

		# Assign cell meta for border lookup
		cell.set_meta("row", data_idx)
		cell.set_meta("col", data_col)
		data_col += 1


	# end for
# ── Cell control creation ───────────────────────────────────────────────

func _data_to_array(a_data):
	if a_data is Array:
		return a_data.duplicate()
	elif a_data is Dictionary:
		var arr = []
		if columns.is_empty():
			for key in a_data:
				arr.append(a_data[key])
		else:
			for c in columns:
				arr.append(a_data.get(c, null))
		return arr
	elif a_data is GDSQL.DictionaryObject:
		var arr = []
		for i in columns.size():
			arr.append(a_data._get_by_index(i))
		return arr
	else:
		return [str(a_data)]

func _create_cell_control(value, a_data, col_idx: int) -> Control:
	var handled = false
	var control: Control = null
	var data_type = typeof(value)

	match data_type:
		TYPE_BOOL:
			handled = true
			control = check_box_model.duplicate()
			control.button_pressed = value
			control.tooltip_text = str(value)
			if a_data is GDSQL.DictionaryObject:
				_bind_update_callback(a_data, col_idx, control)

		TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			handled = true
			control = label_model.duplicate()
			control.text = str(value)
			control.tooltip_text = _split_tooltip(control.text)
			if a_data is GDSQL.DictionaryObject:
				var p_name = a_data.__get_index_prop(col_idx).to_snake_case()
				var hint = a_data.get_meta(p_name + "_enum_hint_string_dict", "")
				if hint != "":
					var pairs = Array(hint.split(",")).map(func(v): return v.split(":"))
					for p in pairs:
						if int(p[1]) == value:
							control.text = str(p[0])
							control.tooltip_text = _split_tooltip(control.text)
							break
				_bind_update_callback(a_data, col_idx, control)

		TYPE_OBJECT:
			if value is Texture2D:
				handled = true
				var texture_rect2d = TextureRect.new()
				texture_rect2d.texture = value
				texture_rect2d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				texture_rect2d.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				texture_rect2d.tooltip_text = "%s\nType: %s" % [value.resource_path, value.get_class()]
				control = texture_rect2d
				if a_data is GDSQL.DictionaryObject:
					_bind_update_callback(a_data, col_idx, control)
			elif value is Resource:
				handled = true
				var erp = EditorResourcePicker.new()
				erp.base_type = "Resource"
				erp.edited_resource = value
				erp.editable = false
				control = erp
				if a_data is GDSQL.DictionaryObject:
					_bind_update_callback(a_data, col_idx, control)
			elif value is Control:
				handled = true
				control = value
			elif value is GDSQL.DictionaryObject:
				handled = true
				var grid = GridContainer.new()
				grid.columns = 2
				var sub_data = value
				var sub_idx = -1
				for info in sub_data._get_property_list():
					if sub_data._is_hidden_prop(info["name"]):
						continue
					sub_idx += 1
					var lbl = Label.new()
					lbl.text = info["name"]
					lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
					grid.add_child(lbl)
					grid.add_child(_create_cell_control(sub_data.get(info["name"]), sub_data, sub_idx))
				control = grid

	if not handled:
		control = label_model.duplicate()
		control.text = var_to_str(value)
		control.tooltip_text = _split_tooltip(control.text)

	# Set mouse filter so events pass through to row_container for selection
	if control:
		if control is Button:
			control.mouse_filter = Control.MOUSE_FILTER_PASS
		elif not (value is Control):
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return control

func _bind_update_callback(a_data: GDSQL.DictionaryObject, col_idx: int, control: Control):
	if a_data == null or not is_instance_valid(a_data):
		return
	var p_name = a_data.__get_index_prop(col_idx).to_snake_case()
	var hint = a_data.get_meta(p_name + "_enum_hint_string_dict", "")
	var wr = weakref(control)

	var hint_static = hint
	var cb = func(new_value):
		var ctl = wr.get_ref()
		if not ctl:
			return
		var data_type = typeof(new_value)
		match data_type:
			TYPE_BOOL:
				if ctl is CheckBox:
					ctl.button_pressed = new_value
				else:
					_replace_control(ctl, _create_cell_control(new_value, a_data, col_idx))
			TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
				if ctl is Label:
					if hint_static != "":
						var pairs = Array(hint_static.split(",")).map(func(v): return v.split(":"))
						var found = false
						for p in pairs:
							if int(p[1]) == new_value:
								ctl.text = str(p[0])
								found = true
								break
						if not found:
							ctl.text = ""
					else:
						ctl.text = str(new_value)
					ctl.tooltip_text = _split_tooltip(ctl.text)
				else:
					_replace_control(ctl, _create_cell_control(new_value, a_data, col_idx))
			TYPE_OBJECT:
				if (new_value is Resource or new_value is Control) and ctl is not Label:
					_replace_control(ctl, _create_cell_control(new_value, a_data, col_idx))
				else:
					if ctl is Label:
						ctl.text = var_to_str(new_value) if new_value is Object else str(new_value)
						ctl.tooltip_text = _split_tooltip(ctl.text)
					else:
						_replace_control(ctl, _create_cell_control(new_value, a_data, col_idx))
			_:
				_replace_control(ctl, _create_cell_control(new_value, a_data, col_idx))

	a_data.set_update_callback(a_data.__get_index_prop(col_idx), cb)

func _replace_control(old: Control, new_ctl: Control):
	if not is_instance_valid(old):
		return
	var parent = old.get_parent()
	if parent:
		new_ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		old.replace_by(new_ctl)
		old.queue_free()

# ── Row operations ────────────────────────────────────────────────────────

func append_data(a_data):
	datas_flat.append(a_data)
	if columns.is_empty() and a_data is Dictionary:
		for key in a_data:
			columns.append(key)
		rebuild_header()
	update_content_size()
	# If the new row is near the viewport, refresh
	if datas_flat.size() - 1 <= last_visible_idx + BUFFER_ROWS:
		_on_scroll(scroll_container.scroll_vertical)

func insert_data(pos: int, a_data):
	clear_borders()
	datas_flat.insert(pos, a_data)
	if columns.is_empty() and a_data is Dictionary:
		for key in a_data:
			columns.append(key)
		rebuild_header()
	update_content_size()
	_on_scroll(scroll_container.scroll_vertical)

func remove_data_at(index: int, free_data: bool):
	clear_borders()
	if index < 0 or index >= datas_flat.size():
		return
	if free_data and datas_flat[index] is GDSQL.DictionaryObject:
		datas_flat[index].free_all_custom_display_controls()
	datas_flat.remove_at(index)
	update_content_size()
	_on_scroll(scroll_container.scroll_vertical)

func move_data(from: int, to: int):
	if from == to:
		return
	clear_borders()
	var data = datas_flat[from]
	datas_flat.remove_at(from)
	datas_flat.insert(to, data)
	update_content_size()
	_on_scroll(scroll_container.scroll_vertical)

func clear_all():
	clear_borders()
	datas_flat.clear()
	for i in range(row_pool.size()):
		row_pool[i].visible = false
		pool_in_use[i] = false

func _get_row_node(data_idx: int):
	for i in range(row_pool.size()):
		if pool_in_use[i] and row_pool[i].visible:
			if row_pool[i].get_meta("data_index", -1) == data_idx:
				return row_pool[i]
	return null

# ── Borders overlay ─────────────────────────────────────────────────────

func _draw_grid():
	if datas_flat.is_empty() or actual_row_height <= 0 or col_widths.is_empty():
		return
	if not is_instance_valid(borders_overlay) or not is_instance_valid(scroll_container):
		return

	var view_h = scroll_container.size.y
	var scroll_val = scroll_container.scroll_vertical
	var fo = int(show_frame)

	# Visible row range
	var first_r = max(0, int(scroll_val / actual_row_height))
	var last_r = min(datas_flat.size() - 1, int((scroll_val + view_h) / actual_row_height))
	if last_r < first_r:
		return

	# Data column indices in col_widths
	var first_dc = fo
	var last_dc = col_widths.size() - 1
	if last_dc < first_dc:
		return

	var left_x = _get_col_x(first_dc)
	var right_x = _get_col_x(last_dc) + col_widths[last_dc]

	# Y range clamped to viewport
	var y0 = first_r * actual_row_height - scroll_val
	var y1 = (last_r + 1) * actual_row_height - scroll_val
	if y0 < 0.0:
		y0 = 0.0
	if y1 > view_h:
		y1 = view_h

	# Horizontal grid lines — at bottom of each visible row
	for r in range(first_r, last_r + 1):
		var y = (r + 1) * actual_row_height - scroll_val
		if y < y0 or y > y1:
			continue
		borders_overlay.draw_line(Vector2(left_x, y), Vector2(right_x, y), GRID_COLOR, 1.0)

	# Vertical grid lines — left of first data column and right of each data column
	var x_first = _get_col_x(first_dc)
	borders_overlay.draw_line(Vector2(x_first, y0), Vector2(x_first, y1), GRID_COLOR, 1.0)
	for ci in range(first_dc, last_dc + 1):
		var x = _get_col_x(ci) + col_widths[ci]
		if x > right_x:
			break
		borders_overlay.draw_line(Vector2(x, y0), Vector2(x, y1), GRID_COLOR, 1.0)

func _on_borders_overlay_draw():
	# Grid lines (drawn first, behind selection borders)
	if show_grid:
		_draw_grid()

	if not support_select_border:
		return
	if selected_borders.is_empty() and exclude_border.is_empty() and not autofill_info.has("rect"):
		return

	var view_h = scroll_container.size.y
	var scroll_val = scroll_container.scroll_vertical
	var multi = selected_borders.size() > 1
	var fo = int(show_frame)

	for border in selected_borders:
		var rect = border["rect"] as Rect2
		var start_r = int(rect.position.x)
		var end_r = int(rect.end.x)
		var start_c = int(rect.position.y)
		var end_c = int(rect.end.y)

		for r in range(start_r, end_r):
			var y0 = r * actual_row_height - scroll_val
			if y0 + actual_row_height < 0 or y0 > view_h:
				continue

			for c in range(start_c, end_c):
				var ci = c + fo
				if ci < 0 or ci >= col_widths.size():
					continue
				var x0 = _get_col_x(ci)
				var bw = col_widths[ci]
				# Only last border's start cell has no background (draw_center=false)
				var is_start = r == last_selected_pos.x and c == last_selected_pos.y
				if not is_start:
					var alpha = DEFAULT_BORDER_BG.a * _get_overlap_count(r, c) * 1.05
					var bg = Color(DEFAULT_BORDER_BG.r, DEFAULT_BORDER_BG.g, DEFAULT_BORDER_BG.b, alpha)
					borders_overlay.draw_rect(Rect2(x0, y0, bw, actual_row_height), bg)

		# Draw continuous outer boundary (4 lines)
		var sl = _get_col_x(start_c + fo)
		var last_ci = end_c + fo - 1
		var sr = _get_col_x(last_ci) + col_widths[last_ci] if last_ci >= 0 else sl
		var st = start_r * actual_row_height - scroll_val
		var sb = end_r * actual_row_height - scroll_val
		var bc = DEFAULT_BORDER_LINE
		if multi:
			bc = Color(DEFAULT_BORDER_LINE, 0.5)
		borders_overlay.draw_line(Vector2(sl, st), Vector2(sr, st), bc, 2)
		borders_overlay.draw_line(Vector2(sl, sb), Vector2(sr, sb), bc, 2)
		borders_overlay.draw_line(Vector2(sl, st), Vector2(sl, sb), bc, 2)
		borders_overlay.draw_line(Vector2(sr, st), Vector2(sr, sb), bc, 2)

	# Exclude border (dark blue background)
	if not exclude_border.is_empty():
		var ex_rect = exclude_border["rect"] as Rect2
		for er in range(int(ex_rect.position.x), int(ex_rect.end.x)):
			var ey = er * actual_row_height - scroll_val
			if ey + actual_row_height < 0 or ey > view_h:
				continue
			for ec in range(int(ex_rect.position.y), int(ex_rect.end.y)):
				var eci = ec + fo
				if eci < 0 or eci >= col_widths.size():
					continue
				var ex0 = _get_col_x(eci)
				var ew = col_widths[eci]
				borders_overlay.draw_rect(Rect2(ex0, ey, ew, actual_row_height), Color(Color.DARK_BLUE, 0.25))

	# Autofill dashed border
	if autofill_info.has("rect"):
		var af_rect = autofill_info["rect"] as Rect2
		var af_start = af_rect.position
		var af_end = af_rect.end
		for r in range(int(af_start.x), int(af_end.x)):
			for c in range(int(af_start.y), int(af_end.y)):
				if r == int(af_start.x) or c == int(af_start.y) or r == int(af_end.x) - 1 or c == int(af_end.y) - 1:
					var ci = c + int(show_frame)
					if ci >= col_widths.size():
						continue
					var cx = _get_col_x(ci)
					var cy = r * actual_row_height - scroll_val
					_draw_dashed_rect(Rect2(cx, cy, col_widths[ci], actual_row_height),
						r == int(af_start.x), r == int(af_end.x) - 1,
						c == int(af_start.y), c == int(af_end.y) - 1)


# ── Dashed rect drawing ──────────────────────────────────────────────────

func _draw_dashed_rect(rect: Rect2, show_top: bool, show_bottom: bool, show_left: bool, show_right: bool):
	var dcol = Color(0.6, 0.6, 0.6, 0.8)
	var dash_len = 4.0
	var gap_len = 3.0
	var w = 1.5

	if show_top:
		var x = rect.position.x
		var end_x = rect.end.x
		var drawing = true
		while x < end_x:
			var step = dash_len if drawing else gap_len
			var nx = min(x + step, end_x)
			if drawing:
				borders_overlay.draw_line(Vector2(x, rect.position.y), Vector2(nx, rect.position.y), dcol, w)
			x = nx
			drawing = not drawing

	if show_bottom:
		var x = rect.position.x
		var end_x = rect.end.x
		var drawing = true
		while x < end_x:
			var step = dash_len if drawing else gap_len
			var nx = min(x + step, end_x)
			if drawing:
				borders_overlay.draw_line(Vector2(x, rect.end.y), Vector2(nx, rect.end.y), dcol, w)
			x = nx
			drawing = not drawing

	if show_left:
		var y = rect.position.y
		var end_y = rect.end.y
		var drawing = true
		while y < end_y:
			var step = dash_len if drawing else gap_len
			var ny = min(y + step, end_y)
			if drawing:
				borders_overlay.draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x, ny), dcol, w)
			y = ny
			drawing = not drawing

	if show_right:
		var y = rect.position.y
		var end_y = rect.end.y
		var drawing = true
		while y < end_y:
			var step = dash_len if drawing else gap_len
			var ny = min(y + step, end_y)
			if drawing:
				borders_overlay.draw_line(Vector2(rect.end.x, y), Vector2(rect.end.x, ny), dcol, w)
			y = ny
			drawing = not drawing

# ── Column / cell helpers ───────────────────────────────────────────────

func _get_col_x(col: int) -> float:
	var x = 0.0
	for i in range(min(col, col_widths.size())):
		x += col_widths[i]
	return x

func _get_cell_screen_rect(data_row: int, data_col: int) -> Rect2:
	var ci = data_col + int(show_frame)
	var x = _get_col_x(ci)
	var y = data_row * actual_row_height - scroll_container.scroll_vertical
	return Rect2(x, y, col_widths[ci], actual_row_height)

func _get_overlap_count(row: int, col: int) -> int:
	var count = 0
	for b in selected_borders:
		var r = b["rect"] as Rect2
		if row >= r.position.x and row < r.end.x and col >= r.position.y and col < r.end.y:
			count += 1
	return count

# ── Border management ──────────────────────────────────────────────────

func clear_borders():
	selected_borders.clear()
	exclude_border = {}
	exclude_border_active = false
	_remove_corner_dragger()
	autofill_info = {}
	autofill_borders_positions.clear()
	borders_overlay.queue_redraw()

func add_border(border: Dictionary):
	if not support_select_border:
		return
	var b_rect = border["rect"] as Rect2
	if not b_rect.has_area():
		return
	var start = border["start"]
	if start is Vector2:
		start = Vector2i(start)
		border["start"] = start
	last_selected_pos = start
	for i in selected_borders.size():
		if selected_borders[i]["start"] == start:
			selected_borders[i] = border
			borders_overlay.queue_redraw()
			if selected_borders.size() <= 1:
				_add_corner_dragger()
			return
	if not border.get("ctrl", false):
		selected_borders.clear()
	selected_borders.append(border)
	borders_overlay.queue_redraw()
	if selected_borders.size() > 1:
		_remove_corner_dragger()
	else:
		_add_corner_dragger()

func add_exclude_border(border: Dictionary):
	if not support_select_border:
		return
	if not (border["rect"] as Rect2).has_area():
		return
	exclude_border = border
	exclude_border_active = true
	borders_overlay.queue_redraw()

func commit_exclude_border():
	if not exclude_border_active or exclude_border.is_empty():
		return
	var exclude_rect = exclude_border["rect"] as Rect2

	# Step 1: Remove borders fully enclosed by exclude rect
	var clears = []
	for i in selected_borders.size():
		var b_rect = selected_borders[i]["rect"] as Rect2
		if exclude_rect.encloses(b_rect):
			clears.push_back(i)
	clears.reverse()
	for i in clears:
		selected_borders.remove_at(i)

	# Step 2: Split borders intersecting with exclude rect
	var to_add = []
	var to_delete = []
	var empty_rect = Rect2()
	for i in selected_borders.size():
		var border = selected_borders[i]
		var b_rect = border["rect"] as Rect2
		var inter = exclude_rect.intersection(b_rect)
		if inter == empty_rect or not inter.has_area():
			continue
		to_delete.push_back(i)

		var bp = b_rect.position
		var be = b_rect.end

		# Decompose into up to 4 non-overlapping sub-rectangles
		# Top strip: above the intersection (full width)
		if inter.position.y > bp.y:
			to_add.push_back({
				"start": Vector2i(bp.x, bp.y),
				"rect": Rect2(bp.x, bp.y, b_rect.size.x, inter.position.y - bp.y)
			})
		# Bottom strip: below the intersection (full width)
		if inter.end.y < be.y:
			to_add.push_back({
				"start": Vector2i(bp.x, inter.end.y),
				"rect": Rect2(bp.x, inter.end.y, b_rect.size.x, be.y - inter.end.y)
			})
		# Left strip: between top/bottom, to the left
		if inter.position.x > bp.x:
			to_add.push_back({
				"start": Vector2i(bp.x, inter.position.y),
				"rect": Rect2(bp.x, inter.position.y, inter.position.x - bp.x, inter.size.y)
			})
		# Right strip: between top/bottom, to the right
		if inter.end.x < be.x:
			to_add.push_back({
				"start": Vector2i(inter.end.x, inter.position.y),
				"rect": Rect2(inter.end.x, inter.position.y, be.x - inter.end.x, inter.size.y)
			})

	# Remove and add
	to_delete.reverse()
	for i in to_delete:
		selected_borders.remove_at(i)
	for b in to_add:
		selected_borders.append(b)


	# Save exclude start before clearing
	var eb_start = exclude_border.get("start", Vector2i.ZERO)
	exclude_border = {}
	exclude_border_active = false

	# Handle corner dragger based on remaining selection count
	if selected_borders.is_empty():
		var fb = {"start": Vector2i(eb_start), "rect": Rect2(eb_start.x, eb_start.y, 1, 1)}
		add_border(fb)
		return
	elif selected_borders.size() == 1:
		last_selected_pos = selected_borders.front()["start"]
		_remove_corner_dragger()
		_add_corner_dragger()
	else:
		last_selected_pos = selected_borders.back()["start"]
		_remove_corner_dragger()

	borders_overlay.queue_redraw()

	if selected_borders.is_empty():
		return false
	var start_c = (selected_borders.front()["rect"] as Rect2).position.y
	var end_c = (selected_borders.front()["rect"] as Rect2).end.y
	for b in selected_borders:
		var r = b["rect"] as Rect2
		if r.position.y != start_c or r.end.y != end_c:
			return false
	return true

func borders_has_same_rows() -> bool:
	if selected_borders.is_empty():
		return false
	var start_r = (selected_borders.front()["rect"] as Rect2).position.x
	var end_r = (selected_borders.front()["rect"] as Rect2).end.x
	for b in selected_borders:
		var r = b["rect"] as Rect2
		if r.position.x != start_r or r.end.x != end_r:
			return false
	return true

func pos_is_selected(pos: Vector2i) -> bool:
	for b in selected_borders:
		var r = b["rect"] as Rect2
		if pos.x >= r.position.x and pos.x < r.end.x and pos.y >= r.position.y and pos.y < r.end.y:
			return true
	return false

func get_data_of_highlight_rows() -> Array:
	var rows_idx = []
	for b in selected_borders:
		var r = b["rect"] as Rect2
		for i in range(int(r.position.x), int(r.end.x)):
			if not rows_idx.has(i):
				rows_idx.append(i)
	var ret = []
	for i in rows_idx:
		if i < datas_flat.size():
			ret.append(datas_flat[i])
	return ret

# ── Corner dragger ────────────────────────────────────────────────────

func _add_corner_dragger():
	if not editable:
		return
	_remove_corner_dragger()
	if selected_borders.is_empty():
		return
	var rect = selected_borders.front()["rect"] as Rect2
	var last_row = int(rect.end.x) - 1
	var last_col = int(rect.end.y) - 1
	if last_row < 0 or last_col < 0:
		return

	var ci = last_col + int(show_frame)
	if ci < 0 or ci >= col_widths.size():
		return
	var cx = _get_col_x(ci) + col_widths[ci]
	var cy = (last_row + 1) * actual_row_height - scroll_container.scroll_vertical
	cornor_dragger = load("res://addons/gdsql/table/cornor_dragger.tscn").instantiate()
	borders_overlay.add_child(cornor_dragger)
	cornor_dragger.position = Vector2(cx, cy) - Vector2(5, 5)
	cornor_dragger.cornor_drag_start.connect(_on_corner_drag_start)
	cornor_dragger.cornor_drag_moving.connect(_on_corner_drag_moving)
	cornor_dragger.cornor_drag_end.connect(_on_corner_drag_end)
	cornor_dragger.cornor_double_clicked.connect(_on_corner_double_clicked)

func _remove_corner_dragger():
	if is_instance_valid(cornor_dragger):
		cornor_dragger.queue_free()
		cornor_dragger = null

func _update_dragger_position():
	if not is_instance_valid(cornor_dragger):
		return
	if selected_borders.is_empty():
		return
	var rect = selected_borders.front()["rect"] as Rect2
	var last_row = int(rect.end.x) - 1
	var last_col = int(rect.end.y) - 1
	if last_row < 0 or last_col < 0:
		return
	var ci = last_col + int(show_frame)
	if ci < 0 or ci >= col_widths.size():
		return
	var cx = _get_col_x(ci) + col_widths[ci]
	var cy = (last_row + 1) * actual_row_height - scroll_container.scroll_vertical
	cornor_dragger.position = Vector2(cx, cy) - Vector2(5, 5)

# ── Autofill handlers ──────────────────────────────────────────────────

func _on_corner_drag_start():
	if selected_borders.is_empty():
		return
	var rect = selected_borders.front()["rect"] as Rect2
	autofill_info = {
		"start": rect.position,
		"end": rect.end,
		"rect": rect,
		"mode": "start"
	}
	borders_overlay.queue_redraw()

func _on_corner_drag_moving(diff: Vector2):
	if autofill_info.is_empty() or not autofill_info.has("start"):
		return
	var src_start = autofill_info["start"] as Vector2
	var src_end = autofill_info["end"] as Vector2

	# Get cell under mouse using overlay-relative coordinates
	var mouse_gpos = get_global_mouse_position()
	var overlay_gpos = borders_overlay.global_position
	var local_mouse = mouse_gpos - overlay_gpos
	local_mouse.x -= scroll_container.scroll_horizontal
	var cell_pos = get_cell_at_pos(local_mouse)
	var pos_row = cell_pos.x
	var pos_col = cell_pos.y

	if pos_row < 0 or pos_col < 0:
		return

	# Compute cell center for threshold
	var ci = pos_col + int(show_frame)
	var cell_cx = local_mouse.x
	var cell_cy = local_mouse.y
	var expand_cx = local_mouse.x
	var expand_cy = local_mouse.y
	if ci >= 0 and ci < col_widths.size():
		var cell_x = _get_col_x(ci)
		cell_cx = cell_x + col_widths[ci] * 0.5  # shrink threshold (50%)
		expand_cx = cell_x + col_widths[ci] * 0.2  # expand threshold (20%)
		cell_cy = pos_row * actual_row_height + actual_row_height * 0.5  # shrink threshold (50%)
		expand_cy = pos_row * actual_row_height + actual_row_height * 0.2  # expand threshold (20%)

	# Compute desired end based on mouse position with threshold
	var cur_end = autofill_info.get("rect", Rect2(src_start, src_end - src_start)).end
	var desired_end = cur_end

	# --- Column ---
	if pos_col < src_start.y:
		# Extending left: recompute full rect including new start
		var sp = Vector2(min(src_start.x, pos_row), pos_col)
		var ep = Vector2(max(src_end.x, pos_row + 1), src_end.y)
		add_autofill_border(sp, ep, "add")
		return
	elif pos_col >= src_end.y:
		# Right of selection → expand right (past center required)
		if local_mouse.x > expand_cx:
			desired_end.y = pos_col + 1
	elif pos_col == src_end.y - 1:
		# In last col: left half→shrink, right half→expand back
		if local_mouse.x < cell_cx:
			desired_end.y = pos_col
		else:
			desired_end.y = pos_col + 1
	elif pos_col < src_end.y - 1:
		if local_mouse.x < cell_cx:
			desired_end.y = pos_col

	# --- Row ---
	if pos_row < src_start.x:
		# Extending up: recompute full rect
		var sp = Vector2(pos_row, min(src_start.y, pos_col))
		var ep = Vector2(src_end.x, max(src_end.y, pos_col + 1))
		add_autofill_border(sp, ep, "add")
		return
	elif pos_row >= src_end.x:
		if local_mouse.y > expand_cy:
			desired_end.x = pos_row + 1
	elif pos_row == src_end.x - 1:
		# In last row: top half→shrink, bottom half→expand back
		if local_mouse.y < cell_cy:
			desired_end.x = pos_row
		else:
			desired_end.x = pos_row + 1
	elif pos_row < src_end.x - 1:
		if local_mouse.y < cell_cy:
			desired_end.x = pos_row

	# Determine mode and apply (compare against current rect, not original)
	var mode = "add" if (desired_end.x > src_end.x or desired_end.y > src_end.y) else "sub"
	if desired_end != cur_end:
		add_autofill_border(src_start, desired_end, mode)

func add_autofill_border(start_pos: Vector2, end_pos: Vector2, mode: String):
	# Clear old dashed borders
	autofill_info["rect"] = Rect2(start_pos, end_pos - start_pos)
	autofill_info["mode"] = mode
	borders_overlay.queue_redraw()

func _on_corner_drag_end():
	_commit_autofill()

func _on_corner_double_clicked():
	commit_vertical_autofill()

func _commit_autofill():
	if autofill_info.is_empty() or not autofill_info.has("rect"):
		autofill_info = {}
		borders_overlay.queue_redraw()
		return
	var af_rect = autofill_info["rect"] as Rect2
	if not af_rect.has_area():
		autofill_info = {}
		borders_overlay.queue_redraw()
		return

	var af_start = af_rect.position
	var af_end = af_rect.end

	# Handle sub mode (shrink selection, set removed cells to defaults)
	if autofill_info.get("mode", "") == "sub":
		var ssel = selected_borders.front()["rect"] as Rect2 if not selected_borders.is_empty() else af_rect
		var sub_rect = Rect2()
		if af_rect.position == ssel.position and af_rect.end == ssel.end:
			sub_rect = ssel
		elif abs(af_rect.size.x - ssel.size.x) < 0.5:
			sub_rect.position = Vector2(af_rect.position.x, af_rect.end.y)
			sub_rect.size = Vector2(af_rect.size.x, ssel.size.y - af_rect.size.y)
		else:
			sub_rect.position = Vector2(af_rect.end.x, af_rect.position.y)
			sub_rect.size = Vector2(ssel.size.x - af_rect.size.x, af_rect.size.y)
		
		for r2 in range(int(sub_rect.position.x), int(sub_rect.end.x)):
			var d2 = datas_flat[r2] if r2 < datas_flat.size() else null
			if d2 is GDSQL.DictionaryObject:
				for c2 in range(int(sub_rect.position.y), int(sub_rect.end.y)):
					if not (d2.get_prop_usage_by_index(c2) & PROPERTY_USAGE_READ_ONLY):
						d2._set_default_by_index(c2)
		
		var sstart = Vector2i(autofill_info["start"])
		add_border({"start": sstart, "rect": af_rect})
		autofill_info = {}
		borders_overlay.queue_redraw()
		return

	var src_start = Vector2i(autofill_info["start"])
	var src_sel = selected_borders.front()["rect"] as Rect2 if not selected_borders.is_empty() else af_rect

	if af_rect.position == src_sel.position and af_rect.end == src_sel.end:
		autofill_info = {}
		borders_overlay.queue_redraw()
		return

	# Downward fill: extend rows (LeastSquares)
	if af_end.x > src_sel.end.x:
		var add_start_x = int(src_sel.end.x)
		var add_end_x = int(af_end.x)
		for col in range(int(src_sel.position.y), int(src_sel.end.y)):
			var xdata = []
			var ydata = []
			for r in range(int(src_sel.position.x), int(src_sel.end.x)):
				var d = datas_flat[r]
				if d is GDSQL.DictionaryObject:
					xdata.push_back(r)
					ydata.append(d._get_by_index(col))
			if xdata.is_empty():
				continue
			var ls = GDSQL.LeastSquares.new(xdata, ydata)
			for row in range(add_start_x, add_end_x):
				if row < datas_flat.size():
					var tgt = datas_flat[row]
					if tgt is GDSQL.DictionaryObject and not (tgt.get_prop_usage_by_index(col) & PROPERTY_USAGE_READ_ONLY):
						tgt._set_by_index(col, type_convert(ls.get_y(row), tgt.get_prop_type_by_index(col)))

	# Rightward fill: extend columns (LeastSquares)
	if af_end.y > src_sel.end.y:
		var add_start_y = int(src_sel.end.y)
		var add_end_y = int(af_end.y)
		for row in range(int(src_sel.position.x), int(src_sel.end.x)):
			var d = datas_flat[row]
			if not (d is GDSQL.DictionaryObject):
				continue
			var xdata = []
			var ydata = []
			for c in range(int(src_sel.position.y), int(src_sel.end.y)):
				xdata.push_back(c)
				ydata.append(d._get_by_index(c))
			if xdata.is_empty():
				continue
			var ls = GDSQL.LeastSquares.new(xdata, ydata)
			for col in range(add_start_y, add_end_y):
				if row < datas_flat.size():
					var tgt = datas_flat[row]
					if tgt is GDSQL.DictionaryObject and not (tgt.get_prop_usage_by_index(col) & PROPERTY_USAGE_READ_ONLY):
						tgt._set_by_index(col, type_convert(ls.get_y(col), tgt.get_prop_type_by_index(col)))

	add_border({"start": src_start, "rect": af_rect})
	autofill_info = {}
	borders_overlay.queue_redraw()
func commit_vertical_autofill():
	if selected_borders.is_empty():
		return
	var sel_rect = selected_borders.front()["rect"] as Rect2
	if int(sel_rect.end.x) >= datas_flat.size():
		return

	for col in range(int(sel_rect.position.y), int(sel_rect.end.y)):
		var xdata = []
		var ydata = []
		for r in range(int(sel_rect.position.x), int(sel_rect.end.x)):
			var d = datas_flat[r]
			if d is GDSQL.DictionaryObject:
				xdata.push_back(r)
				ydata.append(d._get_by_index(col))
		if xdata.is_empty():
			continue
		var ls = GDSQL.LeastSquares.new(xdata, ydata)
		for row in range(int(sel_rect.end.x), datas_flat.size()):
			var tgt = datas_flat[row]
			if tgt is GDSQL.DictionaryObject and not (tgt.get_prop_usage_by_index(col) & PROPERTY_USAGE_READ_ONLY):
				tgt._set_by_index(col, type_convert(ls.get_y(row), tgt.get_prop_type_by_index(col)))

	var new_rect = Rect2(sel_rect.position, Vector2(datas_flat.size(), sel_rect.size.y))
	add_border({"start": sel_rect.position, "rect": new_rect})
	autofill_info = {}
	borders_overlay.queue_redraw()

# ── Mouse input ────────────────────────────────────────────────────────

func get_cell_at_pos(pos: Vector2) -> Vector2i:
	if datas_flat.is_empty() or actual_row_height <= 0:
		return Vector2i(-1, -1)
	var row = int(pos.y / actual_row_height)
	if row < 0 or row >= datas_flat.size():
		return Vector2i(-1, -1)

	var x = 0.0
	for c in range(col_widths.size()):
		var w = col_widths[c]
		if pos.x >= x and pos.x < x + w:
			var data_col = c - int(show_frame)
			if data_col < 0 or data_col >= columns.size():
				return Vector2i(-1, -1)
			return Vector2i(row, data_col)
		x += w
	return Vector2i(-1, -1)

func _on_row_container_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.pressed:
			var cell_pos = get_cell_at_pos(mb.position)
			if cell_pos.x < 0 or cell_pos.y < 0:
				return

			exclude_mode = false
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.shift_pressed:
					_handle_shift_click(cell_pos)
				elif mb.ctrl_pressed:
					_handle_ctrl_click(cell_pos)
				else:
					_handle_normal_click(cell_pos)

			if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
				if cell_pos.x < datas_flat.size():
					row_clicked.emit(cell_pos.x, mb.button_index, datas_flat[cell_pos.x])
		else:
			# Mouse release
			if exclude_mode and start_drag:
				commit_exclude_border()
			if start_drag_with_ctrl and exclude_mode:
				commit_exclude_border()
			start_drag = false
			start_drag_with_ctrl = false
			exclude_mode = false

	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT and start_drag:
			var cell_pos = get_cell_at_pos(mm.position)
			if cell_pos.x >= 0 and cell_pos.y >= 0:
				var anchor = last_selected_pos
				var start_p = Vector2i(min(anchor.x, cell_pos.x), min(anchor.y, cell_pos.y))
				var end_p = Vector2i(max(anchor.x, cell_pos.x) + 1, max(anchor.y, cell_pos.y) + 1)
				var drag_rect = Rect2(start_p.x, start_p.y, end_p.x - start_p.x, end_p.y - start_p.y)
				var border = {
					"start": anchor,
					"rect": drag_rect,
					"ctrl": start_drag_with_ctrl
				}
				if start_drag_with_ctrl and exclude_mode:
					add_exclude_border(border)
				else:
					add_border(border)

func _handle_normal_click(cell_pos: Vector2i):
	start_drag = true
	start_drag_with_ctrl = false
	clear_borders()
	var border = {
		"start": cell_pos,
		"rect": Rect2(cell_pos.x, cell_pos.y, 1, 1)
	}
	add_border(border)
	if editable:
		inspect_highlight_rows()

func _handle_shift_click(cell_pos: Vector2i):
	start_drag = true
	start_drag_with_ctrl = false
	var anchor = last_selected_pos
	var start_p = Vector2i(min(anchor.x, cell_pos.x), min(anchor.y, cell_pos.y))
	var end_p = Vector2i(max(anchor.x, cell_pos.x) + 1, max(anchor.y, cell_pos.y) + 1)
	var rect = Rect2(start_p.x, start_p.y, end_p.x - start_p.x, end_p.y - start_p.y)
	var border = {
		"start": anchor,
		"rect": rect
	}
	add_border(border)

func _handle_ctrl_click(cell_pos: Vector2i):
	start_drag = true
	start_drag_with_ctrl = true
	last_selected_pos = cell_pos
	if pos_is_selected(cell_pos):
		exclude_mode = true
		var border = {
			"start": cell_pos,
			"rect": Rect2(cell_pos.x, cell_pos.y, 1, 1),
			"ctrl": true
		}
		add_exclude_border(border)
	else:
		var border = {
			"start": cell_pos,
			"rect": Rect2(cell_pos.x, cell_pos.y, 1, 1),
			"ctrl": true
		}
		add_border(border)

# ── Frame / header click handlers ──────────────────────────────────────

func _on_frame_btn_pressed(data_idx: int, btn: Button):
	if Input.is_key_pressed(KEY_SHIFT):
		var anchor = last_selected_pos
		var start_r = min(anchor.x, data_idx)
		var end_r = max(anchor.x, data_idx) + 1
		var rect = Rect2(start_r, 0, end_r - start_r, columns.size())
		var border = {"start": anchor, "rect": rect}
		add_border(border)
	elif Input.is_key_pressed(KEY_CTRL):
		var all_selected = true
		for c in columns.size():
			if not pos_is_selected(Vector2i(data_idx, c)):
				all_selected = false
				break
		var rect = Rect2(data_idx, 0, 1, columns.size())
		var border = {"start": Vector2i(data_idx, 0), "rect": rect, "ctrl": true}
		if all_selected:
			add_exclude_border(border)
			commit_exclude_border()
		else:
			add_border(border)
	else:
		clear_borders()
		var rect = Rect2(data_idx, 0, 1, columns.size())
		var border = {"start": Vector2i(data_idx, 0), "rect": rect}
		add_border(border)
		if editable:
			inspect_highlight_rows()

func _on_header_col_pressed(i: int):
	if _drag_press_active:
		return
	if i < int(show_frame) or i >= header_buttons.size() or datas_flat.is_empty():
		return
	var dc = i - int(show_frame)  # col_widths index → data column index
	if Input.is_key_pressed(KEY_SHIFT):
		var anchor = last_selected_pos
		var start_c = min(anchor.y, dc)
		var end_c = max(anchor.y, dc) + 1
		var rect = Rect2(0, start_c, datas_flat.size(), end_c - start_c)
		var border = {"start": anchor, "rect": rect}
		add_border(border)
	elif Input.is_key_pressed(KEY_CTRL):
		var all_selected = true
		for r in datas_flat.size():
			if not pos_is_selected(Vector2i(r, dc)):
				all_selected = false
				break
		var rect = Rect2(0, dc, datas_flat.size(), 1)
		var border = {"start": Vector2i(0, dc), "rect": rect, "ctrl": true}
		if all_selected:
			add_exclude_border(border)
			commit_exclude_border()
		else:
			add_border(border)
	else:
		clear_borders()
		var rect = Rect2(0, dc, datas_flat.size(), 1)
		var border = {"start": Vector2i(0, dc), "rect": rect}
		add_border(border)

func _on_select_all_btn_pressed():
	if datas_flat.is_empty() or columns.is_empty():
		return
	clear_borders()
	var border = {
		"start": Vector2i.ZERO,
		"rect": Rect2(0, 0, datas_flat.size(), columns.size())
	}
	add_border(border)
	if editable:
		inspect_highlight_rows()

# ── Row operations ─────────────────────────────────────────────────────

func highlight_row(data_idx: int):
	if data_idx < 0 or data_idx >= datas_flat.size() or columns.is_empty():
		return
	clear_borders()
	var border = {
		"start": Vector2i(data_idx, 0),
		"rect": Rect2(data_idx, 0, 1, columns.size())
	}
	add_border(border)

func row_grab_focus(data_idx: int):
	highlight_row(data_idx)
	if data_idx < datas_flat.size() and datas_flat[data_idx] is Object and editable:
		EditorInterface.inspect_object(datas_flat[data_idx])
		await get_tree().process_frame
		for i: MenuButton in EditorInterface.get_inspector().get_parent().find_children("@MenuButton*", "MenuButton", true, false):
			if i.tooltip_text in ["Manage object properties.", tr("Manage object properties.")]:
				i.get_popup().emit_signal("id_pressed", 12)
				break

# ── Shortcut button callbacks ──────────────────────────────────────────

func _on_button_select_all_pressed():
	_on_select_all_btn_pressed()

func _on_button_edit_pressed():
	inspect_highlight_rows()

func _on_button_copy_pressed():
	var data_list = get_data_of_highlight_rows()
	if data_list.is_empty():
		return
	var lines = []
	for d in data_list:
		var row_arr = []
		for c in columns.size():
			var val = ""
			if d is Array and c < d.size():
				val = str(d[c])
			elif d is Dictionary:
				if columns.size() > c:
					var keys = d.keys()
					if c < keys.size() and keys[c] in d:
						val = str(d[keys[c]])
			elif d is GDSQL.DictionaryObject:
				val = str(d._get_by_index(c))
			row_arr.append(val)
		lines.append("\t".join(row_arr))
	DisplayServer.clipboard_set("\n".join(lines))

func _on_button_paste_pressed():
	var text = DisplayServer.clipboard_get()
	if text.is_empty():
		return
	var lines = text.split("\n")
	var data_list = get_data_of_highlight_rows()
	if data_list.is_empty():
		return
	for i in min(lines.size(), data_list.size()):
		var vals = lines[i].split("\t")
		var d = data_list[i]
		for j in min(vals.size(), columns.size()):
			if d is GDSQL.DictionaryObject:
				if not (d.get_prop_usage_by_index(j) & PROPERTY_USAGE_READ_ONLY):
					d._set_by_index(j, vals[j])

func _on_button_delete_pressed():
	var data_list = get_data_of_highlight_rows()
	for d in data_list:
		if d is GDSQL.DictionaryObject:
			for c in columns.size():
				if not (d.get_prop_usage_by_index(c) & PROPERTY_USAGE_READ_ONLY):
					d._set_default_by_index(c)

func _on_button_delete_row_pressed():
	var rows_idx = []
	for b in selected_borders:
		var r = b["rect"] as Rect2
		for i in range(int(r.position.x), int(r.end.x)):
			if not rows_idx.has(i):
				rows_idx.append(i)
	rows_idx.sort()
	rows_idx.reverse()
	for i in rows_idx:
		if i < datas_flat.size():
			row_deleted.emit(datas_flat[i])
			datas_flat.remove_at(i)
	clear_borders()
	update_content_size()
	update_frame_col_width_if_needed()
	_on_scroll(scroll_container.scroll_vertical)

# ── Popup menu ─────────────────────────────────────────────────────────

func _on_popup_menu_index_pressed(index: int):
	match index:
		0:  # Copy Field
			var data_list = get_data_of_highlight_rows()
			if data_list.is_empty():
				return
			var arr = []
			for d in data_list:
				for c in columns.size():
					var val = str(d._get_by_index(c)) if d is GDSQL.DictionaryObject else str(d)
					arr.append(val)
					break
			DisplayServer.clipboard_set("\n".join(arr))
		1:  # Copy Line
			var data_list = get_data_of_highlight_rows()
			if data_list.is_empty():
				return
			var lines = []
			for d in data_list:
				var row_arr = []
				for c in columns.size():
					var val = str(d._get_by_index(c)) if d is GDSQL.DictionaryObject else str(d)
					row_arr.append(val)
				lines.append("\t".join(row_arr))
			DisplayServer.clipboard_set("\n".join(lines))
		2:  # Delete
			var data_list = get_data_of_highlight_rows()
			for d in data_list:
				if d is GDSQL.DictionaryObject:
					for c in columns.size():
						if not (d.get_prop_usage_by_index(c) & PROPERTY_USAGE_READ_ONLY):
							d._set_default_by_index(c)

# ── Inspector ──────────────────────────────────────────────────────────

func inspect_highlight_rows():
	var data_list = get_data_of_highlight_rows()
	if data_list.is_empty():
		return
	if data_list.size() == 1:
		var obj = data_list[0]
		if obj is Object:
			EditorInterface.inspect_object(obj)
			await get_tree().process_frame
			for i: MenuButton in EditorInterface.get_inspector().get_parent().find_children("@MenuButton*", "MenuButton", true, false):
				if i.tooltip_text in ["Manage object properties.", tr("Manage object properties.")]:
					i.get_popup().emit_signal("id_pressed", 12)
					break
		return

	var common_usage = {}
	for d in data_list:
		if not d is GDSQL.DictionaryObject:
			continue
		var plist = (d as Object).get_property_list()
		for p in plist:
			if not common_usage.has(p["name"]):
				common_usage[p["name"]] = p["usage"]
			elif common_usage[p["name"]] != p["usage"] and common_usage[p["name"]] != PROPERTY_USAGE_DEFAULT:
				common_usage[p["name"]] = PROPERTY_USAGE_DEFAULT

	var impl_data = {}
	var impl_hint = {}
	for d in data_list:
		if not d is GDSQL.DictionaryObject:
			continue
		for c in columns.size():
			var prop_name = d.__get_index_prop(c)
			if not impl_hint.has(prop_name):
				impl_hint[prop_name] = {
					"type": d.get_prop_type_by_index(c),
					"usage": common_usage.get(prop_name, PROPERTY_USAGE_DEFAULT),
					"hint": d.get_prop_hint_by_index(c),
					"hint_string": d.get_meta(prop_name.to_snake_case() + "_enum_hint_string_dict", ""),
				}
				impl_data[prop_name] = null
			var val = d._get_by_index(c)
			if impl_data[prop_name] == null:
				impl_data[prop_name] = val
			elif impl_data[prop_name] != val:
				impl_data[prop_name] = null

	var impl = GDSQL.DictionaryObject.new(impl_data, impl_hint)
	var on_change = func(prop, new_val, _old_val):
		for d in data_list:
			if not is_instance_valid(d):
				continue
			if d is GDSQL.DictionaryObject and not (d.get_prop_usage(prop) & PROPERTY_USAGE_READ_ONLY):
				d.set(prop, new_val)
	impl.value_changed.connect(on_change)
	EditorInterface.inspect_object(impl)
	await get_tree().process_frame
	for i: MenuButton in EditorInterface.get_inspector().get_parent().find_children("@MenuButton*", "MenuButton", true, false):
		if i.tooltip_text in ["Manage object properties.", tr("Manage object properties.")]:
			i.get_popup().emit_signal("id_pressed", 12)
			break

# ── Misc ────────────────────────────────────────────────────────────────

func _on_vbar_visibility_changed():
	header_container.queue_sort()
	_on_table_resized()

func _split_tooltip(content: String) -> String:
	const L = 40
	var total = content.length()
	if total <= L:
		return content
	var arr = []
	var start = 0
	while start < total:
		if start + L >= total:
			arr.append(content.substr(start))
			break
		var ch = content.unicode_at(start + L)
		if ch >= 0x4e00 and ch <= 0x9fff:
			arr.append(content.substr(start, L))
			start += L
		else:
			var idx = content.find(" ", start + L)
			if idx == -1:
				arr.append(content.substr(start))
				break
			arr.append(content.substr(start, idx - start))
			start = idx + 1
	return "\n".join(arr)

func _on_data_area_mouse_entered():
	pass

func _on_data_area_mouse_exited():
	pass

func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		_remove_corner_dragger()
		clear_borders()
	elif what == NOTIFICATION_ENTER_TREE:
		_entered_tree = true

# ── Additional helper functions ──────────────────────────────────────────

func _draw_corner_dragger():
	if selected_borders.is_empty():
		return
	var rect = selected_borders.front()["rect"] as Rect2
	var last_row = int(rect.end.x) - 1
	var last_col = int(rect.end.y) - 1
	if last_row < 0 or last_col < 0:
		return
	var ci = last_col + int(show_frame)
	if ci < 0 or ci >= col_widths.size():
		return
	var cx = _get_col_x(ci) + col_widths[ci]
	var cy = (last_row + 1) * actual_row_height - scroll_container.scroll_vertical
	var s = 5.0
	var pts = PackedVector2Array([
		Vector2(cx, cy - s),
		Vector2(cx - s, cy),
		Vector2(cx, cy)
	])
	borders_overlay.draw_colored_polygon(pts, Color(1, 1, 1, 0.7))
	borders_overlay.draw_line(Vector2(cx - s, cy), Vector2(cx, cy - s), Color(1, 1, 1, 0.9), 1.0)

func get_cell_at_screen_pos(screen_pos: Vector2) -> Vector2i:
	if not is_instance_valid(borders_overlay) or datas_flat.is_empty():
		return Vector2i(-1, -1)
	var local_pos = screen_pos - borders_overlay.global_position
	var scroll_val = scroll_container.scroll_vertical
	if actual_row_height <= 0:
		return Vector2i(-1, -1)
	var row = int((local_pos.y + scroll_val) / actual_row_height)
	if row < 0 or row >= datas_flat.size():
		return Vector2i(-1, -1)

	var x = 0.0
	for c in range(col_widths.size()):
		var w = col_widths[c]
		if local_pos.x >= x and local_pos.x < x + w:
			var data_col = c - int(show_frame)
			if data_col < 0 or data_col >= columns.size():
				return Vector2i(-1, -1)
			return Vector2i(row, data_col)
		x += w
	return Vector2i(-1, -1)

func _dofill_extend(src_start: Vector2, src_end: Vector2, tgt_start: Vector2, tgt_end: Vector2):
	# Fill cells in target region by repeating pattern from source region
	var src_h = int(src_end.x - src_start.x)
	var src_w = int(src_end.y - src_start.y)
	if src_h <= 0 or src_w <= 0:
		return
	var tgt_h = int(tgt_end.x - tgt_start.x)
	var tgt_w = int(tgt_end.y - tgt_start.y)
	if tgt_h <= 0 or tgt_w <= 0:
		return

	for dr in range(tgt_h):
		for dc in range(tgt_w):
			var tgt_row = int(tgt_start.x) + dr
			var tgt_col = int(tgt_start.y) + dc
			if tgt_row >= datas_flat.size() or tgt_col >= columns.size():
				continue
			var src_row = int(src_start.x) + dr % src_h
			var src_col = int(src_start.y) + dc % src_w
			var src_data = datas_flat[src_row]
			var tgt_data = datas_flat[tgt_row]
			if src_data is GDSQL.DictionaryObject and tgt_data is GDSQL.DictionaryObject:
				if not (tgt_data.get_prop_usage_by_index(tgt_col) & PROPERTY_USAGE_READ_ONLY):
					tgt_data._set_by_index(tgt_col, src_data._get_by_index(src_col))

func _fill_cell_from_samples(samples: Array, target_row: int, target_col: int):
	# Fill a single cell using least-squares extrapolation from sample cells
	if samples.size() < 2 or target_row >= datas_flat.size() or target_col >= columns.size():
		return
	var xs = []
	var ys = []
	for s in samples:
		xs.append(s[0])
		var d = datas_flat[s[0]]
		if d is GDSQL.DictionaryObject:
			ys.append(d._get_by_index(s[1]))
	target_row = clampi(target_row, 0, datas_flat.size() - 1)
	var tgt = datas_flat[target_row]
	if tgt is GDSQL.DictionaryObject:
		if not (tgt.get_prop_usage_by_index(target_col) & PROPERTY_USAGE_READ_ONLY):
			tgt._set_by_index(target_col, _least_squares_predict(xs, ys, float(target_row)))

func _least_squares_predict(xs: Array, ys: Array, x: float) -> float:
	if xs.size() != ys.size() or xs.size() < 2:
		return x
	var n = float(xs.size())
	var sum_x = 0.0
	var sum_y = 0.0
	var sum_xy = 0.0
	var sum_xx = 0.0
	for i in xs.size():
		var xi = float(xs[i])
		var yi = float(ys[i])
		sum_x += xi
		sum_y += yi
		sum_xy += xi * yi
		sum_xx += xi * xi
	var slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x) if (n * sum_xx - sum_x * sum_x) != 0 else 0.0
	var intercept = (sum_y - slope * sum_x) / n
	return slope * x + intercept

func _dofill_clear(start_pos: Vector2, end_pos: Vector2):
	# Clear (set to default) all cells in the given region
	for r in range(int(start_pos.x), int(end_pos.x)):
		for c in range(int(start_pos.y), int(end_pos.y)):
			if r < datas_flat.size() and c < columns.size():
				var d = datas_flat[r]
				if d is GDSQL.DictionaryObject:
					if not (d.get_prop_usage_by_index(c) & PROPERTY_USAGE_READ_ONLY):
						d._set_default_by_index(c)



# ── Additional helpers and utilities ────────────────────────────────────

func _get_data_by_cell(row: int, col: int):
	if row < 0 or row >= datas_flat.size() or col < 0 or col >= columns.size():
		return null
	var d = datas_flat[row]
	if d is Array and col < d.size():
		return d[col]
	elif d is Dictionary:
		if columns[col] in d:
			return d[columns[col]]
	elif d is GDSQL.DictionaryObject:
		return d._get_by_index(col)
	return null

func _set_data_by_cell(row: int, col: int, value):
	if row < 0 or row >= datas_flat.size() or col < 0 or col >= columns.size():
		return
	var d = datas_flat[row]
	if d is GDSQL.DictionaryObject:
		if not (d.get_prop_usage_by_index(col) & PROPERTY_USAGE_READ_ONLY):
			d._set_by_index(col, value)

func _update_borders_after_scroll():
	if selected_borders.is_empty():
		return
	borders_overlay.queue_redraw()
	_update_dragger_position()

func _on_menu_copy_field():
	var data_list = get_data_of_highlight_rows()
	if data_list.is_empty():
		return
	var arr = []
	for d in data_list:
		if columns.size() > 0:
			var val = _get_data_by_cell(datas_flat.find(d), 0) if datas_flat.has(d) else ""
			arr.append(str(val))
	DisplayServer.clipboard_set("\n".join(arr))

func _on_menu_copy_line():
	var data_list = get_data_of_highlight_rows()
	if data_list.is_empty():
		return
	var lines = []
	for d in data_list:
		var row_arr = []
		var idx = datas_flat.find(d)
		for c in columns.size():
			var val = _get_data_by_cell(idx, c) if idx >= 0 else ""
			row_arr.append(str(val))
		lines.append("\t".join(row_arr))
	DisplayServer.clipboard_set("\n".join(lines))

func _on_menu_delete_selected():
	var data_list = get_data_of_highlight_rows()
	for d in data_list:
		if d is GDSQL.DictionaryObject:
			for c in columns.size():
				if not (d.get_prop_usage_by_index(c) & PROPERTY_USAGE_READ_ONLY):
					d._set_default_by_index(c)

func _select_all():
	if datas_flat.is_empty() or columns.is_empty():
		return
	clear_borders()
	selected_borders.append({
		"start": Vector2i.ZERO,
		"rect": Rect2(0, 0, datas_flat.size(), columns.size())
	})
	borders_overlay.queue_redraw()

func _focus_first_cell():
	if datas_flat.is_empty() or columns.is_empty():
		return
	clear_borders()
	var border = {
		"start": Vector2i(0, 0),
		"rect": Rect2(0, 0, 1, 1)
	}
	add_border(border)

func _ensure_selection_visible():
	if selected_borders.is_empty():
		return
	var rect = selected_borders.front()["rect"] as Rect2
	var last_row = int(rect.end.x) - 1
	if last_row >= 0 and last_row < row_container.custom_minimum_size.y / max(1, actual_row_height):
		return
	update_content_size()

func _get_selection_bounds() -> Rect2:
	if selected_borders.is_empty():
		return Rect2()
	var combined = Rect2()
	for b in selected_borders:
		var r = b["rect"] as Rect2
		if combined == Rect2():
			combined = r
		else:
			combined = combined.merge(r)
	return combined

func _is_row_selected(row: int) -> bool:
	for b in selected_borders:
		var r = b["rect"] as Rect2
		if row >= r.position.x and row < r.end.x:
			return true
	return false

func _is_col_selected(col: int) -> bool:
	for b in selected_borders:
		var r = b["rect"] as Rect2
		if col >= r.position.y and col < r.end.y:
			return true
	return false

func _get_selected_rows() -> Array:
	var rows = []
	for b in selected_borders:
		var r = b["rect"] as Rect2
		for i in range(int(r.position.x), int(r.end.x)):
			if not rows.has(i):
				rows.append(i)
	return rows

func _get_selected_cols() -> Array:
	var cols = []
	for b in selected_borders:
		var r = b["rect"] as Rect2
		for i in range(int(r.position.y), int(r.end.y)):
			if not cols.has(i):
				cols.append(i)
	return cols

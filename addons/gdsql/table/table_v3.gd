@tool
extends Control

signal row_clicked(row_index: int, mouse_button_index: int, data)
enum MENU_ID { COPY_FIELD = 0, COPY_LINE = 1, DELETE = 2 }
enum RowHeightMode { FIXED, ADAPTIVE }
enum FRAME_MENU_ID {
	MODE_FIXED = 100,
	MODE_ADAPTIVE = 101,
	CUSTOM_ALL = 200,
	CUSTOM_SELECTED = 201,
	CUSTOM_CURRENT = 202,
	RESET_SELECTED = 203,
	RESET_CURRENT = 204,
	RESET_ALL = 205,
}

const ALL_STATES = ["hover", "pressed", "hover_pressed", "hover_mirrored", "pressed_mirrored", "hover_pressed_mirrored"]
signal row_deleted(datas) # {index: data}

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
## 行的高度是否进行扩展并填充
@export var row_expend_and_fill: bool = false
## 是否允许用户通过序号列右键菜单自定义行高
@export var enable_custom_row_height: bool = false
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
				_on_scroll(data_scroll.scroll_vertical)

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
				_on_scroll(data_scroll.scroll_vertical)

# ── Constants ───────────────────────────────────────────────────────────────

@export var row_height: int = 44:
	set(val):
		row_height = maxi(1, val)
		actual_row_height = row_height
		if is_node_ready():
			invalidate_all_row_heights()

@export var row_height_mode: RowHeightMode = RowHeightMode.FIXED:
	set(val):
		row_height_mode = val
		if is_node_ready():
			invalidate_all_row_heights()
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
var data_area: HBoxContainer
var frame_scroll: Control
var data_scroll: ScrollContainer
var frame_row_container: Control
var data_row_container: Control
var borders_overlay: Control
var popup_menu_text: PopupMenu
var frame_popup_menu: PopupMenu
var row_height_mode_popup: PopupMenu
var custom_row_height_popup: PopupMenu
var row_height_dialog: AcceptDialog
var row_height_spin_box: SpinBox
var frame_header_btn: Button
var data_header_wrapper: Control
var data_header_hbox: HBoxContainer

var label_model: Label
var texture_rect_model: TextureRect
var check_box_model: CheckBox
var row_panel_model: PanelContainer
var row_model: HBoxContainer

# ── State ───────────────────────────────────────────────────────────────────

var col_widths: Array[float] = []        # pixel widths per data column only
var header_buttons: Array[Button] = []    # data column header buttons only (no frame)
var header_spacer: Control = null
var frame_col_width: float = 48.0         # frame column width (separate from col_widths)

var data_row_pool: Array[Control] = []    # pooled data row nodes
var data_pool_in_use: Array[bool] = []
var frame_row_pool: Array[Control] = []   # pooled frame row nodes
var frame_pool_in_use: Array[bool] = []
var first_visible_idx := 0
var last_visible_idx := -1

var datas_flat: Array = []                # working copy (mirror of datas)
var _entered_tree := false

var vbox_container: VBoxContainer

# Selection / border state
var selected_borders: Array[Dictionary] = []
var last_selected_pos := Vector2i(0, 0)
var start_drag := false
var start_drag_with_ctrl := false
var exclude_mode := false
var exclude_border: Dictionary = {}
var exclude_border_active := false

var actual_row_height = row_height
var row_heights: Array[float] = []
var row_offsets: Array[float] = [0.0]
var row_height_dirty: Dictionary = {}
var custom_row_heights: Dictionary = {}
var _row_offsets_dirty := true
var _force_row_layout_refresh := false
var _row_height_menu_row := -1
var _row_height_edit_scope := ""
var _row_height_edit_row := -1
var _default_row_height := 44
var _header_drag_start_col := -1
var _header_drag_active := false
var _header_drag_ctrl := false
var _frame_drag_start_row := -1
var _frame_drag_active := false
var _frame_drag_ctrl := false
var _header_did_drag := false
var _frame_did_drag := false

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
	_default_row_height = row_height
	_construct_tree()
	style_box_empty = StyleBoxEmpty.new()
	await get_tree().process_frame
	rebuild_header()
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
	data_scroll.resized.connect(_update_borders_overlay_size)

	# Scroll listener (built-in v_bar)
	var data_v_bar = data_scroll.get_v_scroll_bar()
	data_v_bar.value_changed.connect(_on_data_scroll_changed)
	data_v_bar.visibility_changed.connect(_on_vbar_resized)

	var data_h_bar = data_scroll.get_h_scroll_bar()
	data_h_bar.value_changed.connect(_on_data_hscroll_changed)

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
	label_model.mouse_filter = Control.MOUSE_FILTER_PASS
	label_model.clip_text = true
	models.add_child(label_model)

	texture_rect_model = TextureRect.new()
	texture_rect_model.name = "TextureRectModel"
	texture_rect_model.mouse_filter = Control.MOUSE_FILTER_PASS
	models.add_child(texture_rect_model)

	check_box_model = CheckBox.new()
	check_box_model.name = "CheckBoxModel"
	check_box_model.mouse_filter = Control.MOUSE_FILTER_PASS
	models.add_child(check_box_model)

	# ── Header (rebuilt by rebuild_header) ──
	header_container = HBoxContainer.new()
	header_container.name = "HeaderContainer"
	header_container.add_theme_constant_override("separation", 0)
	header_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_container.add_child(header_container)

	# ── Data area (HBoxContainer: frame_scroll + data_scroll) ──
	data_area = HBoxContainer.new()
	data_area.name = "DataArea"
	data_area.add_theme_constant_override("separation", 0)
	data_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox_container.add_child(data_area)

	# Frame column (Control with clip_contents, no ScrollContainer)
	frame_scroll = Control.new()
	frame_scroll.name = "FrameScroll"
	frame_scroll.custom_minimum_size.x = 48
	frame_scroll.clip_contents = true
	frame_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	data_area.add_child(frame_scroll)

	frame_row_container = Control.new()
	frame_row_container.name = "FrameRowContainer"
	frame_row_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame_row_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame_scroll.add_child(frame_row_container)

	# Data scroll (vertical + horizontal)
	data_scroll = ScrollContainer.new()
	data_scroll.name = "DataScroll"
	data_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb = StyleBoxEmpty.new()
	sb.content_margin_top = 2
	data_scroll.add_theme_stylebox_override("panel", sb)
	data_area.add_child(data_scroll)

	data_row_container = Control.new()
	data_row_container.name = "DataRowContainer"
	data_row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data_row_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	data_row_container.focus_mode = Control.FOCUS_ALL
	data_scroll.add_child(data_row_container)

	# Mouse events on data_row_container for selection
	data_row_container.gui_input.connect(_on_data_row_container_gui_input)
	data_row_container.mouse_entered.connect(_on_data_area_mouse_entered)
	data_row_container.mouse_exited.connect(_on_data_area_mouse_exited)

	# Borders overlay — direct child of root, positioned to cover data_scroll
	borders_overlay = Control.new()
	borders_overlay.name = "BordersOverlay"
	borders_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	borders_overlay.clip_contents = true
	borders_overlay.draw.connect(_on_borders_overlay_draw)
	add_child(borders_overlay)

	# ── Popup menu ──
	popup_menu_text = PopupMenu.new()
	# 根据 show_frame 控制序号列显示
	frame_scroll.visible = show_frame
	if not show_frame:
		frame_scroll.custom_minimum_size.x = 0
	popup_menu_text.name = "PopupMenuText"
	var icon_copy = load("res://addons/gdsql/img/copy.svg")
	var icon_trash = load("res://addons/gdsql/img/trash-can.svg")
	popup_menu_text.add_item("Copy Field", MENU_ID.COPY_FIELD)
	if icon_copy:
		popup_menu_text.set_item_icon(popup_menu_text.get_item_index(MENU_ID.COPY_FIELD), icon_copy)
	popup_menu_text.add_item("Copy Line", MENU_ID.COPY_LINE)
	popup_menu_text.add_separator()
	popup_menu_text.add_item("Delete", MENU_ID.DELETE)
	if icon_trash:
		popup_menu_text.set_item_icon(popup_menu_text.get_item_index(MENU_ID.DELETE), icon_trash)
	popup_menu_text.set_item_disabled(popup_menu_text.get_item_index(MENU_ID.DELETE), true)
	popup_menu_text.index_pressed.connect(_on_popup_menu_index_pressed)
	vbox_container.add_child(popup_menu_text)

	frame_popup_menu = PopupMenu.new()
	frame_popup_menu.name = "FramePopupMenu"
	row_height_mode_popup = PopupMenu.new()
	row_height_mode_popup.name = "RowHeightModePopup"
	custom_row_height_popup = PopupMenu.new()
	custom_row_height_popup.name = "CustomRowHeightPopup"
	row_height_mode_popup.add_check_item("Fixed", FRAME_MENU_ID.MODE_FIXED)
	row_height_mode_popup.add_check_item("Adaptive", FRAME_MENU_ID.MODE_ADAPTIVE)
	custom_row_height_popup.add_item("All Rows", FRAME_MENU_ID.CUSTOM_ALL)
	custom_row_height_popup.add_item("Selected Rows", FRAME_MENU_ID.CUSTOM_SELECTED)
	custom_row_height_popup.add_item("Current Row", FRAME_MENU_ID.CUSTOM_CURRENT)
	custom_row_height_popup.add_separator()
	custom_row_height_popup.add_item("Reset Selected Rows", FRAME_MENU_ID.RESET_SELECTED)
	custom_row_height_popup.add_item("Reset Current Row", FRAME_MENU_ID.RESET_CURRENT)
	custom_row_height_popup.add_item("Reset All Custom Heights", FRAME_MENU_ID.RESET_ALL)
	frame_popup_menu.add_child(row_height_mode_popup)
	frame_popup_menu.add_child(custom_row_height_popup)
	frame_popup_menu.add_submenu_item("Row Height Mode", "RowHeightModePopup")
	frame_popup_menu.add_submenu_item("Custom Row Height", "CustomRowHeightPopup")
	row_height_mode_popup.id_pressed.connect(_on_frame_popup_id_pressed)
	custom_row_height_popup.id_pressed.connect(_on_frame_popup_id_pressed)
	vbox_container.add_child(frame_popup_menu)

	row_height_dialog = AcceptDialog.new()
	row_height_dialog.name = "RowHeightDialog"
	row_height_dialog.title = "Row Height"
	row_height_spin_box = SpinBox.new()
	row_height_spin_box.name = "RowHeightSpinBox"
	row_height_spin_box.min_value = 1
	row_height_spin_box.max_value = 4096
	row_height_spin_box.step = 1
	row_height_spin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_height_dialog.add_child(row_height_spin_box)
	row_height_dialog.register_text_enter(row_height_spin_box.get_line_edit())
	row_height_dialog.confirmed.connect(_on_row_height_dialog_confirmed, CONNECT_DEFERRED) # Must CONNECT_DEFERRED, or the value of row_height_spin_box is not latest.
	vbox_container.add_child(row_height_dialog)

	# ── Shortcut buttons (invisible) ──
	var shortcut_layer = Control.new()
	shortcut_layer.name = "ShortcutLayer"
	shortcut_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox_container.add_child(shortcut_layer)

	button_select_all = _make_shortcut_button(KEY_A, true)
	button_select_all.pressed.connect(_on_button_select_all_pressed)
	shortcut_layer.add_child(button_select_all)

	button_edit = _make_shortcut_button(KEY_ENTER, false, false, false, [KEY_SPACE, KEY_KP_ENTER])
	button_edit.modulate.a = 0
	button_edit.pressed.connect(_on_button_edit_button_down)
	shortcut_layer.add_child(button_edit)

	button_copy = _make_shortcut_button(KEY_C, true)
	button_copy.pressed.connect(_on_button_copy_pressed)
	shortcut_layer.add_child(button_copy)

	button_paste = _make_shortcut_button(KEY_V, true)
	button_paste.pressed.connect(_on_button_paste_pressed)
	shortcut_layer.add_child(button_paste)

	button_delete = _make_shortcut_button(KEY_DELETE)
	button_delete.pressed.connect(_on_button_delete_pressed)
	shortcut_layer.add_child(button_delete)

	button_delete_row = _make_shortcut_button(KEY_DELETE, false, true)
	button_delete_row.pressed.connect(_on_button_delete_row_pressed)
	shortcut_layer.add_child(button_delete_row)

func _make_shortcut_button(keycode: int, ctrl: bool = false, alt: bool = false, meta: bool = false, extra_keys: Array[int] = []) -> Button:
	var btn = Button.new()
	btn.flat = true
	var se = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", se)
	var sc = Shortcut.new()
	var ev = InputEventKey.new()
	ev.keycode = keycode
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	ev.meta_pressed = meta
	sc.events = [ev]
	for ek in extra_keys:
		var ek_ev = InputEventKey.new()
		ek_ev.keycode = ek
		sc.events.append(ek_ev)
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

	# Frame header button (when show_frame)
	if show_frame:
		frame_header_btn = Button.new()
		frame_header_btn.name = "FrameHeaderBtn"
		var arrow = load("res://addons/gdsql/img/right_and_down_arrow.svg")
		if arrow:
			frame_header_btn.icon = arrow
		frame_header_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		frame_header_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		frame_header_btn.pressed.connect(_on_select_all_btn_pressed)
		frame_header_btn.clip_text = true
		frame_header_btn.add_theme_stylebox_override("focus", style_box_empty)
		_update_frame_col_width()
		frame_header_btn.custom_minimum_size.x = frame_col_width
		frame_row_container.custom_minimum_size.x = frame_col_width
		frame_scroll.custom_minimum_size.x = frame_col_width
		header_container.add_child(frame_header_btn)

	# Data header wrapper (scrollable container for data column buttons)
	data_header_wrapper = Control.new()
	data_header_wrapper.name = "DataHeaderWrapper"
	data_header_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data_header_wrapper.clip_contents = true
	header_container.add_child(data_header_wrapper)

	data_header_hbox = HBoxContainer.new()
	data_header_hbox.name = "DataHeaderHBox"
	data_header_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	data_header_hbox.add_theme_constant_override("separation", 0)
	data_header_wrapper.add_child(data_header_hbox)

	# Build col_widths for DATA columns only (no frame column)
	var data_col_count = columns.size()
	if data_col_count == 0:
		vbox_container.queue_sort()
		data_area.queue_sort()
		return

	col_widths.resize(data_col_count)
	var available = _get_header_available_width()
	if ratios.is_empty():
		var w = max(MIN_COL_WIDTH, available / max(data_col_count, 1))
		for i in data_col_count:
			col_widths[i] = w
	else:
		var total_ratio = 0.0
		for r in ratios:
			total_ratio += r
			total_ratio = max(total_ratio, 0.001)
		var ratio_idx = 0
		for i in data_col_count:
			if ratio_idx < ratios.size():
				col_widths[i] = max(MIN_COL_WIDTH, available * ratios[ratio_idx] / total_ratio)
				ratio_idx += 1
			else:
				col_widths[i] = MIN_COL_WIDTH

	# Build data header buttons
	for i in data_col_count:
		var btn = Button.new()
		btn.text = str(columns[i])
		if column_tips.size() > i and not column_tips[i].is_empty():
			btn.tooltip_text = tr(column_tips[i])
		var arrow_down = load("res://addons/gdsql/img/arrow_down.svg")
		if arrow_down:
			btn.mouse_entered.connect(DisplayServer.cursor_set_custom_image.bind(arrow_down, DisplayServer.CURSOR_HELP, Vector2(12, 12)))
		btn.pressed.connect(_on_header_col_pressed.bind(i))
		btn.custom_minimum_size.x = col_widths[i]
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btn.clip_text = true
		btn.add_theme_stylebox_override("focus", style_box_empty)
		data_header_hbox.add_child(btn)
		header_buttons.append(btn)

	# Spacer (fills remaining space in data header)
	header_spacer = Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	data_header_hbox.add_child(header_spacer)

	# 设置 wrapper 高度为表头按钮的实际最小高度
	data_header_wrapper.custom_minimum_size.y = data_header_hbox.get_combined_minimum_size().y

	# 通知 VBoxContainer 重新布局
	vbox_container.queue_sort()

func _update_frame_col_width() -> float:
	if not show_frame:
		return 30.0
	var max_num = max(1, datas_flat.size())
	var w = max(48.0, len(str(max_num)) * 9.0 + 8.0)
	frame_col_width = w
	return w

func update_frame_col_width_if_needed():
	if show_frame:
		_update_frame_col_width()
		_apply_header_widths()
		if is_instance_valid(frame_header_btn):
			frame_header_btn.custom_minimum_size.x = frame_col_width
		sync_frame_row_widths()
		sync_data_row_widths()


func _get_header_available_width() -> float:
	var avail = max(100, header_container.size.x)
	if show_frame:
		avail -= frame_col_width
	return max(100, avail)

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
	sync_data_row_widths()
	_update_borders_overlay_size()
	borders_overlay.queue_redraw()


func _update_borders_overlay_size():
	if is_instance_valid(borders_overlay) and is_instance_valid(data_scroll):
		var sb = data_scroll.get_theme_stylebox("panel")
		var off = sb.get_offset() if sb else Vector2()
		var min_sz = sb.get_minimum_size() if sb else Vector2()
		borders_overlay.position = data_scroll.position + data_area.position + off
		borders_overlay.size = data_scroll.size - min_sz

func _apply_header_widths():
	for i in min(header_buttons.size(), col_widths.size()):
		header_buttons[i].custom_minimum_size.x = col_widths[i]
	if show_frame and is_instance_valid(frame_header_btn):
		frame_header_btn.custom_minimum_size.x = frame_col_width

# ── Header drag (position-based boundary detection) ──────────────────────

var _drag_col_idx := -1
var _drag_start_x := 0.0
var _drag_start_width := 0.0
var _drag_press_active := false
var _saved_hover_styles: Array = []

func _get_col_boundary_at_x(local_x: float) -> int:
	# local_x is in header_container coordinates.
	# Convert to data_header_hbox content coordinates (account for frame width and horizontal scroll).
	var hx = local_x
	if show_frame:
		hx -= frame_col_width
	hx += data_scroll.scroll_horizontal
	for i in range(col_widths.size()):
		var boundary = _get_col_x(i) + col_widths[i]
		if abs(hx - boundary) <= GRABBER_WIDTH:
			return i
	return -1

func _get_col_at_x(local_x: float) -> int:
	var hx = local_x
	if show_frame:
		hx -= frame_col_width
	hx += data_scroll.scroll_horizontal
	var x = 0.0
	for i in range(col_widths.size()):
		if hx >= x and hx < x + col_widths[i]:
			return i
		x += col_widths[i]
	return -1

func _input(event):
	if not is_node_ready() or not header_container.is_visible_in_tree():
		return
	var mouse_global = get_global_mouse_position()
	var over_header = header_container.get_rect().has_point(header_container.get_local_mouse_position())

	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and over_header:
				var header_pos = header_container.get_local_mouse_position()
				var col_idx = _get_col_boundary_at_x(header_pos.x)
				if col_idx >= 0:
					if mb.double_click:
						_auto_fit_column(col_idx)
						return
					_drag_col_idx = col_idx
					_drag_start_x = mouse_global.x
					_drag_start_width = col_widths[col_idx]
					_drag_press_active = true
					# 拖拽时禁用表头所有状态样式，避免闪烁
					_saved_hover_styles.clear()
					for hbtn in header_buttons:
						_saved_hover_styles.append(hbtn.get_theme_stylebox("hover"))
						_saved_hover_styles.append(hbtn.get_theme_stylebox("pressed"))
						_saved_hover_styles.append(hbtn.get_theme_stylebox("hover_pressed"))
						_saved_hover_styles.append(hbtn.get_theme_stylebox("hover_mirrored"))
						_saved_hover_styles.append(hbtn.get_theme_stylebox("pressed_mirrored"))
						_saved_hover_styles.append(hbtn.get_theme_stylebox("hover_pressed_mirrored"))
						var hbtn_ns = hbtn.get_theme_stylebox("normal")
						if hbtn_ns:
							hbtn.add_theme_stylebox_override("hover", hbtn_ns)
							hbtn.add_theme_stylebox_override("pressed", hbtn_ns)
							hbtn.add_theme_stylebox_override("hover_pressed", hbtn_ns)
							hbtn.add_theme_stylebox_override("hover_mirrored", hbtn_ns)
							hbtn.add_theme_stylebox_override("pressed_mirrored", hbtn_ns)
							hbtn.add_theme_stylebox_override("hover_pressed_mirrored", hbtn_ns)
					return  # don't let _gui_input see this event
				if col_idx < 0:
					var click_col = _get_col_at_x(header_pos.x)
					if click_col >= 0:
						_header_did_drag = false
						_header_drag_start_col = click_col
						_header_drag_active = true
						_header_drag_ctrl = Input.is_key_pressed(KEY_CTRL)

			elif not mb.pressed:
				if _drag_press_active:
					call_deferred("_clear_drag_flag")
				_drag_col_idx = -1
				_header_drag_active = false
				_header_drag_start_col = -1

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var redirect_scroll = false
			if is_instance_valid(data_scroll) and data_scroll.get_rect().has_point(data_scroll.get_local_mouse_position()):
				redirect_scroll = true
			elif show_frame and is_instance_valid(frame_scroll) and frame_scroll.get_rect().has_point(frame_scroll.get_local_mouse_position()):
				redirect_scroll = true
			elif is_instance_valid(header_container) and header_container.get_rect().has_point(header_container.get_local_mouse_position()):
				redirect_scroll = true
			if redirect_scroll:
				if Input.is_key_pressed(KEY_SHIFT):
					var h_bar = data_scroll.get_h_scroll_bar()
					if h_bar:
						var step = maxi(1, int(h_bar.page * 0.3))
						data_scroll.scroll_horizontal += step if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -step
				else:
					var v_bar = data_scroll.get_v_scroll_bar()
					if v_bar:
						var step = maxi(1, int(v_bar.page * 0.3))
						data_scroll.scroll_vertical += step if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -step
				accept_event()
				return

	if event is InputEventMouseMotion:
		if _header_drag_active and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			var ds_local = mouse_global - data_scroll.global_position
			var ds_rect = Rect2(Vector2.ZERO, data_scroll.size)
			if ds_local.x > ds_rect.size.x:
				data_scroll.scroll_horizontal += int((ds_local.x - ds_rect.size.x) * 0.3)
			elif ds_local.x < 0:
				data_scroll.scroll_horizontal += int(ds_local.x * 0.3)
			if ds_local.y > ds_rect.size.y:
				data_scroll.scroll_vertical += int((ds_local.y - ds_rect.size.y) * 0.3)
			elif ds_local.y < 0:
				data_scroll.scroll_vertical += int(ds_local.y * 0.3)
			var hp = header_container.get_local_mouse_position()
			var cur_col = _get_col_at_x(hp.x)
			if cur_col >= 0:
				_header_did_drag = true
				var start_c = mini(_header_drag_start_col, cur_col)
				var end_c = maxi(_header_drag_start_col, cur_col) + 1
				if _header_drag_ctrl:
					var rect = Rect2(0, start_c, datas_flat.size(), end_c - start_c)
					var border = {"start": Vector2i(0, _header_drag_start_col), "rect": rect, "ctrl": true}
					add_border(border)
				else:
					var rect = Rect2(0, start_c, datas_flat.size(), end_c - start_c)
					var border = {"start": Vector2i(0, _header_drag_start_col), "rect": rect}
					add_border(border)
		if _drag_col_idx >= 0:
			var dx = mouse_global.x - _drag_start_x
			var new_w = max(MIN_COL_WIDTH, _drag_start_width + dx)
			if new_w != col_widths[_drag_col_idx]:
				col_widths[_drag_col_idx] = new_w
				_apply_header_widths()
				sync_data_row_widths()
				if row_height_mode == RowHeightMode.ADAPTIVE:
					invalidate_all_row_heights()
				# Update total content width for horizontal scrollbar
				var tw = 0.0
				for w in col_widths:
					tw += w
				data_row_container.custom_minimum_size.x = tw
				data_scroll.queue_sort()
				_update_dragger_position()
				borders_overlay.queue_redraw()
		elif over_header:
			var header_pos = header_container.get_local_mouse_position()
			var col_idx = _get_col_boundary_at_x(header_pos.x)
			var want_hsize = col_idx >= 0
			for btn in header_buttons:
				if want_hsize:
					btn.mouse_default_cursor_shape = Control.CURSOR_HSIZE
				elif btn == frame_header_btn:
					btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
				else:
					btn.mouse_default_cursor_shape = Control.CURSOR_HELP
		else:
			for btn in header_buttons:
				if btn == frame_header_btn:
					btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
				else:
					btn.mouse_default_cursor_shape = Control.CURSOR_HELP

func _clear_drag_flag():
	_drag_press_active = false
	_drag_col_idx = -1
	# 恢复表头所有状态样式
	var si = 0
	for hbtn in header_buttons:
		for state_name in ALL_STATES:
			if si >= _saved_hover_styles.size():
				break
			var saved = _saved_hover_styles[si]
			si += 1
			if saved:
				hbtn.add_theme_stylebox_override(state_name, saved)
			else:
				hbtn.remove_theme_stylebox_override(state_name)
	_saved_hover_styles.clear()

## 双击列分隔线时，自动调整列宽以适应文字内容（仅文本，忽略非文本控件）
func _auto_fit_column(col_idx: int):
	if col_idx < 0 or col_idx >= col_widths.size():
		return

	var font = ThemeDB.fallback_font
	var font_size = ThemeDB.fallback_font_size
	if is_instance_valid(label_model):
		var lf = label_model.get_theme_font("font")
		if lf:
			font = lf
		var lfs = label_model.get_theme_font_size("font_size")
		if lfs > 0:
			font_size = lfs

	var max_width = 0.0

	# 测量表头文字宽度（含按钮内边距）
	if col_idx < header_buttons.size() and is_instance_valid(header_buttons[col_idx]):
		var btn = header_buttons[col_idx]
		var hf = btn.get_theme_font("font")
		if not hf:
			hf = font
		var hfs = btn.get_theme_font_size("font_size")
		if hfs <= 0:
			hfs = font_size
		var hw = hf.get_string_size(btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x
		# 加上按钮 stylebox 的左右内边距
		var btn_style = btn.get_theme_stylebox("normal")
		if btn_style:
			hw += btn_style.get_margin(SIDE_LEFT) + btn_style.get_margin(SIDE_RIGHT)
		if hw > max_width:
			max_width = hw

	# 测量所有数据行的文字宽度
	for row in datas_flat.size():
		var d = datas_flat[row]
		var val = _get_data_by_cell(row, col_idx)
		if val == null:
			continue
		# 跳过非文字的对象（如自定义显示控件、Resource 等），只看基础类型文字
		if val is Object:
			continue
		var text = str(val)

		# 处理 DictionaryObject 的枚举提示（显示枚举文本而非原始值）
		if d is GDSQL.DictionaryObject:
			var col_prop = d.__get_index_prop(col_idx).to_snake_case()
			var hint = d.get_meta(col_prop + "_enum_hint_string_dict", "")
			if hint != "":
				var pairs = hint.split(",")
				for p_str in pairs:
					var p = p_str.split(":")
					if p.size() == 2 and p[1].is_valid_int() and int(p[1]) == val:
						text = p[0]
						break

		if text.is_empty():
			continue
		var w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if w > max_width:
			max_width = w

	# 应用新宽度
	var new_width = max(MIN_COL_WIDTH, max_width + 16.0)
	if new_width != col_widths[col_idx]:
		col_widths[col_idx] = new_width
		_apply_header_widths()
		sync_data_row_widths()
		if row_height_mode == RowHeightMode.ADAPTIVE:
			invalidate_all_row_heights()

		var tw = 0.0
		for w in col_widths:
			tw += w
		# 通过完整 Vector2 赋值确保触发 minimum_size_changed
		data_row_container.custom_minimum_size = Vector2(tw, data_row_container.custom_minimum_size.y)
		# 直接更新横向滚动条范围
		var h_bar = data_scroll.get_h_scroll_bar()
		if h_bar:
			var view_w = data_scroll.size.x
			h_bar.max_value = max(0, tw - view_w)
			h_bar.page = view_w
			if not h_bar.visible and tw > view_w:
				h_bar.visible = true
			elif h_bar.visible and tw <= view_w:
				h_bar.visible = false
		data_scroll.queue_sort()
		_update_dragger_position()
		borders_overlay.queue_redraw()

func sync_frame_row_widths():
	if not show_frame:
		return
	for row_node in frame_row_pool:
		if row_node.visible:
			row_node.custom_minimum_size.x = frame_col_width
			var btn = row_node.get_child(0) if row_node.get_child_count() > 0 else null
			if btn is Button:
				btn.custom_minimum_size.x = frame_col_width

func sync_data_row_widths():
	for row_node in data_row_pool:
		if row_node.visible:
			_apply_data_row_widths(row_node)

func _apply_data_row_widths(row_node: Control):
	var hbox = row_node.get_child(0) if row_node.get_child_count() > 0 else null
	if hbox == null:
		return
	var wi = 0
	for child in hbox.get_children():
		if not (child is PanelContainer):
			continue
		if wi >= col_widths.size():
			break
		_apply_cell_width(child as PanelContainer, col_widths[wi])
		wi += 1

func _ensure_row_height_arrays():
	var count = datas_flat.size()
	while row_heights.size() < count:
		row_heights.append(float(row_height))
	while row_heights.size() > count:
		row_heights.pop_back()
	if row_offsets.size() != count + 1:
		_row_offsets_dirty = true

func _rebuild_row_offsets():
	_ensure_row_height_arrays()
	row_offsets.resize(datas_flat.size() + 1)
	row_offsets[0] = 0.0
	for i in datas_flat.size():
		row_offsets[i + 1] = row_offsets[i] + _get_row_height(i)
	_row_offsets_dirty = false

func _ensure_row_offsets():
	if _row_offsets_dirty:
		_rebuild_row_offsets()

func _get_row_height(row: int) -> float:
	if row < 0 or row >= datas_flat.size():
		return float(row_height)
	if custom_row_heights.has(row):
		return float(custom_row_heights[row])
	_ensure_row_height_arrays()
	return max(float(row_height), row_heights[row])

func _get_row_top(row: int) -> float:
	_ensure_row_offsets()
	if row <= 0:
		return 0.0
	if row >= row_offsets.size():
		return row_offsets.back()
	return row_offsets[row]

func _get_row_bottom(row: int) -> float:
	_ensure_row_offsets()
	if row < 0:
		return 0.0
	if row + 1 >= row_offsets.size():
		return row_offsets.back()
	return row_offsets[row + 1]

func _get_total_content_height() -> float:
	_ensure_row_offsets()
	return row_offsets.back() if not row_offsets.is_empty() else 0.0

func _get_row_at_content_y(content_y: float) -> int:
	if datas_flat.is_empty():
		return -1
	_ensure_row_offsets()
	var y = clampf(content_y, 0.0, max(0.0, _get_total_content_height() - 0.001))
	var lo = 0
	var hi = datas_flat.size() - 1
	while lo <= hi:
		var mid = (lo + hi) / 2
		if y < row_offsets[mid]:
			hi = mid - 1
		elif y >= row_offsets[mid + 1]:
			lo = mid + 1
		else:
			return mid
	return clampi(lo, 0, datas_flat.size() - 1)

func _get_visible_row_range(scroll_val: float, view_h: float) -> Vector2i:
	if datas_flat.is_empty() or view_h <= 0:
		return Vector2i(0, -1)
	var first = max(0, _get_row_at_content_y(scroll_val) - BUFFER_ROWS)
	var last = min(datas_flat.size() - 1, _get_row_at_content_y(scroll_val + view_h) + BUFFER_ROWS)
	return Vector2i(first, last)

func _has_dirty_rows_in_range(first: int, last: int) -> bool:
	if row_height_dirty.is_empty():
		return false
	for row in row_height_dirty:
		var row_idx = int(row)
		if row_idx >= first and row_idx <= last:
			return true
	return false

func _set_row_height_cache(row: int, height: float) -> bool:
	if row < 0 or row >= datas_flat.size() or custom_row_heights.has(row):
		return false
	_ensure_row_height_arrays()
	var new_height = max(float(row_height), height)
	if abs(row_heights[row] - new_height) < 0.5:
		row_height_dirty.erase(row)
		return false
	row_heights[row] = new_height
	row_height_dirty.erase(row)
	_row_offsets_dirty = true
	return true

func invalidate_row_height(row: int):
	if row < 0 or row >= datas_flat.size():
		return
	if row_height_mode == RowHeightMode.ADAPTIVE and not custom_row_heights.has(row):
		row_heights[row] = float(row_height)
		row_height_dirty[row] = true
	else:
		row_height_dirty.erase(row)
	_row_offsets_dirty = true
	_force_row_layout_refresh = true
	update_content_size()
	_on_scroll(data_scroll.scroll_vertical)
	borders_overlay.queue_redraw()

func invalidate_all_row_heights():
	_ensure_row_height_arrays()
	row_height_dirty.clear()
	for i in datas_flat.size():
		if not custom_row_heights.has(i):
			row_heights[i] = float(row_height)
			if row_height_mode == RowHeightMode.ADAPTIVE:
				row_height_dirty[i] = true
	_row_offsets_dirty = true
	_force_row_layout_refresh = true
	update_content_size()
	_on_scroll(data_scroll.scroll_vertical)
	borders_overlay.queue_redraw()
	call_deferred("_force_refresh_visible_rows")

func refresh_row_heights():
	invalidate_all_row_heights()

func _reset_adaptive_row_height_cache():
	row_heights.clear()
	row_offsets = [0.0]
	row_height_dirty.clear()
	_row_offsets_dirty = true
	_force_row_layout_refresh = true

func _shift_custom_row_heights(start_index: int, delta: int) -> Dictionary:
	var shifted = {}
	for row in custom_row_heights:
		var row_idx = int(row)
		if row_idx >= start_index:
			shifted[row_idx + delta] = custom_row_heights[row]
		else:
			shifted[row_idx] = custom_row_heights[row]
	return shifted

func _move_custom_row_height(from: int, to: int):
	if from == to:
		return
	var moved_value = custom_row_heights.get(from, null)
	var had_value = custom_row_heights.has(from)
	custom_row_heights.erase(from)
	if from < to:
		var shifted = {}
		for row in custom_row_heights:
			var row_idx = int(row)
			if row_idx > from and row_idx <= to:
				shifted[row_idx - 1] = custom_row_heights[row]
			else:
				shifted[row_idx] = custom_row_heights[row]
		custom_row_heights = shifted
	else:
		var shifted = {}
		for row in custom_row_heights:
			var row_idx = int(row)
			if row_idx >= to and row_idx < from:
				shifted[row_idx + 1] = custom_row_heights[row]
			else:
				shifted[row_idx] = custom_row_heights[row]
		custom_row_heights = shifted
	if had_value:
		custom_row_heights[to] = moved_value
	_row_offsets_dirty = true
	_force_row_layout_refresh = true

func _apply_row_height_to_row(row_node: Control, height: float):
	row_node.custom_minimum_size.y = height
	row_node.size.y = height
	var hbox = row_node.get_child(0) if row_node.get_child_count() > 0 else null
	if hbox is Control:
		(hbox as Control).custom_minimum_size.y = height
		(hbox as Control).size.y = height
		for child in (hbox as Control).get_children():
			if child is PanelContainer:
				(child as PanelContainer).custom_minimum_size.y = height
				(child as PanelContainer).size.y = height
				var wrapper = _get_cell_content_wrapper(child as PanelContainer)
				wrapper.custom_minimum_size.y = height
				wrapper.size.y = height

func _measure_data_row_height(row_node: Control) -> float:
	if row_height_mode == RowHeightMode.FIXED:
		return float(row_height)
	var measured = float(row_height)
	var hbox = row_node.get_child(0) if row_node.get_child_count() > 0 else null
	if hbox is Control:
		for cell in (hbox as Control).get_children():
			if not (cell is PanelContainer):
				continue
			var wrapper = _get_cell_content_wrapper(cell as PanelContainer)
			for child in wrapper.get_children():
				if child is Control:
					measured = max(measured, (child as Control).get_combined_minimum_size().y)
	return measured

# ── Virtual Scrolling ─────────────────────────────────────────────────────

func update_content_size():
	_ensure_row_height_arrays()
	var total_h = _get_total_content_height()
	data_row_container.custom_minimum_size.y = total_h
	if show_frame:
		frame_row_container.custom_minimum_size.y = total_h
		frame_row_container.custom_minimum_size.x = frame_col_width
		frame_scroll.custom_minimum_size.x = frame_col_width
	# Horizontal scroll extent = sum of all data column widths
	var total_w = 0.0
	for w in col_widths:
		total_w += w
	data_row_container.custom_minimum_size.x = total_w
	data_area.queue_sort()
	# Ensure ScrollContainer recalculates its scrollbars
	data_scroll.queue_sort()

func _on_scroll(value: float):
	if _scroll_guard:
		return
	_scroll_guard = true
	if datas_flat.is_empty():
		_hide_all_data_pool_rows()
		if show_frame:
			_hide_all_frame_pool_rows()
		borders_overlay.queue_redraw()
		first_visible_idx = 0
		last_visible_idx = -1
		_scroll_guard = false
		return

	var view_h = data_scroll.size.y
	if view_h <= 0:
		_scroll_guard = false
		return

	var visible_range = _get_visible_row_range(value, view_h)
	var new_first = visible_range.x
	var new_last = visible_range.y

	if new_first == first_visible_idx and new_last == last_visible_idx and not _force_row_layout_refresh and not _has_dirty_rows_in_range(new_first, new_last):
		_update_dragger_position()
		borders_overlay.queue_redraw()
		_scroll_guard = false
		return  # no row change, still need to redraw grid/dragger/overlay

	if new_first > new_last:
		_scroll_guard = false
		return

	first_visible_idx = new_first
	last_visible_idx = new_last
	_force_row_layout_refresh = false

	_position_visible_rows()
	# Row heights may have changed during visible row measurement.
	update_content_size()
	_update_dragger_position()
	_update_borders_overlay_size()
	borders_overlay.queue_redraw()
	_scroll_guard = false



func _on_data_scroll_changed(value: float):
	_on_scroll(value)


func _on_data_hscroll_changed(value: float):
	if is_instance_valid(data_header_hbox):
		data_header_hbox.position.x = -value
	_update_dragger_position()
	borders_overlay.queue_redraw()

func _on_vbar_resized():
	header_container.queue_sort()

func _position_visible_rows():
	var needed = last_visible_idx - first_visible_idx + 1
	_ensure_data_pool_size(needed)
	if show_frame:
		_ensure_frame_pool_size(needed)

	# Stabilize adaptive row heights with bounded loop.
	# 只在行数据发生变化时才调用 _assign_data_row_data 重新创建控件，
	# 避免每轮循环都重建控件触发 minimum_size_changed 信号级联。
	var max_iter = 10
	while max_iter > 0:
		max_iter -= 1
		var height_changed = false
		for i in range(needed):
			var data_idx = first_visible_idx + i

			# Data row
			var data_row = data_row_pool[i]
			if data_row.get_meta("data_index", -1) != data_idx:
				_assign_data_row_data(data_row, data_idx)
			_apply_data_row_widths(data_row)
			if row_height_mode == RowHeightMode.ADAPTIVE and not custom_row_heights.has(data_idx):
				height_changed = _set_row_height_cache(data_idx, _measure_data_row_height(data_row)) or height_changed

			# Frame row
			if show_frame:
				var frame_row = frame_row_pool[i]
				_assign_frame_row_data(frame_row, data_idx)

		if not height_changed:
			break

		update_content_size()
		var adjusted_range = _get_visible_row_range(data_scroll.scroll_vertical, data_scroll.size.y)
		if adjusted_range.x == first_visible_idx and adjusted_range.y == last_visible_idx:
			break

		first_visible_idx = adjusted_range.x
		last_visible_idx = adjusted_range.y
		needed = last_visible_idx - first_visible_idx + 1
		_ensure_data_pool_size(needed)
		if show_frame:
			_ensure_frame_pool_size(needed)

	# 定位所有可见行
	for i in range(needed):
		var data_idx = first_visible_idx + i
		var row_top = _get_row_top(data_idx)
		var row_h = _get_row_height(data_idx)

		var data_row = data_row_pool[i]
		data_row.visible = true
		data_pool_in_use[i] = true
		data_row.position = Vector2(0, row_top)
		data_row.size = Vector2(data_row_container.size.x, row_h)
		_apply_row_height_to_row(data_row, row_h)

		if show_frame:
			var frame_row = frame_row_pool[i]
			frame_row.visible = true
			frame_pool_in_use[i] = true
			frame_row.position = Vector2(0, row_top)
			frame_row.size = Vector2(frame_col_width, row_h)
			frame_row.custom_minimum_size.y = row_h
			var btn = frame_row.get_child(0) if frame_row.get_child_count() > 0 else null
			if btn is Button:
				(btn as Button).custom_minimum_size.y = row_h
				(btn as Button).size.y = row_h
			frame_row.queue_sort()

	for i in range(needed, data_row_pool.size()):
		data_row_pool[i].visible = false
		data_pool_in_use[i] = false

	if show_frame:
		for i in range(needed, frame_row_pool.size()):
			frame_row_pool[i].visible = false
			frame_pool_in_use[i] = false


func _dump_row_debug():
	pass

func _dump_border_debug():
	print("=== BORDER DEBUG (using _get_col_x) ====")
	print("overlay gpos=", borders_overlay.global_position, " size=", borders_overlay.size)
	print("scroll gpos=", data_scroll.global_position)
	print("scroll_val=", data_scroll.scroll_vertical)
	print("row_heights=", row_heights)
	for bi in selected_borders.size():
		var b = selected_borders[bi]
		var rect = b["rect"] as Rect2
		print("border[", bi, "] start=", b["start"], " rect=", rect)
		for r in range(int(rect.position.x), int(rect.end.x)):
			var y0 = _get_row_top(r) - data_scroll.scroll_vertical
			var row_h = _get_row_height(r)
			if y0 + row_h < 0 or y0 > data_scroll.size.y:
				continue
			for c in range(int(rect.position.y), int(rect.end.y)):
				var x0 = _get_col_x(c)
				var cell_global = borders_overlay.global_position + Vector2(x0, y0)
				print("  cell[", r, ",", c, "] local=", Vector2(x0, y0), " global=", cell_global, " w=", col_widths[c], " h=", row_h)
	print("=== END BORDER DEBUG ====")

func _hide_all_frame_pool_rows():
	for i in range(frame_row_pool.size()):
		frame_row_pool[i].visible = false
		frame_pool_in_use[i] = false

func _hide_all_data_pool_rows():
	for i in range(data_row_pool.size()):
		data_row_pool[i].visible = false
		data_pool_in_use[i] = false

func _ensure_data_pool_size(needed: int):
	var target = min(MAX_POOL_SIZE, max(needed, 10))
	while data_row_pool.size() < target:
		var row = _create_data_row_node()
		data_row_pool.append(row)
		data_pool_in_use.append(true)
		row.visible = false
		data_row_container.add_child(row)

func _ensure_frame_pool_size(needed: int):
	var target = min(MAX_POOL_SIZE, max(needed, 10))
	while frame_row_pool.size() < target:
		var row = _create_frame_row_node()
		frame_row_pool.append(row)
		frame_pool_in_use.append(true)
		row.visible = false
		frame_row_container.add_child(row)

func _create_data_row_node() -> Control:
	var row = PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if row_expend_and_fill:
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = row_height
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_stylebox_override("panel", style_box_empty)

	# Build cell containers for data columns only (no frame column)
	var hbox = HBoxContainer.new()
	hbox.name = "DataRowHBox"
	hbox.add_theme_constant_override("separation", 0)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.clip_contents = true
	hbox.custom_minimum_size.y = row_height
	row.add_child(hbox)

	for i in range(columns.size()):
		var cell = PanelContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.clip_contents = true
		cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		cell.add_theme_stylebox_override("panel", style_box_empty)
		_apply_cell_width(cell, col_widths[i] if i < col_widths.size() else float(MIN_COL_WIDTH))
		hbox.add_child(cell)
	return row

func _create_frame_row_node() -> Control:
	var row = PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.custom_minimum_size.y = row_height
	row.add_theme_stylebox_override("panel", style_box_empty)
	var btn = Button.new()
	btn.flat = false
	btn.mouse_default_cursor_shape = Control.CURSOR_HELP
	btn.add_theme_font_size_override("font_size", 12)
	var arrow_right = load("res://addons/gdsql/img/arrow_right.svg")
	if arrow_right:
		btn.mouse_entered.connect(DisplayServer.cursor_set_custom_image.bind(arrow_right, DisplayServer.CURSOR_HELP, Vector2(12, 12)))
	btn.pressed.connect(_on_frame_btn_pressed_from_button.bind(btn))
	btn.gui_input.connect(_on_frame_btn_gui_input_from_button.bind(btn))
	row.add_child(btn)
	return row

func _assign_data_row_data(row_node: Control, data_idx: int):
	var hbox = row_node.get_child(0) if row_node.get_child_count() > 0 else null
	if hbox == null:
		return

	var data = datas_flat[data_idx]
	if data == null:
		return

	row_node.set_meta("data_index", data_idx)
	row_node.set_meta("data", data)

	var data_arr = _data_to_array(data)
	var data_col = 0
	for cell in hbox.get_children():
		if not (cell is PanelContainer):
			continue
		if data_col >= data_arr.size() or data_col >= col_widths.size():
			data_col += 1
			continue

		var content_wrapper = _get_cell_content_wrapper(cell as PanelContainer)

		# Clear existing cell content without letting the content minimum size affect the column width.
		for c in content_wrapper.get_children():
			content_wrapper.remove_child(c)
			if not c.get_meta("_gdsql_external_cell_control", false):
				c.queue_free()

		var value = data_arr[data_col]
		var ctl = _create_cell_control(value, data, data_col)
		if ctl:
			_add_control_to_cell(content_wrapper, ctl, data_idx, data_col)

		# Assign cell meta for border lookup
		(cell as PanelContainer).set_meta("row", data_idx)
		(cell as PanelContainer).set_meta("col", data_col)
		data_col += 1

func _get_cell_content_wrapper(cell: PanelContainer) -> Control:
	for child in cell.get_children():
		if child is Control and child.get_meta("_gdsql_cell_content_wrapper", false):
			return child as Control

	var wrapper = Control.new()
	wrapper.name = "CellContentWrapper"
	wrapper.clip_contents = true
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.set_meta("_gdsql_cell_content_wrapper", true)
	wrapper.resized.connect(_on_cell_content_wrapper_resized.bind(wrapper))
	cell.add_child(wrapper)
	return wrapper

func _apply_cell_width(cell: PanelContainer, width: float):
	cell.custom_minimum_size.x = width
	var wrapper = _get_cell_content_wrapper(cell)
	wrapper.custom_minimum_size.x = width
	wrapper.size.x = width
	for child in wrapper.get_children():
		if child is Control:
			_fit_control_to_cell(child as Control, wrapper)

func _add_control_to_cell(wrapper: Control, control: Control, row_idx: int, col_idx: int):
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if control.get_parent() == null:
		wrapper.add_child(control)
	else:
		control.reparent(wrapper)
	control.set_meta("_gdsql_table_row", row_idx)
	control.set_meta("_gdsql_table_col", col_idx)
	_connect_row_height_control_signals(control)
	_fit_control_to_cell(control, wrapper)
	var min_size = control.get_combined_minimum_size()
	wrapper.custom_minimum_size = Vector2(
		col_widths[col_idx] if col_idx < col_widths.size() else float(MIN_COL_WIDTH),
		max(float(row_height), min_size.y) if row_height_mode == RowHeightMode.ADAPTIVE else float(row_height)
	)

func _connect_row_height_control_signals(control: Control):
	var old_callable = control.get_meta("_gdsql_size_changed_callable", Callable())
	if old_callable is Callable and old_callable.is_valid():
		if control.minimum_size_changed.is_connected(old_callable):
			control.minimum_size_changed.disconnect(old_callable)
	var cb = _on_cell_control_size_changed.bind(control)
	control.set_meta("_gdsql_size_changed_callable", cb)
	control.minimum_size_changed.connect(cb)

func _on_cell_control_size_changed(control: Control):
	if row_height_mode != RowHeightMode.ADAPTIVE or not is_instance_valid(control):
		return
	# 在滚动/布局过程中忽略 minimum_size_changed 信号，
	# 因为 _position_visible_rows 已经在测量和设置正确的行高。
	if _scroll_guard:
		return
	var row_idx = int(control.get_meta("_gdsql_table_row", -1))
	if row_idx >= 0:
		invalidate_row_height(row_idx)

func _fit_control_to_cell(control: Control, wrapper: Control):
	control.anchor_left = ANCHOR_BEGIN
	control.anchor_top = ANCHOR_BEGIN
	control.anchor_right = ANCHOR_END
	control.anchor_bottom = ANCHOR_END
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0

func _on_cell_content_wrapper_resized(wrapper: Control):
	if not is_instance_valid(wrapper):
		return
	for child in wrapper.get_children():
		if child is Control:
			_fit_control_to_cell(child as Control, wrapper)

func _assign_frame_row_data(row_node: Control, data_idx: int):
	var btn = row_node.get_child(0) if row_node.get_child_count() > 0 else null
	if not (btn is Button):
		return
	btn.text = str(data_idx + 1)
	btn.set_meta("data_index", data_idx)


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
				control.set_meta("_gdsql_external_cell_control", true)
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
		if a_data is GDSQL.DictionaryObject:
			_bind_update_callback(a_data, col_idx, control)

	# Set mouse filter so events pass through to data_row_container for selection
	if control:
		if control is Button:
			control.mouse_filter = Control.MOUSE_FILTER_PASS
		elif not (value is Control):
			control.mouse_filter = Control.MOUSE_FILTER_PASS

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
				if new_value is Resource or new_value is Control:
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
		new_ctl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		old.replace_by(new_ctl)
		if parent is Control:
			_fit_control_to_cell(new_ctl, parent as Control)
		old.queue_free()

# ── Row operations ────────────────────────────────────────────────────────

func append_data(a_data):
	datas.append(a_data)
	datas_flat.append(a_data)
	if columns.is_empty() and a_data is Dictionary:
		for key in a_data:
			columns.append(key)
		rebuild_header()
	_ensure_row_height_arrays()
	invalidate_row_height(datas_flat.size() - 1)
	update_content_size()
	# If the new row is near the viewport, refresh
	if datas_flat.size() - 1 <= last_visible_idx + BUFFER_ROWS:
		_on_scroll(data_scroll.scroll_vertical)

func insert_data(pos: int, a_data):
	clear_borders()
	datas.insert(pos, a_data)
	datas_flat.insert(pos, a_data)
	custom_row_heights = _shift_custom_row_heights(pos, 1)
	_reset_adaptive_row_height_cache()
	if columns.is_empty() and a_data is Dictionary:
		for key in a_data:
			columns.append(key)
		rebuild_header()
	_ensure_row_height_arrays()
	invalidate_row_height(pos)
	update_content_size()
	_on_scroll(data_scroll.scroll_vertical)

func remove_data_at(index: int, free_data: bool):
	clear_borders()
	if index < 0 or index >= datas_flat.size():
		return
	if free_data and datas_flat[index] is GDSQL.DictionaryObject:
		datas_flat[index].free_all_custom_display_controls()
	datas.remove_at(index)
	datas_flat.remove_at(index)
	custom_row_heights.erase(index)
	custom_row_heights = _shift_custom_row_heights(index + 1, -1)
	_reset_adaptive_row_height_cache()
	update_content_size()
	_on_scroll(data_scroll.scroll_vertical)

func move_data(from: int, to: int):
	if from == to:
		return
	clear_borders()
	var data = datas_flat[from]
	datas.remove_at(from)
	datas.insert(to, data)
	datas_flat.remove_at(from)
	datas_flat.insert(to, data)
	_move_custom_row_height(from, to)
	_reset_adaptive_row_height_cache()
	update_content_size()
	_on_scroll(data_scroll.scroll_vertical)

func clear_all():
	clear_borders()
	datas_flat.clear()
	row_heights.clear()
	row_offsets = [0.0]
	first_visible_idx = 0
	last_visible_idx = -1
	row_height_dirty.clear()
	custom_row_heights.clear()
	_row_offsets_dirty = true
	for i in range(data_row_pool.size()):
		data_row_pool[i].set_meta("data_index", -1)
		data_row_pool[i].visible = false
		data_pool_in_use[i] = false

func _get_row_node(data_idx: int):
	for i in range(data_row_pool.size()):
		if data_pool_in_use[i] and data_row_pool[i].visible:
			if data_row_pool[i].get_meta("data_index", -1) == data_idx:
				return data_row_pool[i]
	return null

# ── Borders overlay ─────────────────────────────────────────────────────

func _draw_grid():
	if datas_flat.is_empty() or col_widths.is_empty():
		return
	if not is_instance_valid(borders_overlay) or not is_instance_valid(data_scroll):
		return

	var view_h = data_scroll.size.y
	var scroll_val = data_scroll.scroll_vertical
	var scroll_h = data_scroll.scroll_horizontal

	var visible_range = _get_visible_row_range(scroll_val, view_h)
	var first_r = visible_range.x
	var last_r = visible_range.y
	if last_r < first_r:
		return

	# Data column indices in col_widths
	var first_dc = 0
	var last_dc = col_widths.size() - 1
	if last_dc < first_dc:
		return

	var left_x = _get_col_x(first_dc) - scroll_h
	var right_x = (_get_col_x(last_dc) + col_widths[last_dc]) - scroll_h

	# Y range clamped to viewport
	var y0 = _get_row_top(first_r) - scroll_val
	var y1 = _get_row_bottom(last_r) - scroll_val
	if y0 < 0.0:
		y0 = 0.0
	if y1 > view_h:
		y1 = view_h

	# Horizontal grid lines — at bottom of each visible row
	for r in range(first_r, last_r + 1):
		var y = _get_row_bottom(r) - scroll_val
		if y < y0 or y > y1:
			continue
		borders_overlay.draw_line(Vector2(left_x, y), Vector2(right_x, y), GRID_COLOR, 1.0)

	# Vertical grid lines — left of first data column and right of each data column
	var x_first = _get_col_x(first_dc) - scroll_h
	borders_overlay.draw_line(Vector2(x_first, y0), Vector2(x_first, y1), GRID_COLOR, 1.0)
	for ci in range(first_dc, last_dc + 1):
		var x = (_get_col_x(ci) + col_widths[ci]) - scroll_h
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

	var view_h = data_scroll.size.y
	var scroll_val = data_scroll.scroll_vertical
	var multi = selected_borders.size() > 1
	var scroll_h = data_scroll.scroll_horizontal

	for border in selected_borders:
		var rect = border["rect"] as Rect2
		var start_r = int(rect.position.x)
		var end_r = int(rect.end.x)
		var start_c = int(rect.position.y)
		var end_c = int(rect.end.y)

		for r in range(start_r, end_r):
			var y0 = _get_row_top(r) - scroll_val
			var row_h = _get_row_height(r)
			if y0 + row_h < 0 or y0 > view_h:
				continue

			for c in range(start_c, end_c):
				var ci = c
				if ci < 0 or ci >= col_widths.size():
					continue
				var x0 = _get_col_x(ci) - scroll_h
				var bw = col_widths[ci]
				# Only last border's start cell has no background (draw_center=false)
				var is_start = r == last_selected_pos.x and c == last_selected_pos.y
				if not is_start:
					var alpha = DEFAULT_BORDER_BG.a * _get_overlap_count(r, c) * 1.05
					var bg = Color(DEFAULT_BORDER_BG.r, DEFAULT_BORDER_BG.g, DEFAULT_BORDER_BG.b, alpha)
					borders_overlay.draw_rect(Rect2(x0, y0, bw, row_h), bg)

		# Draw continuous outer boundary (4 lines)
		var sl = _get_col_x(start_c) - scroll_h
		var last_ci = end_c - 1
		var sr = (_get_col_x(last_ci) + col_widths[last_ci]) - scroll_h if last_ci >= 0 else sl
		var st = _get_row_top(start_r) - scroll_val
		var sb = _get_row_top(end_r) - scroll_val
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
			var ey = _get_row_top(er) - scroll_val
			var row_h = _get_row_height(er)
			if ey + row_h < 0 or ey > view_h:
				continue
			for ec in range(int(ex_rect.position.y), int(ex_rect.end.y)):
				var eci = ec
				if eci < 0 or eci >= col_widths.size():
					continue
				var ex0 = _get_col_x(eci) - scroll_h
				var ew = col_widths[eci]
				borders_overlay.draw_rect(Rect2(ex0, ey, ew, row_h), Color(Color.DARK_BLUE, 0.25))

	# Autofill dashed border
	if autofill_info.has("rect"):
		var af_rect = autofill_info["rect"] as Rect2
	
		var af_start = af_rect.position
		var af_end = af_rect.end
		for r in range(int(af_start.x), int(af_end.x)):
			for c in range(int(af_start.y), int(af_end.y)):
				if r == int(af_start.x) or c == int(af_start.y) or r == int(af_end.x) - 1 or c == int(af_end.y) - 1:
					var ci = c
					if ci >= col_widths.size():
						continue
					var cx = _get_col_x(ci) - scroll_h
					var cy = _get_row_top(r) - scroll_val
					_draw_dashed_rect(Rect2(cx, cy, col_widths[ci], _get_row_height(r)),
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
	var x = _get_col_x(data_col)
	var y = _get_row_top(data_row) - data_scroll.scroll_vertical
	return Rect2(x, y, col_widths[data_col], _get_row_height(data_row))

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

func borders_has_same_cols() -> bool:
	if selected_borders.is_empty():
		return false
	var start_c = (selected_borders.front()["rect"] as Rect2).position.y
	var end_c = (selected_borders.front()["rect"] as Rect2).end.y
	for b in selected_borders:
		var r = b["rect"] as Rect2
		if r.position.y != start_c or r.end.y != end_c:
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

	var ci = last_col
	if ci < 0 or ci >= col_widths.size():
		return
	var cx = _get_col_x(ci) + col_widths[ci] - data_scroll.scroll_horizontal
	var cy = _get_row_bottom(last_row) - data_scroll.scroll_vertical
	cornor_dragger = load("res://addons/gdsql/table/cornor_dragger.tscn").instantiate()
	borders_overlay.add_child(cornor_dragger)
	cornor_dragger.position = Vector2(cx, cy) - Vector2(5, 5)
	cornor_dragger.cornor_drag_start.connect(_on_corner_drag_start)
	cornor_dragger.cornor_drag_moving.connect(_on_corner_drag_moving.bind(rect.position, rect.end))
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
	var ci = last_col
	if ci < 0 or ci >= col_widths.size():
		return
	var cx = _get_col_x(ci) + col_widths[ci] - data_scroll.scroll_horizontal
	var cy = _get_row_bottom(last_row) - data_scroll.scroll_vertical
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

func _on_corner_drag_moving(diff: Vector2, start: Vector2, end: Vector2):
	# 获取鼠标在 data_scroll 局部坐标系中的位置（用于自动滚动判断）
	var mouse_gpos = get_global_mouse_position()
	var ds_local = mouse_gpos - data_scroll.global_position
	var ds_rect = Rect2(Vector2.ZERO, data_scroll.size)

	# 自动滚动：仿照 table.gd 的 scroll_container.ensure_control_visible(panel_container)
	# 超出 scroll_container 的边界时，要让 scroll_container 自己滚动
	if ds_local.x > ds_rect.size.x:
		data_scroll.scroll_horizontal += int((ds_local.x - ds_rect.size.x) * 0.3)
	elif ds_local.x < 0:
		data_scroll.scroll_horizontal += int(ds_local.x * 0.3)
	if ds_local.y > ds_rect.size.y:
		data_scroll.scroll_vertical += int((ds_local.y - ds_rect.size.y) * 0.3)
	elif ds_local.y < 0:
		data_scroll.scroll_vertical += int(ds_local.y * 0.3)

	# 计算数据坐标下的鼠标位置（加上滚动偏移）
	var local_mouse = mouse_gpos - borders_overlay.global_position
	local_mouse.x += data_scroll.scroll_horizontal
	local_mouse.y += data_scroll.scroll_vertical

	# 获取单元格位置（仿照 table.gd 的 get_panel_container_under_mouse + get_index）
	if datas_flat.is_empty():
		return
	var pos_row = _get_row_at_content_y(local_mouse.y)
	var pos_col = -1
	var x = 0.0
	for c in range(col_widths.size()):
		if local_mouse.x < x + col_widths[c]:
			pos_col = c
			break
		x += col_widths[c]

	# 钳制到有效范围（table.gd 通过节点树 get_index 天然就是有效范围）
	pos_row = clampi(pos_row, 0, datas_flat.size() - 1)
	pos_col = clampi(pos_col, 0, col_widths.size() - 1)

	# 如果panel_container在上下左右外侧（非内侧、非斜外侧），则稳定多出一块。否则再使用下方的逻辑。
	if pos_col >= start.y and pos_col <= end.y - 1:
		# 向上多出一块
		if pos_row < start.x:
			add_autofill_border(Vector2(pos_row, start.y), end, "add")
			return
		# 向下多出一块
		if pos_row > end.x - 1:
			add_autofill_border(start, Vector2(pos_row + 1, end.y), "add")
			return
	if pos_row >= start.x and pos_row <= end.x - 1:
		# 向左多出一块
		if pos_col < start.y:
			add_autofill_border(Vector2(start.x, pos_col), end, "add")
			return
		# 向右多出一块
		if pos_col > end.y - 1:
			add_autofill_border(start, Vector2(end.x, pos_col + 1), "add")
			return

	# 内侧或斜外侧
	if diff.x > 0:
		if diff.y > 0:
			if diff.x > diff.y:
				# 向右多出一块
				# #####¯¯¯⌉
				# #####   |
				# #####___⌋
				add_autofill_border(start, Vector2(end.x, pos_col + 1), "add")
			else:
				# 向下多出一块
				# #########
				# #########
				# |       |
				# ⌊_______⌋
				add_autofill_border(start, Vector2(pos_row + 1, end.y), "add")
		else:
			if diff.x > -diff.y:
				# 向右多出一块
				# #####¯¯¯⌉
				# #####   |
				# #####___⌋
				add_autofill_border(start, Vector2(end.x, pos_col + 1), "add")
			else:
				# 向上缩小一块
				if pos_row > start.x:
					var cell_top = _get_row_top(pos_row)
					var half_h = _get_row_height(pos_row) * 0.5
					if local_mouse.y < cell_top + half_h:
						add_autofill_border(start, Vector2(pos_row, end.y),
							"sub" if pos_row != end.x - 1 else "start")
					else:
						add_autofill_border(start, Vector2(pos_row + 1, end.y),
							"sub" if pos_row + 1 != end.x else "start")
				# 全部缩
				elif pos_row == start.x:
					var cell_top = _get_row_top(pos_row)
					var half_h = _get_row_height(pos_row) * 0.5
					if local_mouse.y < cell_top + half_h:
						add_autofill_border(start, end, "sub")
					else:
						add_autofill_border(start, Vector2(pos_row + 1, end.y),
							"sub" if pos_row + 1 != end.x else "start")
				# 向上扩展
				else:
					add_autofill_border(Vector2(pos_row, start.y), end, "add")
	else:
		if diff.y > 0:
			if -diff.x > diff.y:
				# 向左缩一块
				if pos_col > start.y:
					var cell_x = _get_col_x(pos_col)
					var half_w = col_widths[pos_col] * 0.5
					if local_mouse.x < cell_x + half_w:
						add_autofill_border(start, Vector2(end.x, pos_col),
							"sub" if pos_col != end.y - 1 else "start")
					else:
						add_autofill_border(start, Vector2(end.x, pos_col + 1),
							"sub" if pos_col + 1 != end.y else "start")
				# 全部缩
				elif pos_col == start.y:
					var cell_x = _get_col_x(pos_col)
					var half_w = col_widths[pos_col] * 0.5
					if local_mouse.x < cell_x + half_w:
						add_autofill_border(start, end, "sub")
					else:
						add_autofill_border(start, Vector2(end.x, pos_col + 1),
							"sub" if pos_col + 1 != end.y else "start")
				# 向左扩展
				else:
					add_autofill_border(Vector2(start.x, pos_col), end, "add")
			else:
				# 向下多出一块
				# #########
				# #########
				# |       |
				# ⌊_______⌋
				add_autofill_border(start, Vector2(pos_row + 1, end.y), "add")
		else:
			if -diff.x > -diff.y:
				# 向左缩一块
				if pos_col > start.y:
					var cell_x = _get_col_x(pos_col)
					var half_w = col_widths[pos_col] * 0.5
					if local_mouse.x < cell_x + half_w:
						add_autofill_border(start, Vector2(end.x, pos_col),
							"sub" if pos_col != end.y - 1 else "start")
					else:
						add_autofill_border(start, Vector2(end.x, pos_col + 1),
							"sub" if pos_col + 1 != end.y else "start")
				# 全部缩
				elif pos_col == start.y:
					var cell_x = _get_col_x(pos_col)
					var half_w = col_widths[pos_col] * 0.5
					if local_mouse.x < cell_x + half_w:
						add_autofill_border(start, end, "sub")
					else:
						add_autofill_border(start, Vector2(end.x, pos_col + 1),
							"sub" if pos_col + 1 != end.y else "start")
				# 向左扩展
				else:
					add_autofill_border(Vector2(start.x, pos_col), end, "add")
			else:
				# 向上缩小一块
				if pos_row > start.x:
					var cell_top = _get_row_top(pos_row)
					var half_h = _get_row_height(pos_row) * 0.5
					if local_mouse.y < cell_top + half_h:
						add_autofill_border(start, Vector2(pos_row, end.y),
							"sub" if pos_row != end.x - 1 else "start")
					else:
						add_autofill_border(start, Vector2(pos_row + 1, end.y),
							"sub" if pos_row + 1 != end.x else "start")
				# 全部缩
				elif pos_row == start.x:
					var cell_top = _get_row_top(pos_row)
					var half_h = _get_row_height(pos_row) * 0.5
					if local_mouse.y < cell_top + half_h:
						add_autofill_border(start, end, "sub")
					else:
						add_autofill_border(start, Vector2(pos_row + 1, end.y),
							"sub" if pos_row + 1 != end.x else "start")
				# 向上扩展
				else:
					add_autofill_border(Vector2(pos_row, start.y), end, "add")

func add_autofill_border(start_pos: Vector2, end_pos: Vector2, mode: String):
	# 清旧的
	autofill_info["rect"] = Rect2(start_pos, end_pos - start_pos)
	autofill_info["mode"] = mode

	if mode == "start":
		autofill_info.erase("rect")
		borders_overlay.queue_redraw()
		return

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

	#var af_start = af_rect.position
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

	# mode == "start"：用户缩回原始选区，不执行任何填充
	if autofill_info.get("mode", "") == "start":
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

	# Upward fill: extend rows upward (reverse data source)
	if af_rect.position.x < src_sel.position.x:
		var fill_start = int(af_rect.position.x)
		var fill_end = int(src_sel.position.x)
		for col in range(int(src_sel.position.y), int(src_sel.end.y)):
			var xdata = []
			var ydata = []
			for r in range(int(src_sel.end.x) - 1, int(src_sel.position.x) - 1, -1):
				var d = datas_flat[r]
				if d is GDSQL.DictionaryObject:
					xdata.push_back(r)
					ydata.append(d._get_by_index(col))
			if xdata.is_empty():
				continue
			var ls = GDSQL.LeastSquares.new(xdata, ydata)
			for row in range(fill_start, fill_end):
				if row >= 0 and row < datas_flat.size():
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

	# Leftward fill: extend columns leftward (reverse data source)
	if af_rect.position.y < src_sel.position.y:
		var fill_start = int(af_rect.position.y)
		var fill_end = int(src_sel.position.y)
		for row in range(int(src_sel.position.x), int(src_sel.end.x)):
			var d = datas_flat[row]
			if not (d is GDSQL.DictionaryObject):
				continue
			var xdata = []
			var ydata = []
			for c in range(int(src_sel.end.y) - 1, int(src_sel.position.y) - 1, -1):
				xdata.push_back(c)
				ydata.append(d._get_by_index(c))
			if xdata.is_empty():
				continue
			var ls = GDSQL.LeastSquares.new(xdata, ydata)
			for col in range(fill_start, fill_end):
				if col >= 0 and row < datas_flat.size():
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
	if datas_flat.is_empty():
		return Vector2i(-1, -1)
	var row = _get_row_at_content_y(pos.y)
	if row < 0 or row >= datas_flat.size():
		return Vector2i(-1, -1)

	var x = 0.0
	for c in range(col_widths.size()):
		var w = col_widths[c]
		if pos.x >= x and pos.x < x + w:
			var data_col = c
			if data_col < 0 or data_col >= columns.size():
				return Vector2i(-1, -1)
			return Vector2i(row, data_col)
		x += w
	return Vector2i(-1, -1)

func _on_data_row_container_gui_input(event: InputEvent):
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
				elif mb.double_click and editable:
					_on_button_edit_button_down()
				else:
					_handle_normal_click(cell_pos)

			if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
				if cell_pos.x < datas_flat.size():
					row_clicked.emit(cell_pos.x, mb.button_index, datas_flat[cell_pos.x])
				if mb.button_index == MOUSE_BUTTON_RIGHT:
					if not pos_is_selected(cell_pos):
						_handle_normal_click(cell_pos)
					popup_menu_text.set_item_metadata(popup_menu_text.get_item_index(MENU_ID.COPY_FIELD), [cell_pos.y, cell_pos.x])
					popup_menu_text.set_item_metadata(popup_menu_text.get_item_index(MENU_ID.COPY_LINE), [cell_pos.y, cell_pos.x])
					popup_menu_text.set_item_metadata(popup_menu_text.get_item_index(MENU_ID.DELETE), [cell_pos.y, cell_pos.x])
					if show_menu:
						popup_menu_text.position = DisplayServer.mouse_get_position()
						if not popup_menu_text.visible:
							popup_menu_text.popup()
							popup_menu_text.set_item_disabled(popup_menu_text.get_item_index(MENU_ID.DELETE), not support_delete_row or not editable)
					else:
						popup_menu_text.set_item_disabled(popup_menu_text.get_item_index(MENU_ID.DELETE), true)
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
			# Auto-scroll when dragging beyond viewport
			var mouse_gpos = get_global_mouse_position()
			var ds_local = mouse_gpos - data_scroll.global_position
			var ds_rect = Rect2(Vector2.ZERO, data_scroll.size)
			if ds_local.x > ds_rect.size.x:
				data_scroll.scroll_horizontal += int((ds_local.x - ds_rect.size.x) * 0.3)
			elif ds_local.x < 0:
				data_scroll.scroll_horizontal += int(ds_local.x * 0.3)
			if ds_local.y > ds_rect.size.y:
				data_scroll.scroll_vertical += int((ds_local.y - ds_rect.size.y) * 0.3)
			elif ds_local.y < 0:
				data_scroll.scroll_vertical += int(ds_local.y * 0.3)

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

		elif event is InputEventKey and not selected_borders.is_empty():
			var ke = event as InputEventKey
			if ke.pressed and not ke.echo and editable:
				if ke.keycode == KEY_ENTER or ke.keycode == KEY_SPACE or ke.keycode == KEY_KP_ENTER:
					_on_button_edit_button_down()

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

func _on_frame_btn_pressed_from_button(btn: Button):
	_on_frame_btn_pressed(int(btn.get_meta("data_index", -1)), btn)

func _on_frame_btn_gui_input_from_button(event: InputEvent, btn: Button):
	_on_frame_btn_gui_input(event, int(btn.get_meta("data_index", -1)))

func _on_frame_btn_pressed(data_idx: int, _btn: Button):
	if data_idx < 0 or data_idx >= datas_flat.size():
		return
	if _frame_did_drag:
		_frame_did_drag = false
		return
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
		# 确保表格内任一节点获得焦点，这样 shortcut 才能生效
		data_row_container.grab_focus()

func _on_frame_btn_gui_input(event: InputEvent, data_idx: int):
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_frame_did_drag = false
				_frame_drag_start_row = data_idx
				_frame_drag_active = true
				_frame_drag_ctrl = Input.is_key_pressed(KEY_CTRL)
			else:
				_frame_drag_active = false
				_frame_drag_start_row = -1
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_row_height_menu_row = data_idx
			_refresh_frame_popup_state()
			frame_popup_menu.position = DisplayServer.mouse_get_position()
			frame_popup_menu.popup()
			accept_event()
	elif event is InputEventMouseMotion and _frame_drag_active:
		var mm = event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var mouse_gpos = get_global_mouse_position()
			var ds_local = mouse_gpos - data_scroll.global_position
			var ds_rect = Rect2(Vector2.ZERO, data_scroll.size)
			if ds_local.x > ds_rect.size.x:
				data_scroll.scroll_horizontal += int((ds_local.x - ds_rect.size.x) * 0.3)
			elif ds_local.x < 0:
				data_scroll.scroll_horizontal += int(ds_local.x * 0.3)
			if ds_local.y > ds_rect.size.y:
				data_scroll.scroll_vertical += int((ds_local.y - ds_rect.size.y) * 0.3)
			elif ds_local.y < 0:
				data_scroll.scroll_vertical += int(ds_local.y * 0.3)
			var local_y = mouse_gpos.y - frame_row_container.global_position.y
			var cur_row = _get_row_at_content_y(local_y)
			if cur_row >= 0 and cur_row != _frame_drag_start_row:
				_frame_did_drag = true
				var start_r = mini(_frame_drag_start_row, cur_row)
				var end_r = maxi(_frame_drag_start_row, cur_row) + 1
				if _frame_drag_ctrl:
					var rect = Rect2(start_r, 0, end_r - start_r, columns.size())
					var border = {"start": Vector2i(_frame_drag_start_row, 0), "rect": rect, "ctrl": true}
					add_border(border)
				else:
					var rect = Rect2(start_r, 0, end_r - start_r, columns.size())
					var border = {"start": Vector2i(_frame_drag_start_row, 0), "rect": rect}
					add_border(border)

func _refresh_frame_popup_state():
	if not is_instance_valid(row_height_mode_popup) or not is_instance_valid(custom_row_height_popup):
		return
	row_height_mode_popup.set_item_checked(row_height_mode_popup.get_item_index(FRAME_MENU_ID.MODE_FIXED), row_height_mode == RowHeightMode.FIXED)
	row_height_mode_popup.set_item_checked(row_height_mode_popup.get_item_index(FRAME_MENU_ID.MODE_ADAPTIVE), row_height_mode == RowHeightMode.ADAPTIVE)
	var has_selected_rows = not _get_selected_rows().is_empty()
	custom_row_height_popup.set_item_disabled(custom_row_height_popup.get_item_index(FRAME_MENU_ID.CUSTOM_SELECTED), not has_selected_rows)
	custom_row_height_popup.set_item_disabled(custom_row_height_popup.get_item_index(FRAME_MENU_ID.RESET_SELECTED), not has_selected_rows)
	custom_row_height_popup.set_item_disabled(custom_row_height_popup.get_item_index(FRAME_MENU_ID.CUSTOM_CURRENT), _row_height_menu_row < 0)
	custom_row_height_popup.set_item_disabled(custom_row_height_popup.get_item_index(FRAME_MENU_ID.RESET_CURRENT), _row_height_menu_row < 0)
	custom_row_height_popup.set_item_disabled(custom_row_height_popup.get_item_index(FRAME_MENU_ID.RESET_ALL), custom_row_heights.is_empty() and row_height == _default_row_height)

func _on_frame_popup_id_pressed(id: int):
	match id:
		FRAME_MENU_ID.MODE_FIXED:
			row_height_mode = RowHeightMode.FIXED
		FRAME_MENU_ID.MODE_ADAPTIVE:
			row_height_mode = RowHeightMode.ADAPTIVE
		FRAME_MENU_ID.CUSTOM_ALL:
			_open_row_height_dialog("all", _row_height_menu_row)
		FRAME_MENU_ID.CUSTOM_SELECTED:
			_open_row_height_dialog("selected", _row_height_menu_row)
		FRAME_MENU_ID.CUSTOM_CURRENT:
			_open_row_height_dialog("current", _row_height_menu_row)
		FRAME_MENU_ID.RESET_SELECTED:
			_clear_custom_row_heights(_get_selected_rows())
		FRAME_MENU_ID.RESET_CURRENT:
			_clear_custom_row_heights([_row_height_menu_row])
		FRAME_MENU_ID.RESET_ALL:
			custom_row_heights.clear()
			row_height = _default_row_height
			invalidate_all_row_heights()

func _open_row_height_dialog(scope: String, row: int):
	_row_height_edit_scope = scope
	_row_height_edit_row = row
	var value = float(row_height)
	match scope:
		"current":
			if row >= 0 and row < datas_flat.size():
				value = _get_row_height(row)
		"selected":
			var rows = _get_selected_rows()
			if not rows.is_empty():
				value = _get_row_height(rows.front())
		"all":
			value = float(row_height)
	row_height_spin_box.value = value
	row_height_dialog.popup_centered(Vector2i(220, 90))
	# 将光标移到输入框末尾
	var le = row_height_spin_box.get_line_edit()
	if le:
		le.call_deferred("grab_focus")
		le.select_all_on_focus = true

func _on_row_height_dialog_confirmed():
	var value = maxi(1, int(row_height_spin_box.value))
	match _row_height_edit_scope:
		"all":
			row_height = value
		"selected":
			_apply_custom_row_heights(_get_selected_rows(), value)
		"current":
			_apply_custom_row_heights([_row_height_edit_row], value)
	_row_height_edit_scope = ""
	_row_height_edit_row = -1

func _apply_custom_row_heights(rows: Array, height: int):
	for row in rows:
		var row_idx = int(row)
		if row_idx >= 0 and row_idx < datas_flat.size():
			custom_row_heights[row_idx] = float(height)
			row_heights[row_idx] = float(height)
	_row_offsets_dirty = true
	_force_row_layout_refresh = true
	update_content_size()
	_on_scroll(data_scroll.scroll_vertical)
	borders_overlay.queue_redraw()
	# 延迟一帧重新刷新可见行，确保延迟布局后的序号行尺寸正确
	call_deferred("_force_refresh_visible_rows")

func _clear_custom_row_heights(rows: Array):
	for row in rows:
		var row_idx = int(row)
		custom_row_heights.erase(row_idx)
		if row_idx >= 0 and row_idx < row_heights.size():
			row_heights[row_idx] = float(row_height)
			if row_height_mode == RowHeightMode.ADAPTIVE:
				row_height_dirty[row_idx] = true
			else:
				row_height_dirty.erase(row_idx)
	_row_offsets_dirty = true
	_force_row_layout_refresh = true
	update_content_size()
	_on_scroll(data_scroll.scroll_vertical)
	borders_overlay.queue_redraw()
	# 延迟一帧重新定位可见行，解决延迟布局覆盖序号行高度的问题
	call_deferred("_force_refresh_visible_rows")

## 延迟一帧重新定位所有可见行，确保延迟布局不会覆盖序号行高度。
func _force_refresh_visible_rows():
	if not is_inside_tree() or datas_flat.is_empty():
		return
	_position_visible_rows()
	update_content_size()
	_update_dragger_position()
	_update_borders_overlay_size()
	borders_overlay.queue_redraw()

func _on_header_col_pressed(i: int):
	if _drag_press_active:
		return
	if _header_did_drag:
		_header_did_drag = false
		return
	if i >= columns.size() or datas_flat.is_empty():
		return
	var dc = i  # col_widths index → data column index
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

func highlight_row(data_idx: int, skip_await: bool = false):
	if data_idx < 0 or data_idx >= datas_flat.size() or columns.is_empty():
		return
	clear_borders()
	var border = {
		"start": Vector2i(data_idx, 0),
		"rect": Rect2(data_idx, 0, 1, columns.size())
	}
	add_border(border)
	# 自动滚动到高亮行
	if not skip_await:
		await get_tree().create_timer(0.01).timeout
	var row_top = _get_row_top(data_idx)
	if data_idx >= 0 and row_top > data_scroll.scroll_vertical:
		data_scroll.scroll_vertical = row_top

func scroll_to_bottom():
	var v_bar = data_scroll.get_v_scroll_bar()
	await get_tree().create_timer(0.1).timeout
	v_bar.value = v_bar.max_value

func clear_rows():
	clear_borders()
	datas.clear()
	datas_flat.clear()
	for i in range(data_row_pool.size()):
		data_row_pool[i].visible = false
		data_pool_in_use[i] = false
	if show_frame:
		for i in range(frame_row_pool.size()):
			frame_row_pool[i].visible = false
			frame_pool_in_use[i] = false
	update_content_size()
	_on_scroll(data_scroll.scroll_vertical)

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
	if selected_borders.is_empty():
		return
	if selected_borders.size() > 1:
		GDSQL.WorkbenchManager.create_accept_dialog(tr("Can not apply copy to multi-selected areas."))
		return
	var rect = selected_borders.front()["rect"] as Rect2
	var map = {}
	var i_index = -1
	for i in range(int(rect.position.x), int(rect.end.x)):
		i_index += 1
		if not map.has(i_index):
			map[i_index] = {}
		var j_index = -1
		for j in range(int(rect.position.y), int(rect.end.y)):
			j_index += 1
			if datas_flat[i] is Array:
				map[i_index][j_index] = datas_flat[i][j]
			elif datas_flat[i] is Dictionary:
				map[i_index][j_index] = datas_flat[i][(datas_flat[i] as Dictionary).keys()[j]]
			elif datas_flat[i] is GDSQL.DictionaryObject:
				map[i_index][j_index] = (datas_flat[i] as GDSQL.DictionaryObject)._get_by_index(j)
			else:
				push_error("Table only support Array, Dictionary or GDSQL.DictionaryObject.")
	var content = "~~@@GDSQL-TABLE-COPY-CONTENT@@~~" + var_to_str(map)
	DisplayServer.clipboard_set(content)
func _on_button_paste_pressed():
	if selected_borders.is_empty():
		return
	if not editable:
		return
	var content = DisplayServer.clipboard_get()
	var map = null
	var prefix = "~~@@GDSQL-TABLE-COPY-CONTENT@@~~"
	if content.begins_with(prefix):
		map = str_to_var(content.substr(prefix.length()))
		if not map is Dictionary:
			map = null
			var msg = "Clipboard has content that begins with %s but fail to convert to a Dictionary." % prefix
			EditorInterface.get_editor_toaster().push_toast(msg, EditorToaster.SEVERITY_WARNING)
			push_warning(msg)
	if map == null:
		for border in selected_borders:
			var rect = border["rect"] as Rect2
			for i in range(int(rect.position.x), int(rect.end.x)):
				var dict_obj = datas_flat[i] as GDSQL.DictionaryObject
				for j in range(int(rect.position.y), int(rect.end.y)):
					if dict_obj.get_prop_usage_by_index(j) & PROPERTY_USAGE_READ_ONLY:
						var msg = "Skip a readonly cell. row: %d, col: %d" % [i, j]
						push_warning(msg)
						GDSQL.WorkbenchManager.add_log_history.emit("Warn", 0, "Paste", msg)
					else:
						dict_obj._set_by_index(j, type_convert(content, dict_obj.get_prop_type_by_index(j)))
	else:
		map = map as Dictionary
		var map_width = map.size()
		var map_height = (map[map.keys()[0]] as Dictionary).size()
		if selected_borders.size() == 1:
			var rect = selected_borders.front()["rect"] as Rect2
			var rows = range(int(rect.position.x),
				min(datas_flat.size(), int(rect.position.x) + max(map_width, map_width * int(rect.size.x / map_width))))
			var cols = range(int(rect.position.y),
				min(columns.size(), int(rect.position.y) + max(map_height, map_height * int(rect.size.y / map_height))))
			var i_index = -1
			for i in rows:
				i_index += 1
				i_index %= map_width
				var dict_obj = datas_flat[i] as GDSQL.DictionaryObject
				var j_index = -1
				for j in cols:
					j_index += 1
					j_index %= map_height
					if dict_obj.get_prop_usage_by_index(j) & PROPERTY_USAGE_READ_ONLY:
						var msg = "Skip a readonly cell. row: %d, col: %d" % [i, j]
						push_warning(msg)
						GDSQL.WorkbenchManager.add_log_history.emit("Warn", 0, "Paste", msg)
					else:
						dict_obj._set_by_index(j, type_convert(map[i_index][j_index], dict_obj.get_prop_type_by_index(j)))
			var border = {
				"start": selected_borders.front()["start"],
				"rect": Rect2(rect.position, Vector2(rows.size(), cols.size()))
			}
			add_border(border)
		else:
			for border in selected_borders:
				var rect = border["rect"] as Rect2
				if not ((rect.size.x == 1 and rect.size.y == 1) \
				or int(rect.size.x) % map_width == 0 or int(rect.size.y) % map_height == 0):
					GDSQL.WorkbenchManager.create_accept_dialog(tr("Cannot paste because the target areas' shape are different with source area."))
					return
			var selected_borders_bak = selected_borders.duplicate(true)
			clear_borders()
			for a_border in selected_borders_bak:
				var rect = a_border["rect"] as Rect2
				var rows = range(int(rect.position.x),
					min(datas_flat.size(), int(rect.position.x) + max(map_width, map_width * int(rect.size.x / map_width))))
				var cols = range(int(rect.position.y),
					min(columns.size(), int(rect.position.y) + max(map_height, map_height * int(rect.size.y / map_height))))
				var i_index = -1
				for i in rows:
					i_index += 1
					i_index %= map_width
					var dict_obj = datas_flat[i] as GDSQL.DictionaryObject
					var j_index = -1
					for j in cols:
						j_index += 1
						j_index %= map_height
						if dict_obj.get_prop_usage_by_index(j) & PROPERTY_USAGE_READ_ONLY:
							var msg = "Skip a readonly cell. row: %d, col: %d" % [i, j]
							push_warning(msg)
							GDSQL.WorkbenchManager.add_log_history.emit("Warn", 0, "Paste", msg)
						else:
							dict_obj._set_by_index(j, type_convert(map[i_index][j_index], dict_obj.get_prop_type_by_index(j)))
				var border = {
					"start": a_border["start"],
					"rect": Rect2(rect.position, Vector2(rows.size(), cols.size())),
					"ctrl": true
				}
				add_border(border)
func _on_button_delete_pressed():
	var data_list = get_data_of_highlight_rows()
	for d in data_list:
		if d is GDSQL.DictionaryObject:
			for c in columns.size():
				if not (d.get_prop_usage_by_index(c) & PROPERTY_USAGE_READ_ONLY):
					d._set_default_by_index(c)


func _on_button_edit_button_down():
	if not editable:
		return

	var selected_index
	if borders_has_same_cols():
		selected_index = range(selected_borders.front()["rect"].position.y, selected_borders.front()["rect"].end.y)
	elif borders_has_same_rows():
		selected_index = []
		for border in selected_borders:
			var rect = border["rect"] as Rect2
			for i in range(rect.position.y, rect.end.y):
				if not selected_index.has(i):
					selected_index.push_back(i)
		selected_index.sort()
	else:
		return

	var rows = get_data_of_highlight_rows()
	if rows.is_empty():
		return

	var selected_cols = []
	for i in selected_index:
		selected_cols.push_back((rows.front() as GDSQL.DictionaryObject).__get_index_prop(i))

	var readonly_props = []
	var p_usage = {}
	for data in rows:
		var plist = (data as Object).get_property_list()
		for F in plist:
			if not p_usage.has(F["name"]):
				p_usage[F["name"]] = F["usage"]
				if F["usage"] & PROPERTY_USAGE_READ_ONLY and not readonly_props.has(F["name"]):
					readonly_props.push_back(F["name"])
			elif p_usage[F["name"]] != F["usage"] and p_usage[F["name"]] != PROPERTY_USAGE_DEFAULT:
				p_usage[F["name"]] = PROPERTY_USAGE_DEFAULT

	var usage = {}
	var p_list = []
	var data_list = []
	var nc = 0
	for data in rows:
		if not data is Object:
			continue

		var plist = (data as Object).get_property_list()
		for F in plist:
			F["usage"] = p_usage[F["name"]]
			if not usage.has(F["name"]):
				usage[F["name"]] = {"uses": 0, "info": F}
				data_list.push_back(usage[F["name"]])

			if usage[F["name"]]["info"] == F:
				usage[F["name"]]["uses"] += 1

		nc += 1

	for E in data_list:
		if nc == E["uses"]:
			p_list.push_back(E["info"])

	var get_common_class_name = func():
		var a_class_name = null
		var check_again = true
		while check_again:
			check_again = false
			for data in rows:
				if not data is Object:
					continue
				data = data as Object
				var obj_class_name = data.get_class()
				if a_class_name == null:
					a_class_name = obj_class_name
				if obj_class_name == "Object":
					return obj_class_name
				if a_class_name == obj_class_name or ClassDB.is_parent_class(obj_class_name, a_class_name):
					continue
				a_class_name = ClassDB.get_parent_class(a_class_name)
				check_again = true
				break
		return a_class_name

	var common_class_name = get_common_class_name.call()
	if common_class_name == null:
		push_error("Can not find common parent class name")
		return

	var gdscript = GDSQL.GDSQLUtils.gdscript
	gdscript.source_code = "extends %s" % common_class_name
	gdscript.reload()
	var obj = gdscript.new()
	var props_of_common_class = obj.get_property_list()
	if obj.has_method("free") and not obj is RefCounted:
		obj.free()

	for i in props_of_common_class:
		for j in p_list.size():
			if i == p_list[j]:
				p_list.remove_at(j)
				break

	var dummy_dict_obj = GDSQL.DictionaryObject.new({})
	for i in dummy_dict_obj.get_property_list():
		for j in p_list.size():
			if i == p_list[j]:
				p_list.remove_at(j)
				break

	var tmp_p_list = []
	for j in p_list.size():
		if selected_cols.has(p_list[j]["name"]):
			tmp_p_list.push_back(p_list[j])
			continue
		if p_list[j]["usage"] & PROPERTY_USAGE_CATEGORY \
		or p_list[j]["usage"] & PROPERTY_USAGE_GROUP \
		or p_list[j]["usage"] & PROPERTY_USAGE_SUBGROUP:
			for i: String in selected_cols:
				if i.begins_with(p_list[j]["name"]):
					tmp_p_list.push_back(p_list[j])
					break
	p_list = tmp_p_list

	var impl_data = {}
	var impl_hint = {}
	var contains_readonly_prop = false
	for i in p_list:
		var prop = i["name"]
		if not contains_readonly_prop and readonly_props.has(prop):
			contains_readonly_prop = true
		var common_value = null
		var inited = false
		for data in rows:
			if not data is Object:
				continue
			if not inited:
				common_value = data.get(prop)
				impl_hint[prop] = {
					"type": i["type"],
					"usage": i["usage"],
					"hint": i["hint"],
					"hint_string": i["hint_string"],
				}
				inited = true
			elif common_value != data.get(prop):
				common_value = null
				break
		impl_data[prop] = common_value

	var impl_dict_obj = GDSQL.DictionaryObject.new(impl_data, impl_hint)

	var on_value_changed_ref = []
	var on_value_changed = func(prop, new_value, _old_value):
		var valid = false
		for data in rows:
			if not data is Object or not is_instance_valid(data):
				continue
			if data is GDSQL.DictionaryObject:
				if not (data.get_prop_usage(prop) & PROPERTY_USAGE_READ_ONLY):
					data.set(prop, new_value)
			else:
				var props = data.get_property_list()
				for ii in props:
					if ii["name"] == prop:
						if not ii["usage"] & PROPERTY_USAGE_READ_ONLY:
							data.set(prop, new_value)
						break
			valid = true
		if not valid:
			impl_dict_obj.value_changed.disconnect(on_value_changed_ref[0])
			EditorInterface.inspect_object(null)
	on_value_changed_ref.push_back(on_value_changed)
	impl_dict_obj.value_changed.connect(on_value_changed)
	impl_dict_obj.set_meta("align", "vertical")
	var arr: Array[Array] = [
		[impl_dict_obj],
	]
	if rows.size() > 1:
		arr.insert(0, ["Edit %d rows%s" % [rows.size(), "" if selected_cols.size() > 1 else "'s " + Array(selected_cols[0].rsplit(" ")).back()]])
	if contains_readonly_prop:
		arr.insert(0, ["NOTICE: Some rows that contain \nreadonly prop can not be modified!"])
	var min_width = 300 if selected_cols.size() == 1 else 600
	var min_height = 0 if selected_cols.size() < 5 else 800
	var pos = DisplayServer.mouse_get_position() + Vector2i(20, 15)
	GDSQL.WorkbenchManager.create_custom_popup_panel(arr, pos, Callable(), Callable(), Vector2i(min_width, min_height))

func _on_button_delete_row_pressed():
	var rows_idx = []
	var deleted_datas = {}
	for b in selected_borders:
		var r = b["rect"] as Rect2
		for i in range(int(r.position.x), int(r.end.x)):
			if not rows_idx.has(i):
				rows_idx.append(i)
				deleted_datas[i] = datas[i]
	rows_idx.sort()
	rows_idx.reverse()
	for i in rows_idx:
		if i < datas_flat.size():
			remove_data_at(i, true)
	row_deleted.emit(deleted_datas)

# ── Popup menu ─────────────────────────────────────────────────────────

func _on_popup_menu_index_pressed(index: int):
	match popup_menu_text.get_item_text(index):
		"Copy Field":
			var info = popup_menu_text.get_item_metadata(index)
			if not info:
				return
			var highlight_rows = get_data_of_highlight_rows()
			if highlight_rows.is_empty():
				var row_idx = info[1]
				highlight_rows.push_back(datas_flat[row_idx])
				
			var col_index = info[0]
			var arr_content = []
			for data in highlight_rows:
				var value = data[col_index] if (data is Array or data is Dictionary) \
					else (data as GDSQL.DictionaryObject)._get_by_index(col_index)
				match typeof(value):
					TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
						arr_content.push_back(str(value))
					TYPE_OBJECT:
						if value is Resource:
							arr_content.push_back(value.resource_path)
						else:
							arr_content.push_back(var_to_str(value))
					_:
						arr_content.push_back(var_to_str(value))
			DisplayServer.clipboard_set("\n".join(arr_content))
		"Copy Line":
			var info = popup_menu_text.get_item_metadata(index)
			if not info:
				return
				
			var highlight_rows = get_data_of_highlight_rows()
			if highlight_rows.is_empty():
				var row_idx = info[1]
				highlight_rows.push_back(datas_flat[row_idx])
				
			var arr = []
			for data in highlight_rows:
				var arr_content = []
				for col_index in columns.size():
					var value = data[col_index] if (data is Array or data is Dictionary) \
						else (data as GDSQL.DictionaryObject)._get_by_index(col_index)
					match typeof(value):
						TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
							arr_content.push_back(var_to_str(value))
						TYPE_OBJECT:
							if value is Resource:
								arr_content.push_back(var_to_str(value.resource_path))
							else:
								arr_content.push_back(var_to_str(value))
						_:
							arr_content.push_back(var_to_str(value))
				arr.push_back("\t".join(arr_content))
			DisplayServer.clipboard_set("\n".join(arr))
		"Delete":
			if selected_borders.is_empty():
				var info = popup_menu_text.get_item_metadata(index)
				if info:
					var row_idx = info[1]
					if row_idx >= 0 and row_idx < datas_flat.size():
						var deleted_datas = {row_idx: datas_flat[row_idx]}
						remove_data_at(row_idx, true)
						row_deleted.emit(deleted_datas)
			else:
				_on_button_delete_row_pressed()
				
	popup_menu_text.set_item_metadata(index, null)
	
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
	var ci = last_col
	if ci < 0 or ci >= col_widths.size():
		return
	var cx = _get_col_x(ci) + col_widths[ci] - data_scroll.scroll_horizontal
	var cy = _get_row_bottom(last_row) - data_scroll.scroll_vertical
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
	var scroll_val = data_scroll.scroll_vertical
	var row = _get_row_at_content_y(local_pos.y + scroll_val)
	if row < 0 or row >= datas_flat.size():
		return Vector2i(-1, -1)

	var x = 0.0
	for c in range(col_widths.size()):
		var w = col_widths[c]
		if local_pos.x >= x and local_pos.x < x + w:
			var data_col = c
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
			var val = str(_get_data_by_cell(datas_flat.find(d), 0)) if datas_flat.has(d) else ""
			arr.append(val)
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
			var val = str(_get_data_by_cell(idx, c)) if idx >= 0 else ""
			row_arr.append(val)
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
	if last_row >= 0 and _get_row_bottom(last_row) <= data_row_container.custom_minimum_size.y:
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


var _last_data_scroll_v: float = -1
var _scroll_guard := false

func _process(_delta):
	# Sync frame row container position
	if show_frame and is_instance_valid(data_scroll) and is_instance_valid(frame_row_container):
		var sv = data_scroll.scroll_vertical
		if sv != _last_data_scroll_v:
			_last_data_scroll_v = sv
			frame_row_container.position.y = -sv

	# Reposition built-in v_bar to data content's visible right edge
	if is_instance_valid(data_scroll) and is_instance_valid(data_row_container):
		var v_bar = data_scroll.get_v_scroll_bar()
		var data_w = data_row_container.custom_minimum_size.x
		if v_bar.visible and data_w > 0:
			var scroll_h = data_scroll.scroll_horizontal
			var view_w = data_scroll.size.x
			var visible_right = min(view_w, data_w - scroll_h)
			var bar_w = v_bar.size.x
			var bar_left = min(visible_right, view_w - bar_w)
			v_bar.position.x = max(0, bar_left)

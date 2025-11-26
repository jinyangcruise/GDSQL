## 一个用于显示对比工具增加/减少行数的Texture2D。显示效果是 +12 -3 这样的纹理。且正数是绿色，
## 负数是红色。
extends Texture2D

## 显示正数，为0时不显示
@export var add_count: int = 0:
	set(val):
		add_count = val
		refresh()
		
## 显示负数，为0时不显示
@export var remove_count: int = 0:
	set(val):
		remove_count = val
		refresh()
		
var _positive_text: String
var _negative_text: String
var _positive_size: Vector2
var _negative_size: Vector2
var _width: int

func _init() -> void:
	refresh()
	
func refresh():
	# 构建显示文本
	_positive_text = "+%d" % add_count if add_count > 0 else ""
	_negative_text = "-%d" % remove_count if remove_count > 0 else ""
	
	# 获取默认字体
	var font := ThemeDB.get_default_theme().get_font("main", "EditorFonts")
	var font_size: int = ThemeDB.get_default_theme().get_font_size("main_size", "EditorFonts")
	
	# 计算文本尺寸
	if _positive_text:
		_positive_size = Vector2(font.get_string_size(_positive_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size))
	if _negative_text:
		_negative_size = Vector2(font.get_string_size(_negative_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size))
		
	# 计算总尺寸
	var spacing = 4 if _positive_text and _negative_text else 0
	# 绘制正数文本（绿色）
	if _positive_text:
		@warning_ignore("narrowing_conversion")
		_width = _positive_size.x
		
	#绘制负数文本（红色）
	if _negative_text:
		var pos = Vector2(_positive_size.x + spacing, font_size)
		_width = pos.x + _negative_size.x
		
	emit_changed()
	
@warning_ignore("unused_parameter")
func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
	_draw_string(to_canvas_item, pos)
	
@warning_ignore("unused_parameter")
func _draw_rect_region(to_canvas_item: RID, rect: Rect2, src_rect: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
	_draw_string(to_canvas_item, rect.position)
	
@warning_ignore("unused_parameter")
func _draw_rect(to_canvas_item: RID, rect: Rect2, tile: bool, modulate: Color, transpose: bool) -> void:
	_draw_string(to_canvas_item, rect.position)
	
func _draw_string(to_canvas_item, base_pos = Vector2.ZERO):
	var font = null
	var font_size = null
	# 绘制正数文本（绿色）
	if _positive_text:
		if not font:
			font = ThemeDB.get_default_theme().get_font("main", "EditorFonts")
		if not font_size:
			font_size = ThemeDB.get_default_theme().get_font_size("main_size", "EditorFonts")
		@warning_ignore("narrowing_conversion")
		_width = _positive_size.x
		var pos = Vector2(0, font_size) + base_pos
		font.draw_string(to_canvas_item, pos, _positive_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.GREEN)
		
	#绘制负数文本（红色）
	if _negative_text:
		if not font:
			font = ThemeDB.get_default_theme().get_font("main", "EditorFonts")
		if not font_size:
			font_size = ThemeDB.get_default_theme().get_font_size("main_size", "EditorFonts")
		var spacing = 4 if _positive_text else 0
		var pos = Vector2(_positive_size.x + spacing, font_size) + base_pos
		_width = pos.x + _negative_size.x - base_pos.x
		font.draw_string(to_canvas_item, pos, _negative_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.RED)
		
func _get_height() -> int:
	@warning_ignore("narrowing_conversion")
	return _positive_size.y
	
func _get_width() -> int:
	return _width

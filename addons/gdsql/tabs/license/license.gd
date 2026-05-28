@tool
extends ScrollContainer

## License attribution page — shows all third-party icons and their licenses.

const LICENSE_FILE = "res://addons/gdsql/img/license.txt"

var _font_variation: FontVariation

func _ready() -> void:
	_font_variation = FontVariation.new()
	_font_variation.set_spacing(TextServer.SPACING_TOP, 7)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	var title = Label.new()
	title.text = "Open Source Licenses"
	add_margin(vbox, 8)
	vbox.add_child(title)

	var desc = Label.new()
	desc.text = "This addon uses icons from the following sources. Each icon is listed with its original name, author, source link, and license."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_margin(vbox, 4)
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())
	add_margin(vbox, 4)

	var f = FileAccess.open(LICENSE_FILE, FileAccess.READ)
	if not f:
		var err_label = Label.new()
		err_label.text = "License file not found: %s" % LICENSE_FILE
		vbox.add_child(err_label)
		return

	var line = f.get_line()
	while line != "":
		var item = _parse_line(line.strip_edges())
		if item:
			vbox.add_child(_make_item(item))
			vbox.add_child(HSeparator.new())
		line = f.get_line()

	f.close()


func _parse_line(line: String) -> Dictionary:
	# Format: path,icon_url,attribution_text,license
	var parts = line.split(",", false, 4)
	if parts.size() < 3:
		return {}

	var path_part = parts[0].strip_edges()
	var icon_url = parts[1].strip_edges()
	var rest = parts[2].strip_edges()
	var license_text = parts[3].strip_edges() if parts.size() >= 4 else "CC BY 4.0"

	# Parse attribution: "name by author on <a href="url">site</a>"
	var on_pos = rest.find(" on <a href=")
	var by_pos = rest.find(" by ")

	var name = ""
	var author = ""
	var source_url = ""
	var site = ""

	if on_pos >= 0:
		var desc_part = rest.substr(0, on_pos).strip_edges()
		var href_section = rest.substr(on_pos + 1)

		var href_start = href_section.find("\"")
		if href_start >= 0:
			var href_end = href_section.find("\"", href_start + 1)
			if href_end >= 0:
				source_url = href_section.substr(href_start + 1, href_end - href_start - 1)

		var gt_pos = href_section.find(">")
		var lt_pos = href_section.find("</a")
		if gt_pos >= 0 and lt_pos > gt_pos:
			site = href_section.substr(gt_pos + 1, lt_pos - gt_pos - 1).strip_edges()

		if by_pos >= 0:
			name = desc_part.substr(0, by_pos).strip_edges()
			author = desc_part.substr(by_pos + 4).strip_edges()
		else:
			name = desc_part
	else:
		by_pos = rest.find(" by ")
		if by_pos >= 0:
			name = rest.substr(0, by_pos).strip_edges()
			author = rest.substr(by_pos + 4).strip_edges()
		else:
			name = rest

	return {
		"path": path_part,
		"icon_url": icon_url,
		"name": name,
		"author": author,
		"source_url": source_url,
		"site": site,
		"license": license_text,
	}


func _make_item(item: Dictionary) -> Control:
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 4)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Row 1: icon + 3-column grid (name | author | license)
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var tex = ResourceLoader.load(item["path"], "Texture2D", ResourceLoader.CACHE_MODE_REUSE)
	if tex:
		var texture_rect = TextureRect.new()
		texture_rect.texture = tex
		texture_rect.custom_minimum_size = Vector2(32, 32)
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		top.add_child(texture_rect)

	# Column 1: icon name
	var name_btn = LinkButton.new()
	name_btn.text = item["name"]
	name_btn.uri = item["icon_url"]
	name_btn.underline = LinkButton.UNDERLINE_MODE_NEVER
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.size_flags_stretch_ratio = 3
	name_btn.add_theme_font_override("font", _font_variation)
	top.add_child(name_btn)

	# Column 2: author
	if not item["author"].is_empty():
		var author_btn = LinkButton.new()
		author_btn.text = "By %s" % item["author"]
		author_btn.uri = item["source_url"]
		author_btn.underline = LinkButton.UNDERLINE_MODE_NEVER
		author_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		author_btn.size_flags_stretch_ratio = 2
		author_btn.add_theme_font_override("font", _font_variation)
		top.add_child(author_btn)

	# Column 3: license badge
	var badge_panel = PanelContainer.new()
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = Color(0.25, 0.5, 0.25, 0.3)
	badge_style.corner_radius_top_left = 4
	badge_style.corner_radius_top_right = 4
	badge_style.corner_radius_bottom_right = 4
	badge_style.corner_radius_bottom_left = 4
	badge_style.content_margin_left = 6
	badge_style.content_margin_right = 6
	badge_style.content_margin_top = 1
	badge_style.content_margin_bottom = 1
	badge_panel.add_theme_stylebox_override("panel", badge_style)

	var badge_label = Label.new()
	badge_label.text = item["license"]
	badge_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))
	badge_panel.add_child(badge_label)
	badge_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge_panel.size_flags_stretch_ratio = 1
	top.add_child(badge_panel)

	vbox.add_child(top)
	return margin


func add_margin(vbox: VBoxContainer, size: int) -> void:
	var c = Control.new()
	c.custom_minimum_size = Vector2(0, size)
	vbox.add_child(c)

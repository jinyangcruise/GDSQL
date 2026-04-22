@tool
extends Tree

func _make_custom_tooltip(for_text: String) -> Object:
	if for_text == "":
		return null
		
	var rich_text_label = RichTextLabel.new()
	rich_text_label.set_theme_type_variation(&"TooltipLabel")
	rich_text_label.bbcode_enabled = true
	rich_text_label.text = for_text
	rich_text_label.autowrap_trim_flags = TextServer.BREAK_NONE
	rich_text_label.fit_content = true
	rich_text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return rich_text_label

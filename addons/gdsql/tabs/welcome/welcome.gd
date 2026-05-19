@tool
extends PanelContainer

@onready var center_container: CenterContainer = %CenterContainer
@onready var content: VBoxContainer = %Content
@onready var random_tip_label: RichTextLabel = %RandomTipLabel
@onready var version: Label = %Version
@onready var settings_button: Button = %SettingsButton


func _ready() -> void:
	var plugin_cfg := ConfigFile.new()
	plugin_cfg.load("res://addons/gdsql/plugin.cfg")
	version.text = plugin_cfg.get_value('plugin', 'version', 'unknown version')
	
	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)
	
	
func _on_random_tip_label_resized() -> void:
	if content:
		content.set_deferred(&"size", Vector2(content.size.x, 0))


func _on_settings_button_pressed() -> void:
	if GDSQL.WorkbenchManager:
		GDSQL.WorkbenchManager.open_settings_tab.emit()

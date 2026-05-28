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
	version.text = "v" + plugin_cfg.get_value('plugin', 'version', 'unknown version')

	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)

	_add_license_button()


func _add_license_button() -> void:
	# 找到 "Other Addons" 的父容器，在其后添加 License 按钮
	var other_addons = find_child("OtherAddonsLink", true, false)
	if not other_addons:
		return
	var parent = other_addons.get_parent()
	if not parent:
		return


func _on_license_button_pressed() -> void:
	if GDSQL.WorkbenchManager:
		GDSQL.WorkbenchManager.open_license_tab.emit()


func _on_random_tip_label_resized() -> void:
	if content:
		content.set_deferred(&"size", Vector2(content.size.x, 0))


func _on_settings_button_pressed() -> void:
	if GDSQL.WorkbenchManager:
		GDSQL.WorkbenchManager.open_settings_tab.emit()

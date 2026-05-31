@tool
extends PanelContainer

@onready var center_container: CenterContainer = %CenterContainer
@onready var content: VBoxContainer = %Content
@onready var random_tip_label: RichTextLabel = %RandomTipLabel
@onready var version: Button = %Version
@onready var settings_button: Button = %SettingsButton

var _version: String
var _updater: AcceptDialog
var _auto_check_http: HTTPRequest

func _ready() -> void:
	var plugin_cfg := ConfigFile.new()
	plugin_cfg.load("res://addons/gdsql/plugin.cfg")
	_version = "v" + plugin_cfg.get_value('plugin', 'version', 'unknown version')
	version.text = _version
	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)

	_start_auto_update_check()


func _on_update_button_pressed() -> void:
	if _updater:
		_updater.queue_free()
	_updater = load("res://addons/gdsql/tabs/plugin_updater/updater.gd").new()
	add_child(_updater)
	_updater.popup_centered()


func _on_license_button_pressed() -> void:
	if GDSQL.WorkbenchManager:
		GDSQL.WorkbenchManager.open_license_tab.emit()


func _on_random_tip_label_resized() -> void:
	if content:
		content.set_deferred(&"size", Vector2(content.size.x, 0))


func _on_settings_button_pressed() -> void:
	if GDSQL.WorkbenchManager:
		GDSQL.WorkbenchManager.open_settings_tab.emit()


func _on_version_mouse_entered() -> void:
	version.flat = false
	version.text = tr("Check updates")


func _on_version_mouse_exited() -> void:
	version.flat = true
	version.text = _version


func _start_auto_update_check() -> void:
	var settings := ConfigFile.new()
	settings.load("res://gdsql/settings.cfg")
	if not settings.get_value("config", "auto_check_updates", true):
		return

	_auto_check_http = HTTPRequest.new()
	add_child(_auto_check_http)
	_auto_check_http.request_completed.connect(_on_auto_check_completed)
	_auto_check_http.request("https://api.github.com/repos/jinyangcruise/GDSQL/releases/latest")


func _on_auto_check_completed(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		return

	var json = JSON.new()
	var err = json.parse(body.get_string_from_utf8())
	if err != OK:
		return

	var data = json.data
	if not data is Dictionary or not data.has("tag_name"):
		return

	var latest = (data["tag_name"] as String).trim_prefix("v")
	var current = _version.trim_prefix("v")

	if GDSQL.GDSQLUtils.cmp_version(current, latest) >= 0:
		return

	# Parse upgrade_ranges from release body (same format as updater)
	var notes = data.get("body", "")
	if notes == null:
		notes = ""
	var max_upgrade = GDSQL.GDSQLUtils.parse_max_upgrade(notes, current)
	if max_upgrade == "":
		return  # current version not in any upgrade range

	# Check if already at the range ceiling with breaking change beyond
	if GDSQL.GDSQLUtils.cmp_version(latest, max_upgrade) > 0 and GDSQL.GDSQLUtils.cmp_version(current, max_upgrade) >= 0:
		return  # at max of range and can't go further

	version.icon = preload("res://addons/gdsql/img/upgrade.svg")
	version.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.tooltip_text = "A new version is available."

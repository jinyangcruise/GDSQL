@tool
extends PanelContainer

var _version: String
var _updater: AcceptDialog
var _auto_check_http: HTTPRequest
var _TIPS: Array[String] = load("res://addons/gdsql/tabs/welcome/tips.gd").TIPS
var _shuffled_indices: Array[int] = []
var _current_shuffle_pos: int = 0
var _rng: RandomNumberGenerator

@onready var center_container: CenterContainer = %CenterContainer
@onready var content: VBoxContainer = %Content
@onready var random_tip_label: RichTextLabel = %RandomTipLabel
@onready var version: Button = %Version
@onready var settings_button: Button = %SettingsButton
@onready var refresh_tip_button: Button = %RefreshTipButton
@onready var prev_tip_button: Button = %PrevTipButton
@onready var next_tip_button: Button = %NextTipButton


func _ready() -> void:
	var plugin_cfg := ConfigFile.new()
	plugin_cfg.load("res://addons/gdsql/plugin.cfg")
	_version = "v" + plugin_cfg.get_value('plugin', 'version', 'unknown version')
	version.text = _version
	if settings_button:
		settings_button.pressed.connect(_on_settings_button_pressed)

	# 初始化可预测的随机序列（固定种子，每次启动顺序一致）
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42

	_start_auto_update_check()
	_reshuffle_tips()
	_show_current_tip()


func _reshuffle_tips() -> void:
	_shuffled_indices = []
	for i in _TIPS.size():
		_shuffled_indices.push_back(i)
	# Fisher-Yates 洗牌
	for i in range(_shuffled_indices.size() - 1, 0, -1):
		var j = _rng.randi_range(0, i)
		var temp = _shuffled_indices[i]
		_shuffled_indices[i] = _shuffled_indices[j]
		_shuffled_indices[j] = temp
	_current_shuffle_pos = 0


func _show_current_tip() -> void:
	if _shuffled_indices.is_empty():
		_reshuffle_tips()
	random_tip_label.text = _TIPS[_shuffled_indices[_current_shuffle_pos]]


func _show_random_tip() -> void:
	# 随机按钮：重新洗牌，从头开始
	_reshuffle_tips()
	_show_current_tip()


func _advance_tip() -> void:
	_current_shuffle_pos += 1
	if _current_shuffle_pos >= _shuffled_indices.size():
		_reshuffle_tips()
	_show_current_tip()


func _on_update_button_pressed() -> void:
	if _updater:
		_updater.queue_free()
	_updater = load("res://addons/gdsql/tabs/plugin_updater/updater.gd").new()
	add_child(_updater)
	_updater.popup_centered()
	_updater.visibility_changed.connect(_refresh_version)


func _refresh_version() -> void:
	if _updater.visible:
		return
	var plugin_cfg := ConfigFile.new()
	plugin_cfg.load("res://addons/gdsql/plugin.cfg")
	_version = "v" + plugin_cfg.get_value('plugin', 'version', 'unknown version')
	version.text = _version
	version.icon = null
	version.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	version.tooltip_text = ""


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
		return # current version not in any upgrade range

	# Check if already at the range ceiling with breaking change beyond
	if GDSQL.GDSQLUtils.cmp_version(latest, max_upgrade) > 0 and GDSQL.GDSQLUtils.cmp_version(current, max_upgrade) >= 0:
		return # at max of range and can't go further

	version.icon = preload("res://addons/gdsql/img/upgrade.svg")
	version.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.tooltip_text = "A new version is available."


func _on_prev_tip_button_pressed() -> void:
	if _current_shuffle_pos > 0:
		_current_shuffle_pos -= 1
		_show_current_tip()


func _on_next_tip_button_pressed() -> void:
	_advance_tip()

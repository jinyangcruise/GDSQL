@tool
extends AcceptDialog

## Plugin version checker and updater.
##
## Usage:
##   var updater = preload("res://addons/gdsql/tabs/plugin_updater/updater.gd").new()
##   updater.popup_centered()

const MANIFEST_PATH = "res://addons/gdsql/tabs/plugin_updater/file_manifest.txt"
const PLUGIN_CFG_PATH = "res://addons/gdsql/plugin.cfg"
const GITHUB_API = "https://api.github.com/repos/jinyangcruise/GDSQL/releases/latest"
const GDSQL_DIR = "res://addons/gdsql/"

var _current_version: String = ""
var _latest_version: String = ""
var _release_info: Dictionary = {}
var _vbox: VBoxContainer
var _status_label: Label
var _info_label: Label
var _notes_rt: RichTextLabel
var _upgrade_btn: Button
var _http: HTTPRequest


func _init() -> void:
	title = "Check for Updates"
	min_size = Vector2(780, 620)
	exclusive = true

	# Read current version
	var cfg = ConfigFile.new()
	cfg.load(PLUGIN_CFG_PATH)
	_current_version = cfg.get_value("plugin", "version", "0.0.0")

	# Build UI
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 8)
	add_child(_vbox)

	# Status
	_status_label = Label.new()
	_status_label.text = "Checking for updates..."
	_vbox.add_child(_status_label)

	# Version info
	_info_label = Label.new()
	_info_label.text = "Installed: v%s" % _current_version
	_vbox.add_child(_info_label)

	# Release notes
	_notes_rt = RichTextLabel.new()
	_notes_rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes_rt.bbcode_enabled = true
	_notes_rt.scroll_active = true
	_notes_rt.text = ""
	_vbox.add_child(_notes_rt)

	# Upgrade button
	_upgrade_btn = Button.new()
	_upgrade_btn.text = "Upgrade"
	_upgrade_btn.disabled = true
	_upgrade_btn.pressed.connect(_on_upgrade)
	_vbox.add_child(_upgrade_btn)

	# HTTP request for version check
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	# HTTP request for download
	var _dl_http = HTTPRequest.new()
	_dl_http.name = "DownloadHTTP"
	add_child(_dl_http)
	_dl_http.request_completed.connect(_on_download_complete)



## Compare two semver strings. Returns -1, 0, or 1.
func _ready() -> void:
	_http.request(GITHUB_API)


func _cmp_version(a: String, b: String) -> int:
	var pa = a.split(".")
	var pb = b.split(".")
	for i in range(max(pa.size(), pb.size())):
		var va = int(pa[i]) if i < pa.size() else 0
		var vb = int(pb[i]) if i < pb.size() else 0
		if va < vb: return -1
		if va > vb: return 1
	return 0


## Called when HTTP request completes.
func _on_request_completed(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_status_label.text = "Failed to check for updates (network error: %d)." % result
		return

	var json = JSON.new()
	var err = json.parse(body.get_string_from_utf8())
	if err != OK:
		_status_label.text = "Failed to parse server response."
		return

	var data = json.data
	if not data is Dictionary:
		_status_label.text = "Unexpected response."
		return
	if data.has("message"):
		_status_label.text = "GitHub API: %s" % data["message"]
		return
	if not data.has("tag_name"):
		_status_label.text = "Unexpected response (no tag_name)."
		_notes_rt.text = str(data).substr(0, 500)
		return

	_latest_version = (data["tag_name"] as String).trim_prefix("v")
	_release_info = data

	_status_label.text = "Latest version: v%s" % _latest_version

	# Release notes
	var notes = data.get("body", "No release notes.")
	if notes == null:
		notes = "No release notes."
	# Truncate very long notes
	if notes.length() > 3000:
		notes = notes.substr(0, 3000) + "\n... (truncated)"
	_notes_rt.text = "[b]Release notes:[/b]\n" + notes

	# Compare versions
	var cmp = _cmp_version(_current_version, _latest_version)
	if cmp > 0:
		_status_label.text = "Your version (v%s) is ahead of the latest release (v%s)." % [_current_version, _latest_version]
		_upgrade_btn.disabled = true
		_upgrade_btn.text = "Up to date"
	elif cmp == 0:
		_status_label.text = "You're up to date! (v%s)" % _current_version
		_upgrade_btn.disabled = true
		_upgrade_btn.text = "Up to date"
	else:
		_status_label.text = "A new version is available: v%s → v%s" % [_current_version, _latest_version]
		_upgrade_btn.disabled = false
		_upgrade_btn.text = "Upgrade to v%s" % _latest_version

	get_ok_button().text = "Close"


## Build the set of files a given version should have, based on the manifest.
func _files_for_version(version: String) -> Dictionary:
	var files = {}
	var f = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if not f:
		return files

	while not f.eof_reached():
		var line = f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts = line.split(",", true, 3)
		if parts.size() < 3:
			continue
		var action = parts[0]
		var ver = parts[1]
		var path = parts[2]
		if _cmp_version(ver, version) > 0:
			continue
		match action:
			"+":
				files[path] = true
			"-":
				files.erase(path)
	f.close()
	return files


## Detect files in GDSQL_DIR that are NOT in the target version's file list.
func _detect_user_files(target_version: String) -> Array:
	var known = _files_for_version(target_version)
	var user_files = []
	# List files recursively
	var dir = DirAccess.open(GDSQL_DIR)
	if not dir:
		return user_files
	_collect_files(dir, GDSQL_DIR.trim_prefix("res://"), known, user_files)
	return user_files


func _collect_files(dir: DirAccess, prefix: String, known: Dictionary, result: Array) -> void:
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if f in [".", "..", ".git"]:
			f = dir.get_next()
			continue
		var rel = "addons/" + prefix + f
		if dir.current_is_dir():
			var sub = DirAccess.open("res://" + prefix + f)
			if sub:
				_collect_files(sub, prefix + f + "/", known, result)
		else:
			# For .uid/.import: flag only if the base file is not in known
			if f.ends_with(".uid") or f.ends_with(".import"):
				var base = rel.trim_suffix(".uid") if rel.ends_with(".uid") else rel.trim_suffix(".import")
				if not known.has(base):
					result.push_back(rel)
				f = dir.get_next()
				continue
			if not known.has(rel):
				result.push_back(rel)
		f = dir.get_next()
	dir.list_dir_end()


## Start the upgrade process.
func _on_upgrade() -> void:
	_upgrade_btn.disabled = true
	_upgrade_btn.text = "Preparing..."
	
	# Check for user-modified files
	var user_files = _detect_user_files(_latest_version)
	
	if not user_files.is_empty():
		var warn_text = "The following files in addons/gdsql/ are not part of the plugin. They may be your custom data:\n\n"
		var max_show = 30
		for i in range(min(user_files.size(), max_show)):
			warn_text += "  - " + user_files[i] + "\n"
		if user_files.size() > max_show:
			warn_text += "  ... and %d more files\n" % (user_files.size() - max_show)
		warn_text += "\nDo you want to proceed with the upgrade?"
		
		var warn = AcceptDialog.new()
		warn.title = "Files Not Part of GDSQL"
		warn.dialog_text = warn_text
		warn.get_ok_button().text = "Cancel"
		warn.add_button("Ignore and force overwrite", false, "force")
		
		add_child(warn)
		
		var user_choice = ["cancel"]
		warn.confirmed.connect(func(): user_choice[0] = "cancel"; warn.queue_free())
		warn.canceled.connect(func(): user_choice[0] = "cancel"; warn.queue_free())
		warn.custom_action.connect(func(a): user_choice[0] = a; warn.queue_free())
		warn.popup_centered()
		await warn.tree_exited
		
		if user_choice[0] != "force":
			_upgrade_btn.disabled = false
			_upgrade_btn.text = "Upgrade to v%s" % _latest_version
			return
			
	_start_download()
	
	
func _start_download() -> void:
	var zip_url = _release_info.get("zipball_url", "")
	if zip_url.is_empty():
		_status_label.text = "Error: No download URL found."
		return
		
	_status_label.text = "Downloading v%s..." % _latest_version
	_upgrade_btn.text = "Downloading..."
	_upgrade_btn.disabled = true
	
	var dl = find_child("DownloadHTTP") as HTTPRequest
	if not dl:
		_status_label.text = "Internal error."
		return
	var err = dl.request(zip_url)
	if err != OK:
		_status_label.text = "Failed to start download."
		_upgrade_btn.disabled = false
		_upgrade_btn.text = "Retry"
		
		
func _on_download_complete(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_status_label.text = "Download failed."
		_upgrade_btn.disabled = false
		_upgrade_btn.text = "Retry"
		return
		_status_label.text = "Extracting..."
		
		# Save to temp file
		var tmp_path = "user://gdsql_update_%s.zip" % _latest_version
		var f = FileAccess.open(tmp_path, FileAccess.WRITE)
		if not f:
			_status_label.text = "Failed to write temp file."
			_upgrade_btn.disabled = false
			_upgrade_btn.text = "Retry"
			return
		f.store_buffer(body)
		f.close()
		
		# Extract using ZIPReader
		var reader = ZIPReader.new()
		var open_err = reader.open(tmp_path)
		if open_err != OK:
			_status_label.text = "Failed to open zip."
			_upgrade_btn.disabled = false
			_upgrade_btn.text = "Retry"
			return
			
		var zip_files = reader.get_files()
		# GitHub zipball has a top-level dir like "repo-tag-commit/"
		var prefix = ""
		for fp in zip_files:
			if fp.ends_with("/"):
				prefix = fp
				break
				
		var extracted = 0
		for fp in zip_files:
			if not fp.begins_with(prefix + "addons/gdsql/"):
				continue
			if fp.ends_with("/"):
				continue
			var rel = fp.trim_prefix(prefix)
			var target = "res://" + rel
			var data = reader.read_file(fp)
			if fp.ends_with(".import"):
				continue
			# Ensure dir exists
			var d = DirAccess.open("res://")
			if d:
				d.make_dir_recursive(target.get_base_dir())
			var wf = FileAccess.open(target, FileAccess.WRITE)
			if wf:
				wf.store_buffer(data)
				wf.close()
				extracted += 1
				
		reader.close()
		# Cleanup temp zip
		var global_path = ProjectSettings.globalize_path(tmp_path)
		if DirAccess.dir_exists_absolute(global_path):
			var dp = DirAccess.open(tmp_path.get_base_dir())
			if dp:
				dp.remove(tmp_path.get_file())
				
		_status_label.text = "Upgrade complete! (%d files updated) Please restart Godot." % extracted
		_upgrade_btn.disabled = true
		_upgrade_btn.text = "Done"

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
var _download_pct: int = -1
var _download_size: String = ""
var _target_version: String = ""
var _vbox: VBoxContainer
var _status_label: Label
var _info_label: Label
var _notes_rt: RichTextLabel
var _upgrade_btn: Button
var _http: HTTPRequest
var _http_notes: HTTPRequest
var _max_upgrade: String = ""


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

	# HTTP request for target version release notes
	_http_notes = HTTPRequest.new()
	add_child(_http_notes)
	_http_notes.request_completed.connect(_on_notes_completed)




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


## Called when the latest-release HTTP request completes.
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

	# Release notes from latest (may be replaced if target differs)
	var latest_notes = data.get("body", "No release notes.")
	if latest_notes == null:
		latest_notes = "No release notes."
	if latest_notes.length() > 10000:
		latest_notes = latest_notes.substr(0, 10000) + "\n... (truncated)"

	# Parse upgrade ranges from latest release body
	_max_upgrade = _parse_max_upgrade(latest_notes, _current_version)

	# Determine target version
	var cmp = _cmp_version(_current_version, _latest_version)
	if cmp > 0 or cmp == 0 or _max_upgrade == "" or (_cmp_version(_current_version, _max_upgrade) >= 0 and _cmp_version(_latest_version, _max_upgrade) > 0):
		_target_version = ""
	elif _cmp_version(_latest_version, _max_upgrade) > 0:
		_target_version = _max_upgrade
	else:
		_target_version = _latest_version

	# If target differs from latest, fetch target release notes
	if not _target_version.is_empty() and _target_version != _latest_version:
		_status_label.text = "Fetching release notes for v%s..." % _target_version
		var tag_url = "https://api.github.com/repos/jinyangcruise/GDSQL/releases/tags/v" + _target_version
		_http_notes.request(tag_url)
		return

	# Otherwise use latest notes directly
	_finalize_version_info(latest_notes)


## Called when the target-version release notes HTTP request completes.
func _on_notes_completed(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or body.is_empty():
		var fallback = _release_info.get("body", "No release notes.")
		if fallback == null: fallback = ""
		_finalize_version_info(fallback)
		return

	var json = JSON.new()
	var err = json.parse(body.get_string_from_utf8())
	if err != OK:
		var fallback = _release_info.get("body", "No release notes.")
		if fallback == null: fallback = ""
		_finalize_version_info(fallback)
		return

	var data = json.data
	if not data is Dictionary:
		var fallback = _release_info.get("body", "No release notes.")
		if fallback == null: fallback = ""
		_finalize_version_info(fallback)
		return

	var target_notes = data.get("body", "No release notes.")
	if target_notes == null:
		target_notes = "No release notes."
	if target_notes.length() > 10000:
		target_notes = target_notes.substr(0, 10000) + "\n... (truncated)"

	_finalize_version_info(target_notes)


## Show the final version info UI once we have the correct release notes.
func _finalize_version_info(notes: String) -> void:
	var cmp = _cmp_version(_current_version, _latest_version)
	if cmp > 0:
		_status_label.text = "Your version (v%s) is ahead of the latest release (v%s)." % [_current_version, _latest_version]
		_upgrade_btn.disabled = true
		_upgrade_btn.text = "Up to date"
		_notes_rt.text = "[b]Release notes:[/b]\n" + notes
	elif cmp == 0:
		_status_label.text = "You're up to date! (v%s)" % _current_version
		_upgrade_btn.disabled = true
		_upgrade_btn.text = "Up to date"
		_notes_rt.text = "[b]Release notes:[/b]\n" + notes
	elif _max_upgrade == "":
		_status_label.text = "Current version v%s is not in any upgrade path." % _current_version
		_notes_rt.text = "[b]No upgrade path[/b]\n\nYour version (v%s) does not fall into any supported upgrade range.\n\nPlease check GitHub Releases for manual upgrade options.\n\n" % _current_version + "[b]Release notes:[/b]\n" + notes
		_upgrade_btn.disabled = true
		_upgrade_btn.text = "No upgrade path"
	elif _cmp_version(_latest_version, _max_upgrade) > 0:
		if _cmp_version(_current_version, _max_upgrade) >= 0:
			_status_label.text = "No compatible upgrade available for v%s." % _current_version
			_notes_rt.text = "[b]Breaking change detected[/b]\n\nLatest version v%s has breaking changes that are incompatible with your current version (v%s).\n\nYour version has reached the maximum upgrade path. Please check GitHub Releases for any newer compatible version.\n\n" % [_latest_version, _current_version] + "[b]Release notes:[/b]\n" + notes
			_upgrade_btn.disabled = true
			_upgrade_btn.text = "No upgrade path"
		else:
			_target_version = _max_upgrade
			_status_label.text = "Latest v%s has breaking changes. Upgrading to compatible v%s instead." % [_latest_version, _max_upgrade]
			_notes_rt.text = "[b]Breaking change detected[/b]\n\nLatest version v%s changes the data format and is incompatible with your current version (v%s).\n\nAuto-upgrading to v%s instead. After that, you can manually upgrade further.\n\n" % [_latest_version, _current_version, _max_upgrade] + "[b]Release notes (v%s):[/b]\n" % _target_version + notes
			_upgrade_btn.disabled = false
			_upgrade_btn.text = "Upgrade to v%s" % _max_upgrade
	else:
		_target_version = _latest_version
		_status_label.text = "A new version is available: v%s" % _latest_version
		_notes_rt.text = "[b]Release notes:[/b]\n" + notes
		_upgrade_btn.disabled = false
		_upgrade_btn.text = "Upgrade to v%s" % _latest_version

	get_ok_button().text = "Close"


## Collect files in addons/gdsql/ that were not just extracted (recursive).
func _collect_extra(dir: DirAccess, prefix: String, extracted: Dictionary, to_delete: Array) -> void:
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if f in [".", "..", ".git"]:
			f = dir.get_next()
			continue
		var rel = "addons/gdsql/" + prefix + f
		if dir.current_is_dir():
			var sub = DirAccess.open("res://" + rel)
			if sub:
				_collect_extra(sub, prefix + f + "/", extracted, to_delete)
		else:
			if not extracted.has(rel):
				to_delete.push_back(rel)
		f = dir.get_next()
	dir.list_dir_end()


## Delete a list of files collected by _collect_extra.
func _delete_collected(to_delete: Array) -> int:
	var n = 0
	for rel in to_delete:
		var abs = ProjectSettings.globalize_path("res://" + rel)
		var dp = DirAccess.open(abs.get_base_dir())
		if dp:
			var err = dp.remove(abs.get_file())
			if err == OK:
				n += 1
			else:
				push_error("Cannot delete file: %s, error: %s" % [rel, error_string(err)])
	return n


## Parse upgrade_ranges from release body and return max version the current ver can reach.
## Format: upgrade_ranges: 0.5.0-0.5.99|0.6.0-999.999.999
func _parse_max_upgrade(body: String, current_ver: String) -> String:
	if body.is_empty():
		return ""
	# Find the line starting with upgrade_ranges:
	var lines = body.split("
")
	var range_line = ""
	for l in lines:
		if l.trim_prefix(" ").trim_prefix("	").begins_with("upgrade_ranges:"):
			range_line = l.trim_prefix(" ").trim_prefix("	").trim_prefix("upgrade_ranges:").strip_edges()
			break
	if range_line.is_empty():
		return ""

	var ranges = range_line.split("|")
	for r in ranges:
		var parts = r.split("-")
		if parts.size() != 2:
			continue
		var from_v = parts[0].strip_edges()
		var to_v = parts[1].strip_edges()
		if _cmp_version(current_ver, from_v) >= 0 and _cmp_version(current_ver, to_v) <= 0:
			return to_v
	return ""


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
		var rel = prefix + f
		if dir.current_is_dir():
			var sub = DirAccess.open("res://" + prefix + f)
			if sub:
				_collect_files(sub, prefix + f + "/", known, result)
		else:
			# Skip auto-generated .translation files
			if f.ends_with(".translation"):
				f = dir.get_next()
				continue
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
	var user_files = _detect_user_files(_target_version)
	
	if not user_files.is_empty():
		var warn = AcceptDialog.new()
		warn.title = "Files Not Part of GDSQL"
		warn.min_size = Vector2(540, 420)
		
		var mc = MarginContainer.new()
		mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		warn.add_child(mc)
		
		var vb = VBoxContainer.new()
		vb.add_theme_constant_override("separation", 15)
		mc.add_child(vb)
		
		var warn_text = "The following files in addons/gdsql/ are not part of the plugin.\nThey may be your custom data:"
		var wl = Label.new()
		wl.text = warn_text
		vb.add_child(wl)
		
		var mc2 = MarginContainer.new()
		mc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_child(mc2)
		
		var sc = ScrollContainer.new()
		mc2.add_child(sc)
		
		var il = ItemList.new()
		il.theme_type_variation = "ItemListSecondary"
		il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		il.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var ft = []
		for uf in user_files:
			ft.push_back(uf)
			il.add_item(uf)
		sc.add_child(il)
		
		var wl2 = Label.new()
		wl2.text = "Do you want to proceed with the upgrade?\nForcing overwrite will erase existing files in the addons/gdsql/ directory."
		vb.add_child(wl2)
		
		var cp = Button.new()
		cp.size_flags_horizontal = Control.SIZE_SHRINK_END
		cp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		cp.text = "Copy list"
		cp.pressed.connect(func():
			DisplayServer.clipboard_set("\n".join(ft))
			cp.text = "Copied!"
		)
		mc2.add_child(cp)
		
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
	var zip_url = "https://github.com/jinyangcruise/GDSQL/releases/download/v%s/gdsql-v%s.zip" % [_target_version, _target_version]
	if zip_url.is_empty():
		_status_label.text = "Error: No download URL found."
		return

	_status_label.text = "Preparing..."
	_upgrade_btn.text = "Downloading..."
	_upgrade_btn.disabled = true

	var body = await _download_with_progress(zip_url)
	if body.is_empty():
		_status_label.text = "Download failed."
		_upgrade_btn.disabled = false
		_upgrade_btn.text = "Retry"
		return

	if not is_inside_tree():
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
	var marker = "addons/gdsql/"
	var extracted = 0
	var extracted_paths = {}
	for fp in zip_files:
		var idx = fp.find(marker)
		if idx < 0:
			continue
		if fp.ends_with("/"):
			continue
		var rel = fp.substr(idx)
		var target = "res://" + rel
		var data = reader.read_file(fp)
		if fp.ends_with(".import"):
			continue
		var d = DirAccess.open("res://")
		if d:
			d.make_dir_recursive(target.get_base_dir())
		var wf = FileAccess.open(target, FileAccess.WRITE)
		if wf:
			wf.store_buffer(data)
			wf.close()
			extracted += 1
			extracted_paths[rel] = true

	reader.close()
	var global_path = ProjectSettings.globalize_path(tmp_path)
	if DirAccess.dir_exists_absolute(global_path):
		var dp = DirAccess.open(tmp_path.get_base_dir())
		if dp:
			dp.remove(tmp_path.get_file())

	# Remove files that belong to an older version but not the target
	var to_delete = []
	var clean_dir = DirAccess.open("res://addons/gdsql/")
	if clean_dir:
		_collect_extra(clean_dir, "", extracted_paths, to_delete)
	var cleaned = _delete_collected(to_delete)

	_download_pct = -2
	_download_size = ""
	_status_label.text = "Upgrade complete! (%d files updated, %d cleaned up) Please restart Godot." % [extracted, cleaned]
	_upgrade_btn.disabled = true
	_upgrade_btn.text = "Done"


func _download_with_progress(url: String) -> PackedByteArray:
	var client = HTTPClient.new()
	var https = url.begins_with("https://")
	var u = url.trim_prefix("https://").trim_prefix("http://")
	var path = "/" + u.substr(u.find("/") + 1)
	var host = u.substr(0, u.find("/"))
	var tls = TLSOptions.client() if https else null
	var err = client.connect_to_host(host, 443 if https else 80, tls)
	if err != OK:
		return PackedByteArray()

	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		client.poll()
		await get_tree().process_frame

	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return PackedByteArray()

	_status_label.text = "Requesting..."
	client.request(HTTPClient.METHOD_GET, path, ["User-Agent: Godot"])
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		await get_tree().process_frame

	var status = client.get_status()
	if status != HTTPClient.STATUS_BODY and status != HTTPClient.STATUS_CONNECTED:
		return PackedByteArray()

	# Follow redirect
	var code = client.get_response_code()
	if code >= 300 and code < 400:
		for h in client.get_response_headers():
			if h.to_lower().begins_with("location:"):
				var loc = h.substr(9).strip_edges()
				_status_label.text = "Redirecting..."
				client.close()
				return await _download_with_progress(loc)

	# Get content length
	var total = 0
	for h in client.get_response_headers():
		if h.to_lower().begins_with("content-length:"):
			total = int(h.substr(15).strip_edges())
			break

	# Read body with progress
	var body = PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		if not is_inside_tree():
			client.close()
			return PackedByteArray()
		client.poll()
		var chunk = client.read_response_body_chunk()
		if chunk.size() == 0:
			await get_tree().process_frame
			continue
		body.append_array(chunk)
		if total > 0:
			_download_pct = int(float(body.size()) / total * 100)
			_download_size = "%s / %s" % [_format_size(body.size()), _format_size(total)]
			_status_label.text = "Downloading... " + str(_download_pct) + "% (" + _download_size + ")"
			_upgrade_btn.text = str(_download_pct) + "%"
		else:
			_download_pct = -1
			_download_size = _format_size(body.size())
			_status_label.text = "Downloading... " + _download_size
			_upgrade_btn.text = _download_size
		await get_tree().process_frame

	client.close()
	return body


func _process(_delta: float) -> void:
	if _download_pct == -2:
		return
	if _download_pct >= 0:
		if _status_label:
			_status_label.text = "Downloading... " + str(_download_pct) + "% (" + _download_size + ")"
		if _upgrade_btn:
			_upgrade_btn.text = str(_download_pct) + "%"
	elif _download_pct == -1 and not _download_size.is_empty():
		if _status_label:
			_status_label.text = "Downloading... " + _download_size
		if _upgrade_btn:
			_upgrade_btn.text = _download_size

func _format_size(b: int) -> String:
	if b < 1024: return "%d B" % b
	if b < 1048576: return "%.1f KB" % (b / 1024.0)
	return "%.1f MB" % (b / 1048576.0)

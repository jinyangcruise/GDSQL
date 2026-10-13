class_name GDSQLConfigFileCache
extends RefCounted

var _entries: Dictionary = { }


func get_or_load(path: String) -> ConfigFile:
	return get_or_load_with_statistics(path).config


func get_or_load_with_statistics(path: String) -> GDSQLConfigFileCacheLoadResult:
	if _entries.has(path):
		return GDSQLConfigFileCacheLoadResult.new(
			_entries[path] as ConfigFile,
			true,
			0,
		)
	var bytes_read := _file_size(path)
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return GDSQLConfigFileCacheLoadResult.new(null, false, bytes_read)
	_entries[path] = config
	return GDSQLConfigFileCacheLoadResult.new(config, false, bytes_read)


func invalidate(path: String) -> void:
	_entries.erase(path)


func invalidate_prefix(path_prefix: String) -> void:
	var normalized := path_prefix.trim_suffix("/") + "/"
	for path: String in _entries.keys():
		if path == path_prefix or path.begins_with(normalized):
			_entries.erase(path)


func flush(path: String) -> Error:
	if not _entries.has(path):
		return OK
	return (_entries[path] as ConfigFile).save(path)


func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	return -1 if file == null else file.get_length()

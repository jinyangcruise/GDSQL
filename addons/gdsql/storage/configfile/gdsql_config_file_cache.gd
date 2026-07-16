class_name GDSQLConfigFileCache
extends RefCounted

var _entries: Dictionary = { }


func get_or_load(path: String) -> ConfigFile:
	if _entries.has(path):
		return _entries[path] as ConfigFile
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return null
	_entries[path] = config
	return config


func invalidate(path: String) -> void:
	_entries.erase(path)


func flush(path: String) -> Error:
	if not _entries.has(path):
		return OK
	return (_entries[path] as ConfigFile).save(path)

class_name GDSQLStorageBackendIds

const CONFIG_FILE := &"configfile"
const PAGED_BINARY := &"paged_binary"
const IN_MEMORY := &"memory"
const BUFFERED := &"buffered"


## Returns every storage backend identifier known by this GDSQL version.
static func get_all() -> Array[StringName]:
	return [CONFIG_FILE, PAGED_BINARY, IN_MEMORY, BUFFERED]


## Reports whether an identifier names a known storage backend.
static func is_valid(backend_id: StringName) -> bool:
	return backend_id in get_all()


## Reports whether a backend can currently be composed by RuntimeFactory.
static func is_implemented(backend_id: StringName) -> bool:
	return backend_id in [CONFIG_FILE, IN_MEMORY]


## Returns the storage choices available to runtime and editor callers.
static func get_implemented() -> Array[StringName]:
	return [CONFIG_FILE, IN_MEMORY]


## Returns a UI-facing label for a known storage backend identifier.
static func get_display_name(backend_id: StringName) -> String:
	match backend_id:
		CONFIG_FILE:
			return "ConfigFile"
		PAGED_BINARY:
			return "Paged binary"
		IN_MEMORY:
			return "In memory"
		BUFFERED:
			return "Buffered"
		_:
			return ""

class_name GDSQLStorageCapabilities
extends RefCounted

var exact_index_lookup: bool
var range_index_lookup: bool


func _init(
		_exact_index_lookup: bool = false,
		_range_index_lookup: bool = false,
) -> void:
	exact_index_lookup = _exact_index_lookup
	range_index_lookup = _range_index_lookup


func supports_exact_index_lookup() -> bool:
	return exact_index_lookup


func supports_range_index_lookup() -> bool:
	return range_index_lookup

@tool
extends ResourceFormatLoader
class_name ResourceFormatLoaderGDMapperGraph

const EXTENSION = "gdmappergraph"
func _get_recognized_extensions() -> PackedStringArray:
	return [EXTENSION]
	
func _get_resource_type(path: String) -> String:
	return "Resource" if path.get_extension() == EXTENSION else ""
	
func _get_resource_script_class(path: String) -> String:
	return "GDMapperGraph" if path.get_extension() == EXTENSION else ""
	
func _handles_type(type: StringName) -> bool:
	return ClassDB.is_parent_class(type, "Resource")
	
@warning_ignore("unused_parameter")
func _load(path: String, original_path: String, use_sub_threads: bool, cache_mode: int) -> Variant:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
		
	var res = GDMapperGraph.new()
	res.load(path)
	return res

@warning_ignore("missing_tool")
extends GDSQL.GBatisEntity
class_name UserExtraEntity

## int. 
var id = NULL

## String. 
var title = NULL

## String. 
var location = NULL

func get_id() -> int:
	return id
	
func set_id(p_id: int):
	id = p_id
	value_changed.emit("id", id)
	
func get_title() -> String:
	return title
	
func set_title(p_title: String):
	title = p_title
	value_changed.emit("title", title)
	
func get_location() -> String:
	return location
	
func set_location(p_location: String):
	location = p_location
	value_changed.emit("location", location)
	

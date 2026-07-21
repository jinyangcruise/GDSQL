@warning_ignore("missing_tool")
extends GDSQL.GBatisEntity
class_name UserEntity

## int. 
var id = NULL

## String. 
var uname = NULL

## int. 
var level = NULL

## UserExtraEntity. 
var user_extra: UserExtraEntity

func get_id() -> int:
	return id
	
func set_id(p_id: int):
	id = p_id
	value_changed.emit("id", id)
	
func get_uname() -> String:
	return uname
	
func set_uname(p_uname: String):
	uname = p_uname
	value_changed.emit("uname", uname)
	
func get_level() -> int:
	return level
	
func set_level(p_level: int):
	level = p_level
	value_changed.emit("level", level)
	
func get_user_extra() -> UserExtraEntity:
	return user_extra
	
func set_user_extra(p_user_extra: UserExtraEntity):
	user_extra = p_user_extra
	value_changed.emit("user_extra", user_extra)
	

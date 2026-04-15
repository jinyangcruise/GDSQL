# Must not be a RefCounted, because this obj is registered in Engine singleton which does not count a reference!
# Must not be a pure Object, because will crash when close game.
## 该对象持有entity对象，确保各个地方在引用同一个主键的对象时，都获取的是同一个对象。
@tool
extends Node
class_name GD

## {class_name => {primary_prop -> {primary_key => entity_object}}}.
## eg. {"TUserEntity": {"id": {1: t_user_entity}}}
var map: Dictionary

## {class_name => {"base": "", "class": "", "icon": icon_path, "language": "", "path": file_path}}
var global_class_path_map: Dictionary
var refresh_interval: float:
	get:
		if Engine.is_editor_hint():
			return 100 # 0.1 second.
		return 3600 # 1 hour.
		
var last_refresh_time: float = 0

func has_entity(p_class, p_primary_prop, p_primary_key) -> bool:
	return map.has(p_class) and map[p_class].has(p_primary_prop) and map[p_class][p_primary_prop].has(p_primary_key)
	
func get_entity(p_class, p_primary_prop, p_primary_key) -> GDSQL.GBatisEntity:
	if has_entity(p_class, p_primary_prop, p_primary_key):
		return map[p_class][p_primary_prop][p_primary_key]
	return null
	
func set_entity(p_class, p_primary_prop, p_primary_key, p_entity):
	if not map.has(p_class):
		map[p_class] = {}
		
	var need_from_other = false
	if not map[p_class].has(p_primary_prop):
		map[p_class][p_primary_prop] = {}
		need_from_other = true
	map[p_class][p_primary_prop][p_primary_key] = p_entity
	
	# 把其他能作为唯一键属性的也同步一下
	for prop in map[p_class]:
		if prop != p_primary_prop:
			# 对方的给自己
			if need_from_other:
				for key in map[p_class][prop]:
					var entity = map[p_class][prop][key]
					var value = entity.get_indexed(p_primary_prop)
					if value == p_primary_key:
						assert(entity == p_entity, "Inner error!")
					else:
						map[p_class][p_primary_prop][value] = entity
						
			# 自己的给对方
			var prop_value = p_entity.get_indexed(prop)
			if map[p_class][prop].has(prop_value):
				assert(map[p_class][prop][prop_value] == p_entity, "Inner error!")
			else:
				map[p_class][prop][prop_value] = p_entity
				
func get_class_path(p_class_name) -> String:
	if global_class_path_map.is_empty() or \
	Time.get_ticks_msec() - last_refresh_time > refresh_interval:
		global_class_path_map.clear()
		for i in ProjectSettings.get_global_class_list():
			global_class_path_map[i.class] = i
		last_refresh_time = Time.get_ticks_msec()
	assert(global_class_path_map.has(p_class_name), "Not found class: %s." % p_class_name)
	return global_class_path_map[p_class_name].path
	
func get_class_base(p_class_name) -> StringName:
	if global_class_path_map.is_empty() or \
	Time.get_ticks_msec() - last_refresh_time > refresh_interval:
		global_class_path_map.clear()
		for i in ProjectSettings.get_global_class_list():
			global_class_path_map[i.class] = i
		last_refresh_time = Time.get_ticks_msec()
	assert(global_class_path_map.has(p_class_name), "Not found class: %s." % p_class_name)
	return global_class_path_map[p_class_name].base

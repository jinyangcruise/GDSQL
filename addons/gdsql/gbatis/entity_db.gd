# Must not be a RefCounted, because this obj is registered in Engine singleton which does not count a reference!
# Must not be a pure Object, because will crash when close game.
## 该对象持有entity对象，确保各个地方在引用同一个主键的对象时，都获取的是同一个对象。
@tool
extends Node
class_name GD
## {class_name => {primary_key => entity_object}}
var map: Dictionary

func has_entity(p_class, p_primary_key) -> bool:
	return map.has(p_class) and map[p_class].has(p_primary_key)
	
func get_entity(p_class, p_primary_key) -> GDSQL.GBatisEntity:
	if map.has(p_class) and map[p_class].has(p_primary_key):
		return map[p_class][p_primary_key]
	return null
	
func set_entity(p_class, p_primary_key, p_entity):
	if not map.has(p_class):
		map[p_class] = {}
	map[p_class][p_primary_key] = p_entity

extends RefCounted

signal value_changed(property, new_val)

static var NULL = RefCounted.new()

func is_all_propeties_set() -> bool:
	for i in (get_script() as GDScript).get_script_property_list():
		if i.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			if is_same(get_indexed(i.name), NULL):
				return false
	return true
	
func is_property_set(property) -> bool:
	return not is_same(get_indexed(property), NULL)
	
func is_properties_set(properties: Array) -> bool:
	for i in properties:
		if is_same(get_indexed(i), NULL):
			return false
	return true

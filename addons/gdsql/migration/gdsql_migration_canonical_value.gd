extends RefCounted
## Internal deterministic representation for schema and migration values.


static func serialize(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(
			func(left: Variant, right: Variant) -> bool:
				return var_to_str(left) < var_to_str(right),
		)
		var entries: Array = []
		for key in keys:
			entries.append([serialize(key), serialize(value[key])])
		return [TYPE_DICTIONARY, entries]
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(serialize(item))
		return [TYPE_ARRAY, items]
	if value is Resource:
		var resource := value as Resource
		return [TYPE_OBJECT, resource.get_class(), resource.resource_path, var_to_str(resource)]
	return [typeof(value), var_to_str(value)]

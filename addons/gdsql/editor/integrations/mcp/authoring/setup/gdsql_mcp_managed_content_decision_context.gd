extends RefCounted
## Agent-facing impact summaries for Managed Content selection and save expectations.


static func package_selection(
	previous: Array[String],
	requested: Array[String],
	active_save: Dictionary,
) -> Dictionary:
	var added := _difference(requested, previous)
	var removed := _difference(previous, requested)
	var changed := not added.is_empty() or not removed.is_empty()
	return {
		"selected_action": "replace_package_selection",
		"changes_effective_content": changed,
		"added_packages": added,
		"removed_packages": removed,
		"requires_cache_rebuild": changed,
		"active_save_before_change": active_save,
		"save_compatibility_after_rebuild": (
			"reinspect_required" if changed else active_save.get("status", "unavailable")
		),
		"updates_save_expectation": false,
		"agent_instruction": (
			"Explain that replacing the package selection changes the effective content set. "
			+ "Rebuild the cache, then inspect the active save against it. Do not replace the "
			+ "save's recorded expectation unless the user separately confirms that action."
		),
	}


static func save_expectation(
	registration: String,
	previous_status: String,
	packages: Array[Dictionary],
	replaces_previous: bool,
) -> Dictionary:
	return {
		"selected_action": (
			"replace_save_expectation" if replaces_previous else "record_save_expectation"
		),
		"registration": registration,
		"previous_status": previous_status,
		"expected_packages": packages,
		"replaces_previous_expectation": replaces_previous,
		"changes_save_rows": false,
		"agent_instruction": (
			"Explain that this records the current effective package fingerprints as the save's "
			+ "future compatibility expectation. It does not migrate or repair save rows."
		),
	}


static func _difference(left: Array[String], right: Array[String]) -> Array[String]:
	var values: Array[String] = []
	for value in left:
		if value not in right:
			values.append(value)
	values.sort()
	return values

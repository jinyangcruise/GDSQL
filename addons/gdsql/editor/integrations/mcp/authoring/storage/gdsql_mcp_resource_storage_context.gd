extends RefCounted
## Agent-facing decision context for Resource-column ownership.


static func describe_intent(intent: Dictionary) -> Array[Dictionary]:
	var decisions: Array[Dictionary] = []
	match String(intent.get("operation", "")):
		"create_table":
			var table := intent.get("table_definition") as GDSQLTableDefinition
			if table != null:
				for column in table.columns:
					_append_column(decisions, column)
		"alter_table":
			for alteration in intent.get("alterations", []):
				if not alteration is GDSQLTableAlteration:
					continue
				if alteration.kind == GDSQLTableAlteration.Kind.ADD_COLUMN:
					_append_column(decisions, alteration.column)
				elif alteration.kind == GDSQLTableAlteration.Kind.SET_RESOURCE_OWNERSHIP:
					_upsert(decisions, alteration.column_name, alteration.resource_ownership)
	return decisions


static func _append_column(
	decisions: Array[Dictionary],
	column: GDSQLColumnDefinition,
) -> void:
	if column != null and column.data_type == TYPE_OBJECT:
		_upsert(decisions, column.name, column.resource_ownership)


static func _upsert(
	decisions: Array[Dictionary],
	column_name: StringName,
	ownership: GDSQLResourceOwnership.Mode,
) -> void:
	for index in decisions.size():
		if decisions[index]["column"] == String(column_name):
			decisions[index] = _describe(column_name, ownership)
			return
	decisions.append(_describe(column_name, ownership))


static func _describe(
	column_name: StringName,
	ownership: GDSQLResourceOwnership.Mode,
) -> Dictionary:
	var selected := GDSQLResourceOwnership.to_id(ownership)
	return {
		"column": String(column_name),
		"selected": String(selected),
		"recommended": "referenced",
		"selection_was_explicit": true,
		"agent_instruction": (
			"Explain this choice before commit. Recommend referenced for existing project or "
			+ "package assets. Choose owned only when the Resource itself is independent row data."
		),
		"options": [
			{
				"id": "referenced",
				"stored_value": "A versioned UID/path locator to an external asset.",
				"best_for": "Imported meshes, textures, audio, scenes, and shared assets.",
				"tradeoffs": (
					"Keeps table files compact and supports explicit deferred loading, but the asset "
					+ "must remain resolvable and projected Resources load eagerly unless deferred execution is requested."
				),
			},
			{
				"id": "owned",
				"stored_value": "The complete independent Resource value serialized with the row.",
				"best_for": "Generated or per-row configuration state without a stable external asset.",
				"tradeoffs": (
					"Produces a self-contained row value, but duplicates Resource data and can substantially "
					+ "increase table size and load cost."
				),
			},
		],
		"owned_choice_needs_attention": ownership == GDSQLResourceOwnership.Mode.OWNED,
		"lazy_loading_is_automatic": false,
	}

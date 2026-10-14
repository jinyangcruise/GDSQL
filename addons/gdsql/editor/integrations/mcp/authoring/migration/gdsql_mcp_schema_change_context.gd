extends RefCounted
## Agent-facing context for choosing direct schema changes or authored history.


static func describe(selected: String, history_count: int) -> Dictionary:
	var history_active := history_count > 0
	return {
		"selected": selected,
		"history_count": history_count,
		"history_active": history_active,
		"direct_change_allowed": not history_active,
		"decision_required": not history_active,
		"agent_instruction": (
			"Explain that direct changes are for initial or disposable development only. "
			+ "Use an authored migration for shared, deployed, or long-lived data. Once migration "
			+ "history starts, every later schema change must continue through that history."
		),
		"options": [
			{
				"id": "direct",
				"best_for": "Initial local prototyping before migration history starts.",
				"tradeoffs": (
					"Changes the current database immediately and creates no reproducible upgrade step."
				),
				"available": not history_active,
			},
			{
				"id": "migration",
				"best_for": "Team projects, durable saves, deployed builds, and reproducible upgrades.",
				"tradeoffs": (
					"Adds immutable ordered history that must be committed and maintained with the schema."
				),
				"available": true,
			},
		],
	}

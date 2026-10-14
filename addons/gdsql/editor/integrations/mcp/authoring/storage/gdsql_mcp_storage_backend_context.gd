extends RefCounted
## Agent-facing decision context for implemented runtime storage policies.


static func describe(backend: StringName, default_applied: bool) -> Dictionary:
	return {
		"selected": String(backend),
		"default_applied": default_applied,
		"agent_instruction": (
			"Keep ConfigFile when the user has not requested a runtime storage policy. "
			+ "Before choosing memory, explain checkpoint timing and obtain confirmation."
		),
		"options": [
			{
				"id": "configfile",
				"runtime_behavior": "Queries and committed mutations use durable table files.",
				"best_for": "Simple persistence and smaller datasets without checkpoint tuning.",
				"durability": "Committed mutations are durable immediately.",
			},
			{
				"id": "memory",
				"runtime_behavior": (
					"The complete durable dataset hydrates into memory when the runtime starts."
				),
				"best_for": "Frequently accessed mutable runtime state that benefits from batched writes.",
				"durability": (
					"Committed mutations remain in memory until a periodic, pause, exit, or explicit checkpoint."
				),
			},
		],
		"requires_checkpoint_management": backend == GDSQLStorageBackendIds.IN_MEMORY,
		"confirmation_required": true,
	}

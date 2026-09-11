class_name GDSQLContentPackageKind
extends RefCounted
## Stable content-package purposes encoded by manifest files.

enum Kind {
	BASE_GAME,
	DLC,
	MOD,
}


static func from_string(value: String) -> int:
	match value.strip_edges().to_lower():
		"base":
			return Kind.BASE_GAME
		"dlc":
			return Kind.DLC
		"mod":
			return Kind.MOD
	return -1


static func get_id(kind: int) -> String:
	match kind:
		Kind.BASE_GAME:
			return "base"
		Kind.DLC:
			return "dlc"
		Kind.MOD:
			return "mod"
	return ""


static func is_valid(kind: int) -> bool:
	return kind in [Kind.BASE_GAME, Kind.DLC, Kind.MOD]

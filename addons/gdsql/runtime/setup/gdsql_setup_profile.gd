class_name GDSQLSetupProfile
extends RefCounted
## Project-selected content composition profile used by setup guidance.

enum Kind {
	UNSELECTED,
	DIRECT,
	MANAGED,
}


static func get_id(profile: Kind) -> StringName:
	match profile:
		Kind.DIRECT:
			return &"direct"
		Kind.MANAGED:
			return &"managed"
	return &""


static func from_id(profile_id: StringName) -> Kind:
	match profile_id:
		&"direct":
			return Kind.DIRECT
		&"managed":
			return Kind.MANAGED
	return Kind.UNSELECTED


static func is_selectable(profile: Kind) -> bool:
	return profile in [Kind.DIRECT, Kind.MANAGED]

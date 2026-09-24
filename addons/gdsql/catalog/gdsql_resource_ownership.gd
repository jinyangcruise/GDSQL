class_name GDSQLResourceOwnership
extends RefCounted
## Declares who owns the value stored by a Resource column.
##
## OWNED values are independent database values. REFERENCED values remain
## project assets and the database stores only a stable locator.

enum Mode {
	OWNED,
	REFERENCED,
}

const OWNED_ID := &"owned"
const REFERENCED_ID := &"referenced"


static func is_valid(mode: Mode) -> bool:
	return mode == Mode.OWNED or mode == Mode.REFERENCED


static func to_id(mode: Mode) -> StringName:
	return REFERENCED_ID if mode == Mode.REFERENCED else OWNED_ID


static func from_id(id: StringName) -> Mode:
	if id == OWNED_ID:
		return Mode.OWNED
	if id == REFERENCED_ID:
		return Mode.REFERENCED
	return -1 as Mode


static func display_name(mode: Mode) -> String:
	return "Referenced" if mode == Mode.REFERENCED else "Owned"

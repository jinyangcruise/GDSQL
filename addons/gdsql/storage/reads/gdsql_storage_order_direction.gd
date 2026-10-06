class_name GDSQLStorageOrderDirection
extends RefCounted

enum Direction { ASCENDING, DESCENDING }


static func is_valid(direction: Direction) -> bool:
	return direction == Direction.ASCENDING or direction == Direction.DESCENDING

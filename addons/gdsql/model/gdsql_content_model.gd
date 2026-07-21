@abstract
class_name GDSQLContentModel
extends GDSQLModel
## Read-only model resolved through the active content database role.

func database_role() -> StringName:
	return GDSQLDatabaseRegistry.CONTENT_ROLE


func access_mode() -> GDSQLModelAccess.Mode:
	return GDSQLModelAccess.Mode.READ_ONLY

## Mutable model resolved through the active save-slot database role.
@abstract
class_name GDSQLSaveModel
extends GDSQLModel

func database_role() -> StringName:
	return GDSQLDatabaseRegistry.SAVE_ROLE


func access_mode() -> GDSQLModelAccess.Mode:
	return GDSQLModelAccess.Mode.READ_WRITE

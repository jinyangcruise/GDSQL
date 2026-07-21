## Mutable model resolved through the project-wide settings database role.
@abstract
class_name GDSQLSettingsModel
extends GDSQLModel

func database_role() -> StringName:
	return GDSQLDatabaseRegistry.SETTINGS_ROLE


func access_mode() -> GDSQLModelAccess.Mode:
	return GDSQLModelAccess.Mode.READ_WRITE

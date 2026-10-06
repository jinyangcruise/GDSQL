@abstract
class_name GDSQLManagedContentConfigurationStore
extends RefCounted
## Storage-independent boundary for managed-content project configuration.

@abstract
func load_configuration() -> GDSQLOperationResult


@abstract
func save_configuration(
		configuration: GDSQLManagedContentConfiguration,
) -> GDSQLOperationResult


func _tr(message: StringName) -> StringName:
	return TranslationServer.get_or_add_domain(&"GDSQL").translate(message)

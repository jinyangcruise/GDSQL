@abstract
class_name GDSQLSetupProfileStore
extends RefCounted
## Storage-independent boundary for the selected project setup profile.

@abstract
func load_profile() -> GDSQLOperationResult


@abstract
func save_profile(profile: GDSQLSetupProfile.Kind) -> GDSQLOperationResult


@abstract
func clear_profile() -> GDSQLOperationResult


func _tr(message: String) -> String:
	return TranslationServer.get_or_add_domain(&"GDSQL").translate(message)

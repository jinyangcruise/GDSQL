@abstract
class_name GDSQLQueryValidator
extends RefCounted

@abstract
func validate(query: GDSQLQuerySpec) -> GDSQLQueryValidationResult


func _tr(message: String) -> String:
	return TranslationServer.get_or_add_domain(&"GDSQL").translate(message)

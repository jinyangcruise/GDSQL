@abstract
class_name GDSQLContentPackageLayerReader
extends RefCounted
## Storage-independent boundary for decoding one package's database layer.

@abstract
func read_layer(
		source: GDSQLContentPackageSource,
		database_name: StringName,
) -> GDSQLOperationResult


func _tr(message: StringName) -> StringName:
	return TranslationServer.get_or_add_domain(&"GDSQL").translate(message)

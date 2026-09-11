class_name GDSQLExampleInventoryEntry
extends "res://examples/runtime/content_save_models/generated/inventory_entry_model_generated.gd"
## User-owned save-model behavior and cross-role relationship declarations.

static func query() -> GDSQLModelQuery:
	return GDSQLModels.query(GDSQLExampleInventoryEntry)


static func find(identity: Variant) -> GDSQLQueryResult:
	return GDSQLModels.find(GDSQLExampleInventoryEntry, identity)


func relationships() -> Array[GDSQLRelationshipDefinition]:
	return [
		GDSQLRelationshipDefinition.belongs_to(
			&"item",
			GDSQLExampleContentItem,
			&"item_id",
		),
	]

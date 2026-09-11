class_name GDSQLExampleContentItem
extends "res://examples/runtime/content_save_models/generated/content_item_model_generated.gd"
## User-owned content-model behavior. The model assistant does not replace this file.

static func query() -> GDSQLModelQuery:
	return GDSQLModels.query(GDSQLExampleContentItem)


static func find(identity: Variant) -> GDSQLQueryResult:
	return GDSQLModels.find(GDSQLExampleContentItem, identity)

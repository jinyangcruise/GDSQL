@abstract
class_name GDSQLExampleInventoryEntryGenerated
extends GDSQLSaveModel
## Generated from the runtime `inventory` table. Regeneration may replace this file.

var id: int
var item_id: StringName
var quantity: int


func table_name() -> StringName:
	return &"inventory"


func primary_key() -> StringName:
	return &"id"

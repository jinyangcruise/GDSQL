@abstract
class_name GDSQLExampleContentItemGenerated
extends GDSQLContentModel
## Generated from the authored `items` table. Regeneration may replace this file.

var id: StringName
var display_name: String


func table_name() -> StringName:
	return &"items"


func primary_key() -> StringName:
	return &"id"

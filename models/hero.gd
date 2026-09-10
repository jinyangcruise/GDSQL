class_name Hero
extends "res://models/generated/hero_model_generated.gd"
## User-owned model behavior. GDSQL never regenerates this file.


static func query() -> GDSQLModelQuery:
	return GDSQLModels.query(Hero)


static func find(identity: Variant) -> GDSQLQueryResult:
	return GDSQLModels.find(Hero, identity)

@tool
extends GBatisMapper
class_name DemoHeroMapper
func select_hero_by_id(v: int) -> DemoHeroEntity: return query("selectHeroById", v)
func select_heroes_by_min_hp(v: int) -> Array: return query("selectHeroesByMinHp", v)
func insert_hero(e: DemoHeroEntity) -> int: return query("insertHero", e)
func update_hero_hp(id_v: int, hp_v: int) -> int: return query("updateHeroHp", id_v, hp_v)
func delete_hero_by_id(v: int) -> int: return query("deleteHeroById", v)

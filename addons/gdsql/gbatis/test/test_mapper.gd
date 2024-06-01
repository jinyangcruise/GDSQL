extends GBatisMapper
class_name TestSkillMapper

func select_skill_by_id(id: int) -> TestSkillEntity:
	return query("select_skill_by_id", id)
	
func select_skill_by_id2(id: int) -> TestSkillEntity:
	return query("select_skill_by_id2", id)
	
func select_skill_list() -> Array[Object]:
	return query("select_skill_list")
	
func select_skill_effect_by_skill_id(id: int) -> TestSkillEffectEntity:
	return query("select_skill_effect_by_skill_id", id)

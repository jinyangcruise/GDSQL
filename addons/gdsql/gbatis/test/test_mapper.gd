extends GBatisMapper
class_name TestSkillMapper

func select_skill_by_id(id: int) -> TestSkillEntity:
	return query("select_skill_by_id", id)
	
func select_skill_by_id2(id: int) -> TestSkillEntity:
	return query("select_skill_by_id2", id)
	
func select_skill_by_id3(id: int) -> TestSkillEntity:
	return query("select_skill_by_id3", id)
	
func select_skill_list() -> Array[Object]:
	return query("select_skill_list")
	
func select_skill_effect_by_skill_id(id: int) -> Array[TestSkillEffectEntity]:
	return query("select_skill_effect_by_skill_id", id)
	
func update_skill(test_skill_entity: TestSkillEntity) -> int:
	return query("update_skill", test_skill_entity)
	
func insert_skill(test_skill_entity: TestSkillEntity) -> int:
	return query("insert_skill", test_skill_entity)
	
func insert_skill2(test_skill_entity: TestSkillEntity) -> int:
	return query("insert_skill2", test_skill_entity)
	
func insert_skill3(map: Dictionary) -> int:
	return query("insert_skill3", map)
	
func insert_skill4(map: Dictionary):
	return query("insert_skill4", map)

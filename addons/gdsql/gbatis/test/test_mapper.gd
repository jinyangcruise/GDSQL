extends GBatisMapper
class_name TestSkillMapper

func select_skill_by_id(id: int) -> TestSkillEntity:
	return query("select_skill_by_id", id)
	
func select_skill_list() -> Array[Object]:
	return query("select_skill_list")

extends GBatisMapper
class_name TestSkillMapper

func select_skill_by_id(id: int) -> TestSkillEntity:
	return query("select_skill_by_id", id)

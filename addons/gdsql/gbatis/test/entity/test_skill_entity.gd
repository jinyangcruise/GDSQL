extends GBatisEntity
class_name TestSkillEntity

var id: int
var skill_name: String
var icon: Texture2D
var desc: String
var max_level: int

var skill_buff: TestSkillBuffEntity
var arr_skill_buff: Array[TestSkillBuffEntity]

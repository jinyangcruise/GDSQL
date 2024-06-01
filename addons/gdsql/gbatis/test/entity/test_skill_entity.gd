extends RefCounted
class_name TestSkillEntity

var id: int
var skill_name: String
var icon: Texture2D
var desc: String
var max_level: int

var skill_effect: TestSkillEffectEntity
var arr_skill_effect: Array[TestSkillEffectEntity]

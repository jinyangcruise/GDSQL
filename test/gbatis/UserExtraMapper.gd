@tool
extends GBatisMapper
class_name UserExtraMapper

func select_user_extra_by_id(id: int) -> UserExtraEntity:
	return query("select_user_extra_by_id", id)
	
func select_user_extra(userExtra: UserExtraEntity) -> UserExtraEntity:
	return query("select_user_extra", userExtra)
	
func select_user_extra_list(userExtra: UserExtraEntity) -> Array[UserExtraEntity]:
	return query("select_user_extra_list", userExtra)
	
func update_user_extra(userExtra: UserExtraEntity) -> int:
	return query("update_user_extra", userExtra)
	
func insert_user_extra(userExtra: UserExtraEntity) -> int:
	return query("insert_user_extra", userExtra)
	
func delete_user_extra_by_id(id: int) -> int:
	return query("delete_user_extra_by_id", id)
	

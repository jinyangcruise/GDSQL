@tool
extends GBatisMapper
class_name UserMapper

func select_user_by_id(id: int) -> UserEntity:
	return query("select_user_by_id", id)
	
func select_user(user: UserEntity) -> UserEntity:
	return query("select_user", user)
	
func select_user_list(user: UserEntity) -> Array[UserEntity]:
	return query("select_user_list", user)
	
func select_user_extra_by_id(id: int) -> UserExtraEntity:
	return query("select_user_extra_by_id", id)
	
func update_user(user: UserEntity) -> int:
	return query("update_user", user)
	
func insert_user(user: UserEntity) -> int:
	return query("insert_user", user)
	
func delete_user_by_id(id: int) -> int:
	return query("delete_user_by_id", id)
	

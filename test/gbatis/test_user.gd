extends GdUnitTestSuite

const user_mapper: UserMapper = preload("res://test/gbatis/UserMapper.tres")
const user_extra_mapper: UserExtraMapper = preload("res://test/gbatis/UserExtraMapper.tres")


func before_test() -> void:
	var admin_dao = GDSQL.AdminDao.new()
	await admin_dao.truncate_table("Test", "user")
	await admin_dao.truncate_table("Test", "user_extra")


func after_test() -> void:
	var admin_dao = GDSQL.AdminDao.new()
	await admin_dao.truncate_table("Test", "user")
	await admin_dao.truncate_table("Test", "user_extra")


## 测试： Mapper INSERT with entity
func test_mapper_insert_with_entity() -> void:
	var user_entity: UserEntity = UserEntity.new()
	user_entity.set_level(6)
	user_entity.set_uname("Jack")
	
	assert_int(user_mapper.insert_user(user_entity)).is_equal(1)
	assert_int(user_entity.get_id()).is_equal(1)

	var user_entity2: UserEntity = user_mapper.select_user_by_id(1)
	printt(user_entity2)
	assert_int(user_entity2.get_id()).is_equal(1)
	assert_str(user_entity2.get_uname()).is_equal("Jack")
	assert_int(user_entity2.get_level()).is_equal(6)
	assert_object(user_entity2.get_user_extra()).is_null()

	var user_extra_entity: UserExtraEntity = UserExtraEntity.new()
	user_extra_entity.set_id(user_entity.get_id())
	user_extra_entity.set_title("CEO")
	user_extra_entity.set_location("Earth")
	
	assert_int(user_extra_mapper.insert_user_extra(user_extra_entity)).is_equal(1)
	
	var user_entity3: UserEntity = user_mapper.select_user_by_id(1)
	printt(user_entity3)
	assert_int(user_entity3.get_id()).is_equal(1)
	assert_str(user_entity3.get_uname()).is_equal("Jack")
	assert_int(user_entity3.get_level()).is_equal(6)
	assert_object(user_entity3.get_user_extra()).is_not_null()
	assert_str(user_entity3.get_user_extra().get_title()).is_equal("CEO")
	assert_str(user_entity3.get_user_extra().get_location()).is_equal("Earth")

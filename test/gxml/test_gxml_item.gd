extends GdUnitTestSuite

## Tests for GDSQL.GXMLItem.to_dict() and XML loading via load().

const TEST_DIR = "user://test_gdsql_gxml/"
const TEST_XML_FILE = TEST_DIR + "test.xml"

func before_test() -> void:
	var dir_abs = ProjectSettings.globalize_path(TEST_DIR)
	if not DirAccess.dir_exists_absolute(dir_abs):
		DirAccess.make_dir_recursive_absolute(dir_abs)


# ============================================================================
# GXMLItem.to_dict
# ============================================================================

func _make_item(name: String, attrs: Dictionary = {}, content: Array = []) -> GDSQL.GXMLItem:
	var item = GDSQL.GXMLItem.new()
	item.name = name
	item.attrs = attrs
	item.content = content
	return item

## 测试: 简单元素转字典
func test_item_to_dict_simple() -> void:
	var item = _make_item("root", {"a": "1"})
	var d = item.to_dict(GXML.TO_DICT_FLAG.NONE)
	assert_str(d["name"]).is_equal("root")
	assert_str(d["attrs"]["a"]).is_equal("1")


## 测试: 带文本内容的元素
func test_item_to_dict_with_text() -> void:
	var item = _make_item("tag", {}, ["hello"])
	var d = item.to_dict(GXML.TO_DICT_FLAG.NONE)
	assert_str(d["content"][0]).is_equal("hello")


## 测试: 带子元素
func test_item_to_dict_nested() -> void:
	var child = _make_item("child", {}, ["text"])
	var item = _make_item("root", {}, [child])
	var d = item.to_dict(GXML.TO_DICT_FLAG.NONE)
	assert_str(d["content"][0]["name"]).is_equal("child")


## 测试: IGNORE_PLAIN_BLANK_TEXT 忽略空白
func test_item_to_dict_ignore_blank() -> void:
	var item = _make_item("r", {}, ["  ", "data"])
	var d = item.to_dict(GXML.TO_DICT_FLAG.IGNORE_PLAIN_BLANK_TEXT)
	assert_int(d["content"].size()).is_equal(1)
	assert_str(d["content"][0]).is_equal("data")


## 测试: COMBINE_ADJACENT_TEXTS 合并相邻文本
func test_item_to_dict_combine_texts() -> void:
	var item = _make_item("r", {}, ["a", "b"])
	var d = item.to_dict(GXML.TO_DICT_FLAG.COMBINE_ADJACENT_TEXTS)
	assert_int(d["content"].size()).is_equal(1)
	assert_str(d["content"][0]).is_equal("ab")


## 测试: NORMAL 组合标志
func test_item_to_dict_normal() -> void:
	var item = _make_item("r", {}, ["  ", "x", "y"])
	var d = item.to_dict(GXML.TO_DICT_FLAG.NORMAL)
	assert_int(d["content"].size()).is_equal(1)
	assert_str(d["content"][0]).is_equal("xy")


## 测试: CDATA 索引保留
func test_item_to_dict_cdata_index() -> void:
	var item = _make_item("r", {}, ["before", "cdata_content"])
	item.cdata_indexes = [1]
	var d = item.to_dict(GXML.TO_DICT_FLAG.NONE)
	assert_int(d["cdata_indexes"].size()).is_equal(1)
	assert_int(d["cdata_indexes"][0]).is_equal(1)



# ============================================================================
# XML file loading via load()
# ============================================================================

## 测试: load() 加载 XML 文件
func test_load_xml_file() -> void:
	_write_test_xml("<root><item id='1'>hello</item></root>")
	var gxml = load(TEST_XML_FILE) as GXML
	assert_that(gxml).is_not_null()
	assert_str(gxml.root_item.name).is_equal("root")
	var child = gxml.root_item.content[0] as GDSQL.GXMLItem
	assert_str(child.name).is_equal("item")
	assert_str(child.attrs["id"]).is_equal("1")
	assert_str(child.content[0]).is_equal("hello")


## 测试: load() 含属性
func test_load_xml_with_attrs() -> void:
	_write_test_xml("<cfg name='test' version='2'></cfg>")
	var gxml = load(TEST_XML_FILE) as GXML
	assert_str(gxml.root_item.name).is_equal("cfg")
	assert_str(gxml.root_item.attrs["name"]).is_equal("test")


## 测试: load() 多层嵌套
func test_load_xml_nested() -> void:
	_write_test_xml("<a><b><c>deep</c></b></a>")
	var gxml = load(TEST_XML_FILE) as GXML
	var b = gxml.root_item.content[0] as GDSQL.GXMLItem
	var c = b.content[0] as GDSQL.GXMLItem
	assert_str(c.content[0]).is_equal("deep")


## 测试: load() 多个兄弟元素
func test_load_xml_siblings() -> void:
	_write_test_xml("<root><x>1</x><x>2</x></root>")
	var gxml = load(TEST_XML_FILE) as GXML
	assert_int(gxml.root_item.content.size()).is_equal(2)


## 测试: load() + to_dict 完整流程
func test_load_then_to_dict() -> void:
	_write_test_xml("<data><item id='1'>value</item></data>")
	var gxml = load(TEST_XML_FILE) as GXML
	var d = gxml.to_dict(GXML.TO_DICT_FLAG.NONE)
	assert_str(d["name"]).is_equal("data")
	assert_str(d["content"][0]["content"][0]).is_equal("value")


# ============================================================================
# Helpers
# ============================================================================

func _write_test_xml(content: String) -> void:
	var f = FileAccess.open(TEST_XML_FILE, FileAccess.WRITE)
	f.store_string(content)
	f.close()

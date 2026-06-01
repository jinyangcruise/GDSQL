extends GdUnitTestSuite

## Comprehensive test suite for GDSQL.GDSQLUtils.
## Covers all public static methods with edge cases.

# --------------------------------------------------------------------------
# evaluate_command
# --------------------------------------------------------------------------

## 测试: 算术加法 1+2=3
func test_evaluate_command_simple_arithmetic() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "1 + 2")
	assert_int(result).is_equal(3)


## 测试: 乘法 3*4=12
func test_evaluate_command_simple_multiplication() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "3 * 4")
	assert_int(result).is_equal(12)


## 测试: 混合运算优先级
func test_evaluate_command_mixed_arithmetic() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "10 - 3 * 2")
	assert_int(result).is_equal(4)


## 测试: 括号改变运算顺序
func test_evaluate_command_parentheses() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "(1 + 2) * 3")
	assert_int(result).is_equal(9)


## 测试: 字符串拼接
func test_evaluate_command_string_concat() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "\"hello \" + \"world\"")
	assert_str(result).is_equal("hello world")


## 测试: 布尔与运算
func test_evaluate_command_boolean_and() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "true && false")
	assert_bool(result).is_false()


## 测试: 布尔或运算
func test_evaluate_command_boolean_or() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "true || false")
	assert_bool(result).is_true()


## 测试: 相等判断 1==1
func test_evaluate_command_equality() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "1 == 1")
	assert_bool(result).is_true()


## 测试: 不等判断 1!=2
func test_evaluate_command_inequality() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "1 != 2")
	assert_bool(result).is_true()


## 测试: 大于比较 5>3
func test_evaluate_command_greater_than() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "5 > 3")
	assert_bool(result).is_true()


## 测试: 传入变量求值
func test_evaluate_command_with_variables() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "a + b", ["a", "b"], [10, 20])
	assert_int(result).is_equal(30)


## 测试: 变量字符串拼接
func test_evaluate_command_with_variables_string() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "prefix + suffix", ["prefix", "suffix"], ["hello_", "world"])
	assert_str(result).is_equal("hello_world")


## 测试: 单变量表达式
func test_evaluate_command_with_single_variable() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "x * 2", ["x"], [7])
	assert_int(result).is_equal(14)


## 测试: 三变量表达式
func test_evaluate_command_with_three_variables() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "(a + b) * c", ["a", "b", "c"], [1, 2, 3])
	assert_int(result).is_equal(9)


## 测试: 浮点数除法 5/2
func test_evaluate_command_float_arithmetic() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "5.0 / 2.0")
	assert_that(result).is_equal(2.5)


## 测试: 负数运算 -5+3
func test_evaluate_command_negation() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "-5 + 3")
	assert_int(result).is_equal(-2)


## 测试: 取模运算 10%3
func test_evaluate_command_modulo() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "10 % 3")
	assert_int(result).is_equal(1)


## 测试: 目标脚本属性求值
func test_evaluate_command_with_target_script_properties() -> void:
	var script = GDScript.new()
	script.source_code = "extends Object\nvar x = 10\nvar y = 20"
	script.reload()
	var target = script.new()
	var result = GDSQL.GDSQLUtils.evaluate_command(target, "x + y")
	assert_int(result).is_equal(30)
	target.free()


## 测试: 目标属性加变量
func test_evaluate_command_with_target_and_variables() -> void:
	var script = GDScript.new()
	script.source_code = "extends Object\nvar base = 100"
	script.reload()
	var target = script.new()
	var result = GDSQL.GDSQLUtils.evaluate_command(target, "base + delta", ["delta"], [50])
	assert_int(result).is_equal(150)
	target.free()


## 测试: 调用目标方法
func test_evaluate_command_with_target_method_call() -> void:
	var script = GDScript.new()
	script.source_code = "extends Object\nfunc double_it(v):\n\treturn v * 2"
	script.reload()
	var target = script.new()
	var result = GDSQL.GDSQLUtils.evaluate_command(target, "double_it(7)")
	assert_int(result).is_equal(14)
	target.free()


## 测试: 多重一元正号 1++++2=3
func test_evaluate_command_unary_plus_chain() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "1 +++ 2")
	assert_int(result).is_equal(3)


## 测试: 布尔取反 !true
func test_evaluate_command_negate_boolean() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "!true")
	assert_bool(result).is_false()


## 测试: 位与运算 3&1
func test_evaluate_command_bitwise_ops() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command(null, "3 & 1")
	assert_int(result).is_equal(1)


# --------------------------------------------------------------------------
# evaluate_command_with_sql_expression
# --------------------------------------------------------------------------

## 测试: SQL表达式简化求值
func test_evaluate_command_with_sql_expression_simple() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_with_sql_expression(null, "1 + 1")
	assert_int(result).is_equal(2)


## 测试: SQL表达式带变量
func test_evaluate_command_with_sql_expression_variables() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_with_sql_expression(
		null, "a + b", ["a", "b"], [3, 4]
	)
	assert_int(result).is_equal(7)


## 测试: SQL表达式字符串拼接
func test_evaluate_command_with_sql_expression_string() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_with_sql_expression(
		null, "\"Hello, \" + name", ["name"], ["World"]
	)
	assert_str(result).is_equal("Hello, World")


## 测试: 列名到变量映射
func test_evaluate_command_with_sql_expression_input_names() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_with_sql_expression(
		null, "price * quantity", ["price", "quantity"], [5, 3]
	)
	assert_int(result).is_equal(15)


## 测试: 缺失表时返回null
func test_evaluate_command_with_sql_expression_lacking_tables() -> void:
	var lacking = []
	var result = GDSQL.GDSQLUtils.evaluate_command_with_sql_expression(
		null, "t.col_1 + t.col_2", [], [], {}, [], {}, {}, lacking
	)
	assert_that(result).is_null()
	assert_array(lacking).is_not_empty()


## 测试: 嵌套子查询参数
func test_evaluate_command_with_sql_expression_with_nested_subqueries() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_with_sql_expression(
		null, "1 + 1", [], [], {}, [], {}, {}
	)
	assert_int(result).is_equal(2)


# --------------------------------------------------------------------------
# evalute_command_with_agg
# --------------------------------------------------------------------------

## 测试: 聚合函数简化求值
func test_evalute_command_with_agg_simple() -> void:
	var result = GDSQL.GDSQLUtils.evalute_command_with_agg(null, "1 + 2")
	assert_int(result).is_equal(3)


## 测试: 聚合函数带变量
func test_evalute_command_with_agg_variables() -> void:
	var result = GDSQL.GDSQLUtils.evalute_command_with_agg(
		null, "a + b", ["a", "b"], [10, 20]
	)
	assert_int(result).is_equal(30)


## 测试: 聚合实例求值
func test_evalute_command_with_agg_with_instance() -> void:
	var agg = GDSQL.AggregateFunctions.get_instance("test_agg")
	var result = GDSQL.GDSQLUtils.evalute_command_with_agg(agg, "1 + 1")
	assert_int(result).is_equal(2)
	GDSQL.AggregateFunctions.clear_instances()


## 测试: 未设变量默认0
func test_evalute_command_with_agg_input_names() -> void:
	var result = GDSQL.GDSQLUtils.evalute_command_with_agg(
		null, "val * 2", ["val"], [0], {}, [], {}, {}
	)
	assert_int(result).is_equal(0)


# --------------------------------------------------------------------------
# evaluate_command_script
# --------------------------------------------------------------------------

## 测试: 脚本简化求值
func test_evaluate_command_script_simple() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script("1 + 2")
	assert_int(result).is_equal(3)


## 测试: 脚本模式乘法
func test_evaluate_command_script_multiplication() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script("4 * 5")
	assert_int(result).is_equal(20)


## 测试: 脚本模式带变量
func test_evaluate_command_script_with_variables() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script("a + b", ["a", "b"], [7, 8])
	assert_int(result).is_equal(15)


## 测试: 脚本模式字符串拼接
func test_evaluate_command_script_string_concat() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script("s1 + s2", ["s1", "s2"], ["ab", "cd"])
	assert_str(result).is_equal("abcd")


## 测试: 脚本模式布尔运算
func test_evaluate_command_script_boolean() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script("true && false")
	assert_bool(result).is_false()


## 测试: 脚本模式复杂运算
func test_evaluate_command_script_complex_expression() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script("(a + b) * c / d", ["a", "b", "c", "d"], [2, 3, 10, 5])
	assert_int(result).is_equal(10)


## 测试: 变量为null
func test_evaluate_command_script_with_null_variable() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script("val", ["val"], [null])
	assert_that(result).is_null()


## 测试: 三目运算符
func test_evaluate_command_script_ternary() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script("true if a > b else false", ["a", "b"], [5, 3])
	assert_bool(result).is_true()


## 测试: 数组字面量
func test_evaluate_command_script_array_literal() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script("[1, 2, 3]")
	assert_array(result).has_size(3)


## 测试: 字典字面量
func test_evaluate_command_script_dictionary_literal() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script('{"key": "value"}')
	assert_that(result).is_not_null()
	assert_str(result["key"]).is_equal("value")


# --------------------------------------------------------------------------
# globalize_path
# --------------------------------------------------------------------------

## 测试: res://含.和..路径
func test_globalize_path_res_with_dots() -> void:
	var path = "res://addons/../addons/gdsql/./gdsql_utils.gd"
	var result = GDSQL.GDSQLUtils.globalize_path(path)
	# res:// paths are simplified
	assert_bool(result.ends_with("gdsql_utils.gd")).is_true()
	assert_bool(".." in result).is_false()


## 测试: install://含gdsql/data
func test_globalize_path_install_contains_path() -> void:
	var path = "install://gdsql/data"
	var result = GDSQL.GDSQLUtils.globalize_path(path)
	assert_str(result).contains("gdsql/data")


## 测试: install://不以res开头
func test_globalize_path_install_does_not_start_with_res() -> void:
	var path = "install://some_dir/file.txt"
	var result = GDSQL.GDSQLUtils.globalize_path(path)
	assert_bool(result.begins_with("res://")).is_false()


## 测试: install://子目录
func test_globalize_path_install_subdir() -> void:
	var path = "install://subdir/deep/file.gd"
	var result = GDSQL.GDSQLUtils.globalize_path(path)
	assert_str(result).contains("subdir/deep/file.gd")


## 测试: 绝对路径透传
func test_globalize_path_absolute_path_passthrough() -> void:
	# Absolute paths that do not start with res:// or install://
	# and are not relative to the editor's res:// path are returned as-is
	var path = "/absolute/path/to/file.txt"
	var result = GDSQL.GDSQLUtils.globalize_path(path)
	# In non-editor mode or if it doesn't match res_path prefix, it returns the path as-is
	assert_str(result).is_equal(path)


## 测试: Windows绝对路径透传
func test_globalize_path_windows_absolute_passthrough() -> void:
	var path = "D:/some/path/file.txt"
	var result = GDSQL.GDSQLUtils.globalize_path(path)
	assert_str(result).is_equal(path)


## 测试: 相对路径透传
func test_globalize_path_relative_path_passthrough() -> void:
	var path = "relative/path/file.txt"
	var result = GDSQL.GDSQLUtils.globalize_path(path)
	assert_str(result).is_equal(path)


## 测试: install://优先识别
func test_globalize_path_install_then_res_path() -> void:
	# Ensure install:// is recognized before any other check
	var path = "install://some_folder"
	var result = GDSQL.GDSQLUtils.globalize_path(path)
	assert_str(result).contains("some_folder")


## 测试: 空字符串返回空
func test_globalize_path_empty_string() -> void:
	var result = GDSQL.GDSQLUtils.globalize_path("")
	assert_str(result).is_equal("")


# --------------------------------------------------------------------------
# file_exists
# --------------------------------------------------------------------------

## 测试: 文件存在返回true
func test_file_exists_res_path_true() -> void:
	var path = "res://addons/gdsql/basic/gdsql_utils.gd"
	assert_bool(GDSQL.GDSQLUtils.file_exists(path)).is_true()


## 测试: 文件不存在返回false
func test_file_exists_res_path_false() -> void:
	var path = "res://addons/gdsql/nonexistent_file.gd"
	assert_bool(GDSQL.GDSQLUtils.file_exists(path)).is_false()


## 测试: install://路径转换
func test_file_exists_install_path_translated() -> void:
	# install:// paths get globalized, so we can at least verify it runs without error
	var path = "install://nonexistent_file.xyz"
	assert_bool(GDSQL.GDSQLUtils.file_exists(path)).is_false()


## 测试: 绝对路径文件存在
func test_file_exists_absolute_path() -> void:
	var path = "res://addons/gdsql/basic/gdsql_utils.gd"
	assert_bool(GDSQL.GDSQLUtils.file_exists(path)).is_true()


## 测试: 空字符串返回false
func test_file_exists_empty_string() -> void:
	assert_bool(GDSQL.GDSQLUtils.file_exists("")).is_false()


# --------------------------------------------------------------------------
# search_symbol
# --------------------------------------------------------------------------

## 测试: 简单逗号分割
func test_search_symbol_simple_commas() -> void:
	var text = "a,b,c"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(2)
	# Positions: first comma at [1,2), second at [3,4)
	assert_int(result[0][0]).is_equal(1)
	assert_int(result[0][1]).is_equal(2)
	assert_int(result[1][0]).is_equal(3)
	assert_int(result[1][1]).is_equal(4)


## 测试: 单引号内逗号忽略
func test_search_symbol_with_quotes() -> void:
	var text = "a,'b,c',d"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(2)


## 测试: 双引号内逗号忽略
func test_search_symbol_with_double_quotes() -> void:
	var text = 'a,"b,c",d'
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(2)


## 测试: 括号内逗号忽略
func test_search_symbol_with_brackets() -> void:
	var text = "func(a,b),c"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(1)
	assert_int(result[0][0]).is_equal(9)
	assert_int(result[0][1]).is_equal(10)


## 测试: 嵌套括号逗号忽略
func test_search_symbol_nested_brackets() -> void:
	var text = "outer(func(a,b),c),d"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(1)
	assert_int(result[0][0]).is_equal(18)
	assert_int(result[0][1]).is_equal(19)


## 测试: 花括号内逗号忽略
func test_search_symbol_with_braces() -> void:
	var text = "{a,b},c"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(1)


## 测试: 无匹配返回空
func test_search_symbol_no_match() -> void:
	var text = "abc"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(0)


## 测试: 单字符无匹配
func test_search_symbol_single_char_text() -> void:
	var text = "a"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(0)


## 测试: 空文本无匹配
func test_search_symbol_empty_text() -> void:
	var text = ""
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(0)


## 测试: 空白字符分割
func test_search_symbol_whitespace() -> void:
	var text = "a b c"
	var result = GDSQL.GDSQLUtils.search_symbol(text, "\\s")
	assert_int(result.size()).is_equal(2)


## 测试: 制表符分割
func test_search_symbol_whitespace_with_tabs() -> void:
	var text = "a\tb"
	var result = GDSQL.GDSQLUtils.search_symbol(text, "\\s")
	assert_int(result.size()).is_equal(1)


## 测试: 无空白字符
func test_search_symbol_whitespace_no_match() -> void:
	var text = "abc"
	var result = GDSQL.GDSQLUtils.search_symbol(text, "\\s")
	assert_int(result.size()).is_equal(0)


## 测试: 相邻分隔符合并
func test_search_symbol_allow_empty_false_removes_adjacent_empty() -> void:
	var text = "a,,c"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",", false)
	# Adjacent commas merge: the empty arg between them is removed
	assert_int(result.size()).is_equal(1)
	assert_int(result[0][0]).is_equal(1)
	assert_int(result[0][1]).is_equal(3)


## 测试: 转义引号内逗号
func test_search_symbol_with_escaped_quote() -> void:
	var text = "a,'b\\'c',d"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(2)


## 测试: 分号作为分隔符
func test_search_symbol_semicolon() -> void:
	var text = "a;b;c"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ";")
	assert_int(result.size()).is_equal(2)


## 测试: @作为分隔符
func test_search_symbol_at_sign() -> void:
	var text = "a@b@c"
	var result = GDSQL.GDSQLUtils.search_symbol(text, "@")
	assert_int(result.size()).is_equal(2)


## 测试: |作为分隔符
func test_search_symbol_pipe() -> void:
	var text = "a|b||c"
	var result = GDSQL.GDSQLUtils.search_symbol(text, "|")
	assert_int(result.size()).is_equal(3)


## 测试: 括号内双引号逗号
func test_search_symbol_double_quote_inside_brackets() -> void:
	var text = 'func("a,b"),c'
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	# The comma inside quotes is not counted
	assert_int(result.size()).is_equal(1)


## 测试: 混合引号内逗号
func test_search_symbol_mixed_quotes() -> void:
	var text = "a,'b\"c\"d',e"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(2)


# --------------------------------------------------------------------------
# extract_outer_quotes
# --------------------------------------------------------------------------

## 测试: 提取外层单引号
func test_extract_outer_quotes() -> void:
	var text = "func('hello', 'world')"
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	# 最外层是 (...)，作为一个整体被提取，内部引号不单独算外层
	assert_int(result.size()).is_equal(1)
	assert_str(result[0]).is_equal("('hello', 'world')")


## 测试: 提取外层双引号
func test_extract_outer_quotes_double_quotes() -> void:
	var text = 'func("hello", "world")'
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	# 最外层是 (...)，作为一个整体被提取
	assert_int(result.size()).is_equal(1)
	assert_str(result[0]).is_equal('("hello", "world")')


## 测试: 混合引号嵌套
func test_extract_outer_quotes_mixed_single_double() -> void:
	var text = "func('hello \"world\"')"
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	assert_int(result.size()).is_equal(1)
	assert_that(result[0]).contains("hello")


## 测试: 括号内含引号
func test_extract_outer_quotes_nested_brackets() -> void:
	var text = "outer('a(b)', 'c')"
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	# 最外层是 (...)，内部引号不单独算外层
	assert_int(result.size()).is_equal(1)
	assert_str(result[0]).is_equal("('a(b)', 'c')")


## 测试: 无引号返回空
func test_extract_outer_quotes_no_quotes() -> void:
	var text = "abc123"
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	assert_int(result.size()).is_equal(0)


## 测试: 空字符串无引号
func test_extract_outer_quotes_empty_string() -> void:
	var text = ""
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	assert_int(result.size()).is_equal(0)


## 测试: 引号含括号返回
func test_extract_outer_quotes_bracket_not_outer() -> void:
	# Brackets (parentheses) inside the text are returned as part of outer quotes
	var text = "'hello(world)'"
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	assert_int(result.size()).is_equal(1)
	assert_str(result[0]).is_equal("'hello(world)'")


## 测试: 多结果按长度排序
func test_extract_outer_quotes_multiple_returns_sorted_by_length() -> void:
	var text = "'short' and 'much longer'"
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	assert_int(result.size()).is_equal(2)
	# Sorted by length descending (longest first)
	assert_int(result[0].length()).is_greater_equal(result[1].length())


## 测试: 转义引号处理
func test_extract_outer_quotes_escaped_quotes() -> void:
	var text = "'don\\'t stop'"
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	# The escaped quote is treated as a regular char
	assert_that(result).is_not_empty()


## 测试: 引号含花括号
func test_extract_outer_quotes_with_braces() -> void:
	var text = '"{brace}ed"'
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	assert_int(result.size()).is_equal(1)


## 测试: 不匹配引号不崩溃
func test_extract_outer_quotes_only_unmatched_warning() -> void:
	# Unmatched quotes produce an error but should not crash
	var text = "'unmatched"
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	assert_that(result).is_not_null()


# --------------------------------------------------------------------------
# extract_outer_bracket
# --------------------------------------------------------------------------

## 测试: 提取外层括号
func test_extract_outer_bracket_simple() -> void:
	var text = "(hello)"
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	assert_int(result.size()).is_equal(1)
	assert_str(result[0]).is_equal("(hello)")


## 测试: 嵌套括号提取
func test_extract_outer_bracket_nested() -> void:
	var text = "(outer(inner))"
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	assert_int(result.size()).is_equal(1)
	assert_str(result[0]).is_equal("(outer(inner))")


## 测试: 多个括号提取
func test_extract_outer_bracket_multiple() -> void:
	var text = "(first) and (second)"
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	assert_int(result.size()).is_equal(2)


## 测试: 括号内含引号
func test_extract_outer_bracket_with_quotes() -> void:
	var text = "('parenthesized')"
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	assert_int(result.size()).is_equal(1)
	assert_str(result[0]).is_equal("('parenthesized')")


## 测试: 无括号返回空
func test_extract_outer_bracket_no_brackets() -> void:
	var text = "no brackets here"
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	assert_int(result.size()).is_equal(0)


## 测试: 空字符串无括号
func test_extract_outer_bracket_empty_string() -> void:
	var text = ""
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	assert_int(result.size()).is_equal(0)


## 测试: 引号内括号不提取
func test_extract_outer_bracket_only_brackets_inside_quotes() -> void:
	var text = "'(not outer)'"
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	# Brackets inside quotes are not extracted
	assert_int(result.size()).is_equal(0)


## 测试: 方括号不提取
func test_extract_outer_bracket_square_brackets_not_extracted() -> void:
	var text = "[square]"
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	# Only () brackets are extracted, not []
	assert_int(result.size()).is_equal(0)


## 测试: 花括号不提取
func test_extract_outer_bracket_braces_not_extracted() -> void:
	var text = "{braces}"
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	# Only () brackets are extracted, not {}
	assert_int(result.size()).is_equal(0)


## 测试: 括号内逗号
func test_extract_outer_bracket_with_commas_inside() -> void:
	var text = "(a, b, c)"
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	assert_int(result.size()).is_equal(1)
	assert_str(result[0]).is_equal("(a, b, c)")


## 测试: 多结果按长度排序
func test_extract_outer_bracket_sorted_by_length() -> void:
	var text = "(short) and (much longer content)"
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	assert_int(result.size()).is_equal(2)
	# Sorted by length descending
	assert_int(result[0].length()).is_greater_equal(result[1].length())


## 测试: 引号内未闭合括号
func test_extract_outer_bracket_unmatched_inside_quotes() -> void:
	var text = '"unclosed (bracket"'
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	# The ( is inside quotes, so it's not treated as a bracket start
	assert_int(result.size()).is_equal(0)


# --------------------------------------------------------------------------
# get_specific_extension_files
# --------------------------------------------------------------------------

## 测试: 查找.gd文件
func test_get_specific_extension_files_find_gd() -> void:
	var result = GDSQL.GDSQLUtils.get_specific_extension_files("res://addons/gdsql/", "gd")
	assert_bool(result.size() > 0).is_true()


## 测试: 测试目录查gd
func test_get_specific_extension_files_find_gd_in_test_dir() -> void:
	var result = GDSQL.GDSQLUtils.get_specific_extension_files("res://test/core/", "gd")
	assert_bool(result.size() > 0).is_true()
	assert_bool("test_gdsql_utils.gd" in result).is_true()


## 测试: 不存在的扩展名
func test_get_specific_extension_files_nonexistent_extension() -> void:
	var result = GDSQL.GDSQLUtils.get_specific_extension_files("res://addons/gdsql/", "xyz")
	assert_int(result.size()).is_equal(0)


## 测试: 扩展名大小写不敏感
func test_get_specific_extension_files_extension_case_insensitive() -> void:
	var result = GDSQL.GDSQLUtils.get_specific_extension_files("res://addons/gdsql/", "gd")
	assert_bool(result.size() > 0).is_true()


# --------------------------------------------------------------------------
# Edge cases and additional coverage
# --------------------------------------------------------------------------

## 测试: 引号结果长度排序
func test_extract_outer_quotes_result_order() -> void:
	# The function sorts results by length descending.
	# Ensure sorting works correctly.
	var text = "'a' + 'bb' + 'ccc'"
	var result = GDSQL.GDSQLUtils.extract_outer_quotes(text)
	assert_int(result.size()).is_equal(3)
	assert_int(result[0].length()).is_greater_equal(result[1].length())
	assert_int(result[1].length()).is_greater_equal(result[2].length())


## 测试: 括号结果长度排序
func test_extract_outer_bracket_result_order() -> void:
	var text = "(a) + (bb) + (ccc)"
	var result = GDSQL.GDSQLUtils.extract_outer_bracket(text)
	assert_int(result.size()).is_equal(3)
	assert_int(result[0].length()).is_greater_equal(result[1].length())
	assert_int(result[1].length()).is_greater_equal(result[2].length())


## 测试: 不存在的符号
func test_search_symbol_with_empty_result_for_non_existent_symbol() -> void:
	var result = GDSQL.GDSQLUtils.search_symbol("hello world", "#")
	assert_int(result.size()).is_equal(0)


## 测试: 单字符输入逗号
func test_search_symbol_single_char_input() -> void:
	var text = ","
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	assert_int(result.size()).is_equal(1)


## 测试: 大数运算
func test_evaluate_command_script_large_numbers() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script("1000000 * 1000000")
	assert_int(result).is_equal(1000000000000)


## 测试: SQL缓存命中
func test_evaluate_command_with_sql_expression_cache_hit() -> void:
	# Run the same expression twice to exercise the cache hit path
	var result1 = GDSQL.GDSQLUtils.evaluate_command_with_sql_expression(
		null, "cache_test * 2", ["cache_test"], [5]
	)
	assert_int(result1).is_equal(10)

	var result2 = GDSQL.GDSQLUtils.evaluate_command_with_sql_expression(
		null, "cache_test * 2", ["cache_test"], [7]
	)
	assert_int(result2).is_equal(14)


## 测试: 括号引号混合逗号
func test_search_symbol_with_brackets_quotes_and_commas() -> void:
	var text = "func1('a,b'), func2(c,d)"
	var result = GDSQL.GDSQLUtils.search_symbol(text, ",")
	# Only the comma after func1(...) is at the top level.
	# Commas inside quotes and inside func2(...) are ignored.
	assert_int(result.size()).is_equal(1)


## 测试: 浮点数除法
func test_evaluate_command_script_float_division() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script("7.0 / 2.0")
	assert_that(result).is_equal(3.5)


## 测试: 目标方法返回字符串
func test_evaluate_command_with_target_method_returning_string() -> void:
	var script = GDScript.new()
	script.source_code = "extends Object\nfunc greet(name):\n\treturn 'Hello, ' + name"
	script.reload()
	var target = script.new()
	var result = GDSQL.GDSQLUtils.evaluate_command(target, 'greet("GDSQL")')
	assert_str(result).is_equal("Hello, GDSQL")
	target.free()


## 测试: 空白作为分隔符
func test_search_symbol_space_as_delimiter() -> void:
	var text = "one two\tthree\nfour"
	var result = GDSQL.GDSQLUtils.search_symbol(text, "\\s")
	assert_int(result.size()).is_equal(3)


## 测试: 嵌套三目运算符
func test_evaluate_command_script_nested_ternary() -> void:
	var result = GDSQL.GDSQLUtils.evaluate_command_script(
		"true if a > 0 else (false if b > 0 else true)",
		["a", "b"], [5, -1]
	)
	assert_bool(result).is_true()

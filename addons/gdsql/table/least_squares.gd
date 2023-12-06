## 最小二乘法
extends RefCounted
class_name LeastSquares

var groups: Array[LeastSquaresGroupNumber] = []
var group_x_map = {}

## 寻找字符串中最后一组数字的正则方式
var regex: RegEx = RegEx.new()

enum DATA_TYPE {
	NUMBER,
	STRING,
	OTHER
}

func _init(xdata: Array, ydata: Array):
	assert(xdata.size() == ydata.size(), "xdata's size is not equal to ydata's size")
	var a_xdata = []
	var a_ydata = []
	
	regex.compile(r"[0-9]+(?=[^0-9]*$)")
	
	var first_element = ydata.front()
	var pre = LeastSquaresData.new(first_element, regex)
	
	for i in xdata.size():
		var curr = LeastSquaresData.new(ydata[i], regex)
		
		# 是否需要分组
		var need_new_group = not pre.is_same_type(curr) or pre.is_other()
		
		# 即便当前是包含数字的字符串，也需要检查是否和前一个字符串的格式是否一致，从而判断是否需要分组
		if pre.is_same_string_pattern(curr):
			need_new_group = true
			
		# 需要重新分组时，要干的事情
		if need_new_group:
			var lsg: LeastSquaresGroupNumber
			if pre.is_number():
				lsg = LeastSquaresGroupNumber.new(a_xdata, a_ydata)
			elif pre.is_string():
				lsg = LeastSquaresGroupString.new(a_xdata, a_ydata)
			else:
				lsg = LeastSquaresGroupOther.new(a_xdata, a_ydata)
				
			groups.push_back(lsg)
			group_x_map[groups.back()] = i - 1
			a_xdata.clear()
			a_ydata.clear()
			
		a_xdata.push_back(xdata[i])
		a_ydata.push_back(curr)
		pre = curr
		
	if not a_xdata.is_empty():
		var lsg: LeastSquaresGroupNumber
		if pre.is_number():
			lsg = LeastSquaresGroupNumber.new(a_xdata, a_ydata)
		elif pre.is_string():
			lsg = LeastSquaresGroupString.new(a_xdata, a_ydata)
		else:
			lsg = LeastSquaresGroupOther.new(a_xdata, a_ydata)
		groups.push_back(lsg)
		group_x_map[groups.back()] = xdata.size() - 1
	
## NOTICE 如果字符串样本中存在数字以0开头，则涉及最小长度补全，否则不涉及。最小长度是样本中以0开头的数字中的最长的长度。
## 最小长度是样本中最大数字的长度。
## 因此，反推ydata中的元素时，得到的y值可能与原来的y值长度不同。
## 比如：xdata = [0, 1], ydata = ['a_1', 'a_002']，调用get_y(0)的结果是'a_001'而不是'a_1'。
## 字符串中的数字不会出现负数。
func get_y(x: float) -> Variant:
	for group in group_x_map:
		if x <= group_x_map[group] or is_equal_approx(x, group_x_map[group]):
			return group.get_y(x)
	return null
	
#func get_x(y: float, group: int) -> float:
	#return groups[group].get_x(y)
	
	
## ######################################
## 最小二乘法分组：全数字
## ######################################
class LeastSquaresData:
	var data_type: int
	var value: Variant
	var origin_data_type: int
	var is_scientific: bool
	var prefix: String
	var surfix: String
	var num_length_with_zero: int
	
	func _init(v: Variant, regex: RegEx = null):
		origin_data_type = typeof(v)
		
		if v is int or v is float or ((v is String or v is StringName) and v.is_valid_float()):
			data_type = DATA_TYPE.NUMBER
			value = type_convert(v, TYPE_FLOAT)
			is_scientific = (v is String or v is StringName) and (v.contains("e") or v.contains("E"))
			return
			
		if v is String:
			var m = regex.search(v)
			if m != null:
				data_type = DATA_TYPE.STRING
				value = (m as RegExMatch).get_string()
				prefix = v.substr(0, m.get_start())
				surfix = v.substr(m.get_end(), v.length())
				num_length_with_zero = value.length() if value.begins_with("0") else 0
				return
				
		data_type = DATA_TYPE.OTHER
		value = v
		
	func is_number() -> bool:
		return data_type == DATA_TYPE.NUMBER
		
	func is_string() -> bool:
		return data_type == DATA_TYPE.STRING
		
	func is_other() -> bool:
		return data_type == DATA_TYPE.OTHER
		
	func is_same_type(v: LeastSquaresData) -> bool:
		return data_type == v.data_type
		
	func is_same_string_pattern(v: LeastSquaresData) -> bool:
		return is_string() and v.is_string() and prefix == v.prefix and surfix == v.surfix

## ######################################
## 最小二乘法分组：全数字
## ######################################
class LeastSquaresGroupNumber:
	## 斜率
	var slope: float
	## 截距
	var intercept: float
	## 科学计数法表示
	var scientific: bool
	
	func _init(xdata: Array, ydata: Array):
		var n = xdata.size()
		var sumX = 0
		var sumY = 0
		var sumXY = 0
		var sumXX = 0
		scientific = true
		for i in n:
			var a_y_element = ydata[i].value if ydata[i] is LeastSquaresData else ydata[i]
			if scientific:
				if ydata[i] is LeastSquaresData and not (ydata[i] as LeastSquaresData).is_scientific:
					scientific = false
				elif not ydata[i] is LeastSquaresData and not (LeastSquaresData.new(ydata[i], null)).is_scientific:
					scientific = false
			sumX += xdata[i]
			sumY += a_y_element
			sumXY += xdata[i] * a_y_element
			sumXX += xdata[i] * xdata[i]
			
		slope = (n * sumXY - sumX * sumY) / float(n * sumXX - sumX * sumX) if (n * sumXX - sumX * sumX) != 0 else 1 # xdata只有1个元素，默认斜率为1
		intercept = (sumY - slope * sumX) / float(n)
		
	func get_y(x: float) -> Variant:
		var y = slope * x + intercept
		if scientific:
			return String.num_scientific(y)
		return y
		
	# 获取y值对应的x坐标，只在ydata全是数字时有效
	#func get_x(y: Variant) -> float:
		#return (float(y) - intercept) / slope
		
## ######################################
## 最小二乘法分组：同类型包含数字的字符串
## ######################################
class LeastSquaresGroupString extends LeastSquaresGroupNumber:
	## 前缀（当ydata中的元素为字符串时需要）
	var _prefix: String = ""
	## 后缀（当ydata中的元素为字符串时需要）
	var _surfix: String = ""
	## 字符串中的数字的最小长度（样本中以0开头的数字中的最长的长度）
	var _min_num_length: int = 0
	
	## 请确保ydata中的每个元素都是包含数字的字符串
	func _init(xdata: Array, ydata: Array[LeastSquaresData]):
		_prefix = ydata[0].prefix
		_surfix = ydata[0].surfix
		
		var tmp_ydata = []
		for i in ydata:
			assert(i.is_string(), "All the elements' type of ydata must be same")
			assert(not (i.prefix == _prefix and i.surfix == _surfix), 
				"All the elements of ydata should begin with [%s]` and end with [%s]" % [_prefix, _surfix])
			_min_num_length = max(_min_num_length, i.length_with_zero)
			#tmp_ydata.push_back(type_convert(i.value, TYPE_FLOAT))
			tmp_ydata.push_back(LeastSquaresData.new(i.value, null))
			
		super._init(xdata, tmp_ydata)
		
	## NOTICE 如果字符串样本中存在数字以0开头，则涉及最小长度补全，否则不涉及。最小长度是样本中以0开头的数字中的最长的长度。
	## 最小长度是样本中最大数字的长度。
	## 因此，反推ydata中的元素时，得到的y值可能与原来的y值长度不同。
	## 比如：xdata = [0, 1], ydata = ['a_1', 'a_002']，调用get_y(0)的结果是'a_001'而不是'a_1'。
	## 字符串中的数字不会出现负数。
	func get_y(x: float) -> Variant:
		return String(_prefix + str(abs(super.get_y(x))).lpad(_min_num_length) + _surfix)
		
	#func get_x(y: Variant) -> float:
		#assert(y is String, "Y is supposed to be a String but is [%s]" % str(y))
		#y = y as String
		#assert(y.begins_with(_prefix) and y.ends_with(_surfix), "Y is supposed to begin with [%s] and end with [%s]" % [_prefix, _surfix])
		#var m = _regex.search(y)
		#assert(m != null, "Y must contains a number")
		#return super.get_x(m.get_string())
		
		
## ######################################
## 最小二乘法分组：其他类型
## ######################################
class LeastSquaresGroupOther extends LeastSquaresGroupNumber:
	## 需要返回的值（即ydata最后一个元素，当然，这个值可能在其他位置也出现过）
	var _return: Variant
	## 样本中首次出现_return值的位置
	var _start_index: float
	
	func _init(xdata: Array, ydata: Array):
		_return = ydata.back()
		_return = _return.value if _return is LeastSquaresData else _return
		for i in xdata.size():
			if ydata[i] == _return:
				_start_index = xdata[i]
				break
		
	func get_y(_x: float) -> Variant:
		return _return
		
	#func get_x(_y: Variant) -> float:
		#return _start_index
		

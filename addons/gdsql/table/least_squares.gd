## 最小二乘法
@tool
extends RefCounted

var groups: Array[LeastSquaresGroupNumber] = []
var group_x_map = {}

## 寻找字符串中最后一组数字的正则方式
static var regex: RegEx = RegEx.new()

enum DATA_TYPE {
	NUMBER,
	STRING,
	VECTOR2,
	VECTOR2I,
	VECTOR3,
	VECTOR3I,
	VECTOR4,
	VECTOR4I,
	RESOURCE,
	OTHER
}

static func _static_init() -> void:
	regex.compile(r"[0-9]+(?=[^0-9]*$)")
	
## 传入x轴和y轴的样本
func _init(xdata: Array, ydata: Array):
	assert(xdata.size() == ydata.size(), "xdata's size is not equal to ydata's size")
	var a_xdata = []
	var a_ydata = []
	
	var first_element = ydata.front()
	var pre = LeastSquaresData.new(first_element, regex)
	
	for i in xdata.size():
		var curr = LeastSquaresData.new(ydata[i], regex)
		
		# 是否需要分组
		var need_new_group = not a_xdata.is_empty() and not pre.is_same_pattern(curr)
			
		# 需要重新分组时，要干的事情
		if need_new_group:
			var lsg: LeastSquaresGroupNumber = make_lsg(pre, a_xdata, a_ydata)
			groups.push_back(lsg)
			group_x_map[groups.back()] = i - 1
			a_xdata.clear()
			a_ydata.clear()
			
		a_xdata.push_back(xdata[i])
		a_ydata.push_back(curr)
		pre = curr
		
	if not a_xdata.is_empty():
		var lsg: LeastSquaresGroupNumber = make_lsg(pre, a_xdata, a_ydata)
		groups.push_back(lsg)
		group_x_map[groups.back()] = xdata.size() - 1
		
func make_lsg(pre, a_xdata, a_ydata) -> LeastSquaresGroupNumber:
	var lsg: LeastSquaresGroupNumber
	if pre.is_number():
		lsg = LeastSquaresGroupNumber.new(a_xdata, a_ydata)
	elif pre.is_string():
		lsg = LeastSquaresGroupString.new(a_xdata, a_ydata)
	elif pre.is_vector2():
		lsg = LeastSquaresGroupVector2.new(a_xdata, a_ydata)
	elif pre.is_vector2i():
		lsg = LeastSquaresGroupVector2I.new(a_xdata, a_ydata)
	elif pre.is_vector3():
		lsg = LeastSquaresGroupVector3.new(a_xdata, a_ydata)
	elif pre.is_vector3i():
		lsg = LeastSquaresGroupVector3I.new(a_xdata, a_ydata)
	elif pre.is_vector4():
		lsg = LeastSquaresGroupVector4.new(a_xdata, a_ydata)
	elif pre.is_vector4i():
		lsg = LeastSquaresGroupVector4I.new(a_xdata, a_ydata)
	elif pre.is_resource():
		lsg = LeastSquaresGroupResource.new(a_xdata, a_ydata)
	else:
		lsg = LeastSquaresGroupOther.new(a_xdata, a_ydata)
	return lsg
	
## NOTICE 如果字符串样本中存在数字以0开头，则涉及最小长度补全，否则不涉及。最小长度是样本中以0开头的数字中的最长的长度。
## 最小长度是样本中最大数字的长度。
## 因此，反推ydata中的元素时，得到的y值可能与原来的y值长度不同。
## 比如：xdata = [0, 1], ydata = ['a_1', 'a_002']，调用get_y(0)的结果是'a_001'而不是'a_1'。
## 字符串中的数字不会出现负数。
func get_y(x: float) -> Variant:
	var last_group
	for group in group_x_map:
		last_group = group
		if x <= group_x_map[group] or is_equal_approx(x, group_x_map[group]):
			return group.get_y(x)
	return last_group.get_y(x)
	
#func get_x(y: float, group: int) -> float:
	#return groups[group].get_x(y)
	
	
## ######################################
## 最小二乘法数据
## ######################################
class LeastSquaresData:
	var data_type: int
	var value: Variant
	var origin_data_ref: WeakRef
	var origin_data_type: int
	var is_scientific: bool
	var prefix: String
	var surfix: String
	var num_length_with_zero: int
	
	func _init(v: Variant, regex: RegEx = null):
		if v is Object:
			origin_data_ref = weakref(v)
		origin_data_type = typeof(v)
		
		if v is int or v is float or ((v is String or v is StringName) and v.is_valid_float()):
			data_type = DATA_TYPE.NUMBER
			var to_int = int(v)
			if str(v) == str(to_int):
				value = to_int
			else:
				value = float(v)
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
				
		if v is Vector2:
			data_type = DATA_TYPE.VECTOR2
			value = v
			return
			
		if v is Vector2i:
			data_type = DATA_TYPE.VECTOR2I
			value = v
			return
			
		if v is Vector3:
			data_type = DATA_TYPE.VECTOR3
			value = v
			return
			
		if v is Vector3i:
			data_type = DATA_TYPE.VECTOR3I
			value = v
			return
			
		if v is Vector4:
			data_type = DATA_TYPE.VECTOR4
			value = v
			return
			
		if v is Vector4i:
			data_type = DATA_TYPE.VECTOR4I
			value = v
			return
			
		if v is Resource:
			if not v.resource_path.contains("::"):
				var m = regex.search(v.resource_path)
				if m != null:
					data_type = DATA_TYPE.RESOURCE
					value = (m as RegExMatch).get_string()
					prefix = v.resource_path.substr(0, m.get_start())
					surfix = v.resource_path.substr(m.get_end(), v.resource_path.length())
					num_length_with_zero = value.length() if value.begins_with("0") else 0
					return
					
		data_type = DATA_TYPE.OTHER
		value = v
		
	func is_number() -> bool:
		return data_type == DATA_TYPE.NUMBER
		
	func is_string() -> bool:
		return data_type == DATA_TYPE.STRING
		
	func is_vector2() -> bool:
		return data_type == DATA_TYPE.VECTOR2
		
	func is_vector2i() -> bool:
		return data_type == DATA_TYPE.VECTOR2I
		
	func is_vector3() -> bool:
		return data_type == DATA_TYPE.VECTOR3
		
	func is_vector3i() -> bool:
		return data_type == DATA_TYPE.VECTOR3I
		
	func is_vector4() -> bool:
		return data_type == DATA_TYPE.VECTOR4
		
	func is_vector4i() -> bool:
		return data_type == DATA_TYPE.VECTOR4I
		
	func is_resource() -> bool:
		return data_type == DATA_TYPE.RESOURCE
		
	func is_other() -> bool:
		return data_type == DATA_TYPE.OTHER
		
	func is_same_type(v: LeastSquaresData) -> bool:
		return data_type == v.data_type
		
	func is_same_pattern(v: LeastSquaresData) -> bool:
		if not is_same_type(v):
			return false
		if is_other() or v.is_other():
			return false
		if is_number() and v.is_number():
			return true
		if is_string() and v.is_string() and prefix == v.prefix and surfix == v.surfix:
			return true
		if is_vector2() and v.is_vector2():
			return true
		if is_vector2i() and v.is_vector2i():
			return true
		if is_vector3() and v.is_vector3():
			return true
		if is_vector3i() and v.is_vector3i():
			return true
		if is_vector4() and v.is_vector4():
			return true
		if is_vector4i() and v.is_vector4i():
			return true
		return false
		
		
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
	## 小数点保留位数（取y中的最大）
	var ndigits: int
	
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
			
			# 小数点位数
			if ydata[i].value is float and not scientific:
				var number_str = str(ydata[i].value)
				var decimal_point_index = number_str.find(".")
				if decimal_point_index != -1:
					var decimal_places = number_str.length() - decimal_point_index - 1
					if decimal_places >= ndigits:
						ndigits = decimal_places
						
		slope = (n * sumXY - sumX * sumY) / float(n * sumXX - sumX * sumX) if (n * sumXX - sumX * sumX) != 0 else 1 # xdata只有1个元素，默认斜率为1
		intercept = (sumY - slope * sumX) / float(n)
		
	func get_y(x: float) -> Variant:
		var y = slope * x + intercept
		if scientific:
			return String.num_scientific(y)
		if ndigits == 0:
			if y == int(y):
				return int(y)
		else:
			y = float(('%.' + str(ndigits) + 'f') % y)
		return y
		
	# 获取y值对应的x坐标，只在ydata全是数字时有效
	#func get_x(y: Variant) -> float:
		#return (float(y) - intercept) / slope
		
## ######################################
## 最小二乘法分组：同类型包含数字的字符串
## ######################################
class LeastSquaresGroupString extends LeastSquaresGroupNumber:
	## 前缀
	var _prefix: String = ""
	## 后缀
	var _surfix: String = ""
	## 字符串中的数字的最小长度（样本中以0开头的数字中的最长的长度）
	var _min_num_length: int = 0
	
	## 请确保ydata中的每个元素都是包含数字的字符串
	func _init(xdata: Array, ydata: Array):
		_prefix = ydata[0].prefix
		_surfix = ydata[0].surfix
		
		var tmp_ydata = []
		for i in ydata:
			#assert(i.is_string(), "All the elements' type of ydata must be same")
			#assert(not (i.prefix == _prefix and i.surfix == _surfix), 
				#"All the elements of ydata should begin with [%s]` and end with [%s]" % [_prefix, _surfix])
			_min_num_length = max(_min_num_length, i.num_length_with_zero)
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
## 最小二乘法分组：Vector2
## ######################################
class LeastSquaresGroupVector2 extends LeastSquaresGroupNumber:
	var _x_lsgn: LeastSquaresGroupNumber
	var _y_lsgn: LeastSquaresGroupNumber
	
	func _init(xdata: Array, ydata: Array):
		var _x = ydata.map(func(v): return LeastSquaresData.new(v.value.x, null))
		var _y = ydata.map(func(v): return LeastSquaresData.new(v.value.y, null))
		_x_lsgn = LeastSquaresGroupNumber.new(xdata, _x)
		_y_lsgn = LeastSquaresGroupNumber.new(xdata, _y)
		
	func get_y(x: float) -> Variant:
		return Vector2(_x_lsgn.get_y(x), _y_lsgn.get_y(x))
		
		
## ######################################
## 最小二乘法分组：Vector2i
## ######################################
class LeastSquaresGroupVector2I extends LeastSquaresGroupVector2:
	func get_y(x: float) -> Variant:
		return Vector2i(int(_x_lsgn.get_y(x)), int(_y_lsgn.get_y(x)))
		
		
## ######################################
## 最小二乘法分组：Vector3
## ######################################
class LeastSquaresGroupVector3 extends LeastSquaresGroupVector2:
	var _z_lsgn: LeastSquaresGroupNumber
	
	func _init(xdata: Array, ydata: Array):
		super._init(xdata, ydata)
		var _z = ydata.map(func(v): return LeastSquaresData.new(v.value.z, null))
		_z_lsgn = LeastSquaresGroupNumber.new(xdata, _z)
		
	func get_y(x: float) -> Variant:
		return Vector3(_x_lsgn.get_y(x), _y_lsgn.get_y(x), _z_lsgn.get_y(x))
		
		
## ######################################
## 最小二乘法分组：Vector3i
## ######################################
class LeastSquaresGroupVector3I extends LeastSquaresGroupVector3:
	func get_y(x: float) -> Variant:
		return Vector3i(int(_x_lsgn.get_y(x)), int(_y_lsgn.get_y(x)), int(_z_lsgn.get_y(x)))
		
		
## ######################################
## 最小二乘法分组：Vector4
## ######################################
class LeastSquaresGroupVector4 extends LeastSquaresGroupVector3:
	var _w_lsgn: LeastSquaresGroupNumber
	
	func _init(xdata: Array, ydata: Array):
		super._init(xdata, ydata)
		var _w = ydata.map(func(v): return LeastSquaresData.new(v.value.w, null))
		_w_lsgn = LeastSquaresGroupNumber.new(xdata, _w)
		
	func get_y(x: float) -> Variant:
		return Vector4(_x_lsgn.get_y(x), _y_lsgn.get_y(x), _z_lsgn.get_y(x), _w_lsgn.get_y(x))
		
		
## ######################################
## 最小二乘法分组：Vector4i
## ######################################
class LeastSquaresGroupVector4I extends LeastSquaresGroupVector4:
	func get_y(x: float) -> Variant:
		return Vector4i(int(_x_lsgn.get_y(x)), int(_y_lsgn.get_y(x)), int(_z_lsgn.get_y(x)), int(_w_lsgn.get_y(x)))
		
		
## ######################################
## 最小二乘法分组：Resource
## ######################################
class LeastSquaresGroupResource extends LeastSquaresGroupString:
	var _model: WeakRef # 模板的引用
	
	func _init(xdata: Array, ydata: Array):
		_model = ydata.front().origin_data_ref
		super._init(xdata, ydata)
		
	func get_y(x: float) -> Resource:
		var path = super.get_y(x)
		return load(path)
			
			
## ######################################
## 最小二乘法分组：其他类型
## ######################################
class LeastSquaresGroupOther extends LeastSquaresGroupNumber:
	## 需要返回的值（即ydata最后一个元素，当然，这个值可能在其他位置也出现过）
	var _return: Variant
	# 样本中首次出现_return值的位置
	#var _start_index: float
	
	func _init(_xdata: Array, ydata: Array):
		_return = ydata.back()
		_return = _return.value if _return is LeastSquaresData else _return
		#for i in xdata.size():
			#if ydata[i] == _return:
				#_start_index = xdata[i]
				#break
		
	func get_y(_x: float) -> Variant:
		return _return
		
	#func get_x(_y: Variant) -> float:
		#return _start_index
		

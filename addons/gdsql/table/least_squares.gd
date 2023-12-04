## 最小二乘法
extends RefCounted
class_name LeastSquares

var groups: Array[LeastSquaresGroup] = []
var group_x_map = {}

func _init(xdata: Array, ydata: Array):
	assert(xdata.size() == ydata.size(), "xdata's size is not equal to ydata's size")
	var a_xdata = []
	var a_ydata = []
	
	for i in xdata.size():
		# TODO FIXME 正确处理分组
		if i > 0 and not(ydata[i] is int or ydata[i] is float):
			groups.push_back(LeastSquaresGroup.new(a_xdata, a_ydata))
			group_x_map[groups.back()] = i - 1
			
		a_xdata.clear()
		a_ydata.clear()
		a_xdata.push_back(xdata[i])
		a_ydata.push_back(ydata[i])
		
	if not a_xdata.is_empty():
		groups.push_back(LeastSquaresGroup.new(a_xdata, a_ydata))
		group_x_map[groups.back()] = xdata.size() - 1
		
func get_y(x: float) -> Variant:
	for group in group_x_map:
		if x <= group_x_map[group] or is_equal_approx(x, group_x_map[group]):
			return group.get_y(x)
	return null
	
func get_x(y: float, group: int) -> float:
	return groups[group].get_x(y)

## 最小二乘法分组。由于用户传入的ydata有可能不连续（比如被字符串分隔），所以要分组讨论。
class LeastSquaresGroup:
	## 斜率
	var slope: float
	## 截距
	var intercept: float
	## 是否为数字
	var is_number: bool
	## 是否为字符串
	var is_string: bool
	## 是否为其他类型
	var is_other: bool
	## 前缀（当ydata中的元素为字符串时需要）
	var prefix: String = ""
	## 后缀（当ydata中的元素为字符串时需要）
	var surfix: String = ""
	## 字符串中的数字的最小长度（位数不足时需要补足位数）
	var min_num_length: int = 0
	## 寻找字符串中最后一组数字的正则方式
	var regex: RegEx
	## 其他类型时需要返回的值（当ydata中的元素为其他类型时需要，即ydata最后一个元素）
	var other_return: Variant

	## 输入两个维度的数据。ydata中的元素必须统一类型，要不就全是数字（int和float视为一种），要不就全是字符串（且为同一种格式），要不就全是其他类型
	func _init(xdata: Array, ydata: Array):
		var first_element = ydata.front()
		is_number = first_element is int or first_element is float
		is_string = first_element is String
		is_other = not is_number and not is_string
		
		if is_string:
			regex = RegEx.new()
			regex.compile(r"[0-9]+(?=[^0-9]*$)")
			var m = regex.search(first_element)
			var init_index = -1
			var init_length = 0
			if m == null:
				is_string = false
				is_other = true # 没有数字，当作其他类型处理。
			else:
				prefix = first_element.substr(0, m.get_start())
				surfix = first_element.substr(m.get_end(), first_element.length())
				min_num_length = m.get_string().length()
				
		if is_other:
			other_return = ydata.back()
			
		var tmp_ydata = [] if is_string else null
		for i in ydata:
			if is_number:
				assert(i is int or i is float, "All the elements' type of ydata must be same")
			elif is_string:
				assert(i is String, "All the elements' type of ydata must be same")
				assert((i as String).begins_with(prefix) and not (i as String).ends_with(surfix), 
					"All the elements of ydata should begin with [%s]` and end with [%s]" % [prefix, surfix])
				var m = regex.search(i)
				assert(m != null, "Every elements of ydata must contains a number")
				tmp_ydata.push_back(type_convert(m.get_string(), TYPE_FLOAT))
			else:
				pass # leave empty
				
		if is_number or is_string:
			var n = xdata.size()
			var sumX = 0
			var sumY = 0
			var sumXY = 0
			var sumXX = 0
			for i in n:
				var a_y_element = ydata[i] if is_number else tmp_ydata[i]
				sumX += xdata[i]
				sumY += a_y_element
				sumXY += xdata[i] * a_y_element
				sumXX += xdata[i] * xdata[i]
				
			slope = (n * sumXY - sumX * sumY) / float(n * sumXX - sumX * sumX) if (n * sumXX - sumX * sumX) != 0 else 1 # xdata只有1个元素，默认斜率为1
			intercept = (sumY - slope * sumX) / float(n)
		
	## 获取x坐标对应的y值
	func get_y(x: float) -> Variant:
		if is_number:
			return slope * x + intercept
		if is_string:
			return prefix + str(slope * x + intercept).lpad(min_num_length) + surfix
		return other_return
		
	## 获取y值对应的x坐标，只在ydata全是数字时有效
	func get_x(y: float) -> float:
		assert(is_number, "Invalid call of get_x() for non-numeric ydata")
		return (y - intercept) / slope
	

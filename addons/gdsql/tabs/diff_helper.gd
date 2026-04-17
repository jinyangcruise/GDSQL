extends Object

enum Operation {
	MOVE,
	DELETE,
	INSERT,
}

static func compare(src: Array, dst: Array):
	var script = _shortest_edit_script(src, dst)
	var src_index = 0
	var dst_index = 0
	var src_deleted_lines = []
	var dst_inserted_lines = []
	# 记录 dst 到 src 的映射
	var mapping_dst_src = {}  # key: dst_index => value: src_index
	
	for op in script:
		match op:
			Operation.MOVE:
				#print(src[src_index])
				mapping_dst_src[dst_index] = src_index
				src_index += 1
				dst_index += 1
				
			Operation.DELETE:
				#print_rich("[color=red]-%s[/color]" % src[src_index]) 
				src_deleted_lines.push_back(src_index)
				src_index += 1
				
			Operation.INSERT:
				#print_rich("[color=green]+%s[/color]" % dst[dst_index]) 
				dst_inserted_lines.push_back(dst_index)
				dst_index += 1
				
	return [src_deleted_lines, dst_inserted_lines, mapping_dst_src, script]
	
## 把dst中的（新增）行合并到src中，返回src应该插入的位置。参数index是dst中的行。
static func merge_insert_line_by_mapping(index: int, src_line_count: int, mapping: Dictionary):
	if mapping.has(index):
		assert(false, "Err! src has this line!")
	# 查找最近的 MOVE 行对应的 src 位置
	for i in range(index - 1, -1, -1):
		if mapping.has(i):
			return mapping[i] + 1  # 插入到它后面
	return src_line_count
	
## 把src中的（删除）行合并（还原）到dst中，返回dst应该插入的位置。参数index是src中的行。
static func merge_delete_line_by_mapping(index: int, dst_line_count: int, mapping: Dictionary):
	# 查找最近的 MOVE 行对应的 dst 位置
	var insert_pos = dst_line_count
	for i in mapping:
		if mapping[i] < index:
			insert_pos = i + 1  # 插入到它后面
		elif mapping[i] == index:
			assert(false, "Err! dst has this line!")
		else:
			break
	return insert_pos
	
static func _shortest_edit_script(src: Array, dst: Array) -> Array:
	var n = src.size()
	var m = dst.size()
	var sum = n + m
	var trace = []
	var x = 0
	var y = 0
	
	var found = false # 为了中途跳出
	for d in range(0, sum + 1):
		var v = {}
		trace.append(v)
		
		if d == 0:
			var t = 0
			while t < src.size() and t < dst.size() and src[t] == dst[t]:
				t += 1
			v[0] = t
			if t == n and t == m:
				break
			continue
		
		var last_v = trace[d - 1]
		
		for k in range(-d, d + 1, 2):
			if k == -d or (k != d && last_v.get(k - 1, 0) < last_v.get(k + 1, 0)):
				x = last_v.get(k + 1, 0)
			else:
				x = last_v.get(k - 1, 0) + 1
			
			y = x - k
			
			while x < n and y < m and src[x] == dst[y]:
				x += 1
				y += 1
			
			v[k] = x
			
			if x == n and y == m:
				found = true
				break
				
		if found:
			break
	
	var script = []
	x = n
	y = m
	
	for d in range(trace.size() - 1, 0, -1):
		var k = x - y
		var last_v = trace[d - 1]
		var prev_k = 0
		
		if k == -d or (k != d and last_v.get(k - 1, 0) < last_v.get(k + 1, 0)):
			prev_k = k + 1
		else:
			prev_k = k - 1
		
		var prev_x = last_v.get(prev_k, 0)
		var prev_y = prev_x - prev_k
		
		while x > prev_x and y > prev_y:
			script.append(Operation.MOVE)
			x -= 1
			y -= 1
		
		if x == prev_x:
			script.append(Operation.INSERT)
		else:
			script.append(Operation.DELETE)
		
		x = prev_x
		y = prev_y
	
	var first_v = trace[0]
	var common_prefix_length = first_v.get(0, 0)
	for i in range(common_prefix_length):
		script.append(Operation.MOVE)
	
	script.reverse()
	return script

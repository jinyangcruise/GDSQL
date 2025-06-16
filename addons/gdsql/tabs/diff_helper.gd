extends Object
class_name DiffHelper

enum Operation {
	INSERT,
	DELETE,
	MOVE
}

static func compare(src: Array, dst: Array):
	var script = _shortest_edit_script(src, dst)
	var src_index = 0
	var dst_index = 0
	var src_deleted_lines = []
	var dst_inserted_lines = []
	
	for op in script:
		match op:
			Operation.INSERT:
				#print_rich("[color=green]+%s[/color]" % dst[dst_index]) 
				dst_inserted_lines.push_back(dst_index)
				dst_index += 1
				
			Operation.MOVE:
				#print(src[src_index])
				src_index += 1
				dst_index += 1
				
			Operation.DELETE:
				#print_rich("[color=red]-%s[/color]" % src[src_index]) 
				src_deleted_lines.push_back(src_index)
				src_index += 1
				
	return [src_deleted_lines, dst_inserted_lines]

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

@tool
extends RefCounted

#<!ELEMENT cache (property*)>
#<!ATTLIST cache
#type CDATA #IMPLIED ------------- ❌ not support
#eviction CDATA #IMPLIED --------- 缓存回收策略，可以不设置，默认值为 LRU（最近最少使用）
#                                  策略。其他可能的值包括 FIFO（先进先出）、
#                                  SOFT（软引用）❌和 WEAK（弱引用）❌
#flushInterval CDATA #IMPLIED ---- 缓存刷新间隔，单位为毫秒。如果设置为非零值，MyBatis 
#                                  会在指定的时间间隔内自动刷新缓存。
#size CDATA #IMPLIED ------------- 缓存大小，默认值为 1024。如果设置为非零值，MyBatis 
#                                  会在缓存大小超过指定值时开始回收缓存。
#                                  它指定的是缓存中可以存储的键值对的最大数量，而不是缓存
#                                  所占用的内存大小。当缓存中的键值对数量达到或超过这个指
#                                  定值时，MyBatis 就会根据缓存配置和策略来决定哪些缓存
#                                  条目应该被淘汰，以保持缓存的大小不超过指定的值。
#readOnly CDATA #IMPLIED --------- ❌ not support
#                                  是否只读，默认为 false。只读的缓存会给所有调用者返回
#                                  同一个实例，因此这些对象不能被修改，这提供了性能优势。
#blocking CDATA #IMPLIED --------- ❌ not support
#>

var eviction: String
var flush_interval: int
var size: int

# ------------- 内部使用 --------------
## 缓存数据
var _cache
## 上次缓存刷新时间，毫秒数
var _last_flush_time: int

func _init(conf: Dictionary) -> void:
	eviction = conf.get("eviction", "LRU").strip_edges()
	flush_interval = type_convert(conf.get("flushInterval", "0").strip_edges(), TYPE_INT)
	size = type_convert(conf.get("size", "1024").strip_edges(), TYPE_INT)
	if eviction == "LRU":
		_cache = GBatisLRULink.new()
	elif eviction == "FIFO":
		_cache = GBatisFIFOLink.new()
	else:
		assert(false, "Attr eviction in <cache> should be LRU or FIFO, but: " + eviction)
	_cache.capacity = size
	
func clear_cache(now: int = 0):
	_cache.clear()
	if now == 0:
		now = Time.get_ticks_msec()
	_last_flush_time = now
	
func _refresh():
	if flush_interval <= 0:
		return
	var now = Time.get_ticks_msec()
	if now - _last_flush_time > flush_interval:
		clear_cache(now)
		
func set_cache(method: String, param: Dictionary, value: Variant):
	var key = [method]
	for i in param:
		if i != GDSQL.GBatisMapperParser.BIND:
			key.push_back(param[i])
	set_cache_by_key(key, value)
	
func set_cache_by_key(key, value: Variant):
	_refresh()
	_cache.put_value(key, var_to_str(value))
	
func get_cache(method: String, param: Dictionary) -> Array:
	var key = [method]
	for i in param:
		if i != GDSQL.GBatisMapperParser.BIND:
			key.push_back(param[i])
	_refresh()
	if _cache.has_key(key):
		return [true, str_to_var(_cache.get_value(key)), key]
	return [false, null, key]
	
class GBatisCacheNode extends RefCounted:
	var key
	var value: Variant
	var prev: GBatisCacheNode
	var next: GBatisCacheNode
	
class GBatisLRULink extends RefCounted:
	var cache: Dictionary
	var capacity: int
	var head: GBatisCacheNode = GBatisCacheNode.new()
	var tail: GBatisCacheNode = GBatisCacheNode.new()
	
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			if head:
				head.next = null
				head = null
			if tail:
				tail.prev = null
				tail = null
				
	func _init() -> void:
		head.next = tail
		tail.prev = head
		
	func has_key(key) -> bool:
		return cache.has(key)
		
	func get_value(key):
		if not cache.has(key):
			return null
		var node = cache[key] as GBatisCacheNode
		move_to_tail(node)
		return node.value
		
	func remove_value(key):
		if not has_key(key):
			return
		var node = cache[key] as GBatisCacheNode
		remove_node(node)
		cache.erase(key)
		
	func put_value(key, value: Variant):
		if cache.has(key):
			var node = cache[key] as GBatisCacheNode
			node.value = value
			move_to_tail(node)
		else:
			var node = GBatisCacheNode.new()
			node.key = key
			node.value = value
			
			# 添加节点到链表尾部  
			add_to_tail(node)
			
			# 将新节点添加到哈希表中  
			cache[key] = node
			
			# 如果超出容量，删除最久未使用的节点  
			if cache.size() > capacity:
				var removed_node = remove_head()
				cache.erase(removed_node.key)
				
	func add_to_tail(node: GBatisCacheNode):
		var prev_node = tail.prev
		prev_node.next = node
		node.prev = prev_node
		node.next = tail
		tail.prev = node
		
	func remove_node(node: GBatisCacheNode):
		var prev_node = node.prev
		var next_node = node.next
		prev_node.next = next_node
		next_node.prev = prev_node
		
	func move_to_tail(node: GBatisCacheNode):
		remove_node(node)
		add_to_tail(node)
		
	func remove_head():
		var head_next = head.next
		remove_node(head_next)
		return head_next
		
	func clear():
		# 清空双向链表
		var current = head.next
		while current != tail:
			var next_node = current.next
			# 从哈希表中移除当前节点的键  
			cache.erase(current.key)
			# 断开当前节点的连接  
			current.prev = null
			current.next = null
			# 移动到下一个节点  
			current = next_node
			
		# 双向链表重置为只有一个头节点和尾节点  
		head.next = tail
		tail.prev = head
		
	func clean():
		clear()
		head.next = null
		tail.prev = null
		head = null
		tail = null
		
class GBatisFIFOLink extends RefCounted:
	var cache: Dictionary
	var capacity: int
	var head: GBatisCacheNode = GBatisCacheNode.new()
	var tail: GBatisCacheNode = GBatisCacheNode.new()
	
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			if head:
				head.next = null
				head = null
			if tail:
				tail.prev = null
				tail = null
				
	func _init() -> void:
		head.next = tail
		tail.prev = head
		
	func has_key(key) -> bool:
		return cache.has(key)
		
	func get_value(key):
		if cache.has(key):
			return cache[key].value
		return null
		
	func put_value(key, value: Variant):
		if cache.has(key):
			var node = cache[key]
			node.value = value
			return
			
		# Add the new item to the tail  
		var new_node = GBatisCacheNode.new()
		new_node.key = key
		new_node.value = value
		cache[key] = new_node
		new_node.prev = tail.prev
		new_node.next = tail
		tail.prev.next = new_node
		tail.prev = new_node
		
		if cache.size() > capacity:
			var oldest_node = head.next
			cache.erase(oldest_node.key)
			oldest_node.prev.next = oldest_node.next
			oldest_node.next.prev = oldest_node.prev
			
	func remove_value(key):
		if not has_key(key):
			return
		var node = cache[key] as GBatisCacheNode
		remove_node(node)
		cache.erase(key)
		
	func remove_node(node: GBatisCacheNode):
		var prev_node = node.prev
		var next_node = node.next
		prev_node.next = next_node
		next_node.prev = prev_node
		
	func clear():
		# 清空双向链表
		var current = head.next
		while current != tail:
			var next_node = current.next
			# 从哈希表中移除当前节点的键  
			cache.erase(current.key)
			# 断开当前节点的连接  
			current.prev = null
			current.next = null
			# 移动到下一个节点  
			current = next_node
			
		# 双向链表重置为只有一个头节点和尾节点  
		head.next = tail
		tail.prev = head
		
	func clean():
		clear()
		head.next = null
		tail.prev = null
		head = null
		tail = null

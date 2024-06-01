@tool
extends RefCounted
class_name GBatisCache
#<!ELEMENT cache (property*)>
#<!ATTLIST cache
#type CDATA #IMPLIED ------------- ❌ not support
#eviction CDATA #IMPLIED --------- 缓存回收策略，可以不设置，默认值为 FIFO，表示先进先出
#                                  策略。其他可能的值包括 LRU（最近最少使用）、
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

func _init(conf: Dictionary) -> void:
	eviction = conf.get("eviction", "FIFO").strip_edges()
	flush_interval = type_convert(conf.get("flushInterval", "0").strip_edges(), TYPE_INT)
	size = type_convert(conf.get("size", "1024").strip_edges(), TYPE_INT)
	
func clean():
	pass

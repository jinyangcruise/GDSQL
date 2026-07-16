const TIPS: Array[String] = [
	# -------- BaseDAO 基础用法 --------
	"使用 [b]BaseDao[/b] 时，链式调用即可完成完整查询：[color=#8dbbe6]use_db('db').from('table').select('id','name').where('id == 1').query()[/color]",
	"[b]insert[/b] 的数据可以是 Dictionary 或 Array（批量插入），配合 [color=#8dbbe6]auto_commit(false)[/color] 可先修改内存数据，最后统一 [color=#8dbbe6]commit()[/color] 写入文件。",
	"使用 [b]insert_or_update[/b] 可实现「存在则更新、不存在则插入」的 upsert 语义，配合 [color=#8dbbe6]on_duplicate_update[/color] 指定冲突时更新的字段。",
	"[b]where[/b] 条件支持丰富的表达式：[color=#8dbbe6]==[/color]、[color=#8dbbe6]!=[/color]、[color=#8dbbe6]>[/color]、[color=#8dbbe6]<[/color]、[color=#8dbbe6]in[/color]、[color=#8dbbe6]has[/color]等。",
	"[b]group_by[/b] 和 [b]order_by[/b] 支持使用 select 中定义的别名，例如：select('sum(score) as total').group_by('class_id').order_by('total desc')。",
	"[b]left_join[/b] 支持跨库联表查询，使用 [color=#8dbbe6]left_join_use_same_db_and_pass[/color] 可快速引用主库的联表。",
	"[b]union_all[/b] 可以合并多个查询结果，每个子查询独立调用 [color=#8dbbe6]select_same[/color] 保持字段一致。limit 和 order_by 作用于最终合并后的数据集。",
	"[b]replace_into[/b] 相当于先删除再插入，与 [b]insert_or_update[/b] 不同：replace 会删除旧行重新插入，自增 ID 会变。",

	# -------- SQL 图表面板 --------

	# -------- 表设计 --------
	"数据库名称和表名称对大小写不敏感。例如：DB_FOO、Db_Foo、db_FOo、db_foo，其实都是同一个数据库，可以混用。表名称同理。",
	"字段的 [b]hint[/b] 支持 [color=#8dbbe6]PROPERTY_HINT_ENUM[/color] 和 [color=#8dbbe6]PROPERTY_HINT_ENUM_SUGGESTION[/color]，可在检查器中以下拉菜单形式展示可选值。",

	# -------- 性能优化 --------
	"大批量插入数据时，使用 [color=#8dbbe6]auto_commit(false)[/color] 关闭自动提交，最后手动 [b]commit()[/b]，可显著提升写入性能。",

	# -------- 代码内部实现 / 避坑 --------
	"[b]【内部实现】[/b] 表数据文件是 [b].gsql[/b] 格式，本质上是 Godot 的 [b]ConfigFile[/b] 变体。可以直接用文本编辑器打开查看结构，但手动修改可能导致校验失败。",
	"[b]【避坑】[/b] [color=#8dbbe6]DictionaryObject[/color] 不要手动 [b]free[/b] 或 [b]queue_free[/b]。它是 RefCounted 类型，超出作用域后自动释放。手动释放会导致引用计数异常。",

	# -------- Mapper / gbatis --------
	"Mapper XML 中 [b]result_map[/b] 可以自动映射查询结果到 Godot 对象，支持 [color=#8dbbe6]association[/color]（一对一映射到一个对象属性）和 [color=#8dbbe6]collection[/color]（一对多映射到一个数组）嵌套映射。",

	# -------- 常规操作 --------
	"在 TabBar 上 [b]右键[/b] 可以快速关闭当前页签、关闭其他页签、关闭右侧页签或关闭全部页签。",
	"[b]鼠标中键[/b] 点击页签可直接关闭该页签，无需先切换到该页签再找关闭按钮。",
	"页签可以 [b]拖拽重排[/b]，按住页签拖动即可调整顺序。",
]

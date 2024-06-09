extends RefCounted
class_name GBatisMapperRule

const rule = {
	"cache-ref": {
		"valid_child": [],
		"attr_list": {
			"namespace": {
				"required": true,
				"support": false,
				"desc": ""
			}
		},
		"deprecated": true
	},
	"cache": {
		"valid_child": ["property*"],
		"attr_list": {
			"type": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"eviction": {
				"required": false,
				"support": true,
				"desc": "缓存回收策略，可以不设置，默认值为 LRU（最近最少使用）\n策略。其他可能的值包括 FIFO（先进先出）、\nSOFT（软引用）❌和 WEAK（弱引用）❌"
			},
			"flushInterval": {
				"required": false,
				"support": true,
				"desc": "缓存刷新间隔,单位为毫秒。如果设置为非零值,MyBatis会在指定的时间间隔内自动刷新缓存。"
			},
			"size": {
				"required": false,
				"support": true,
				"desc": "缓存大小,默认值为 1024。如果设置为非零值,MyBatis会在缓存大小超过指定值时开始回收缓存。"
			},
			"readOnly": {
				"required": false,
				"support": false,
				"desc": "是否只读,默认为 false。只读的缓存会给所有调用者返回同一个实例,因此这些对象不能被修改,这提供了性能优势。"
			},
			"blocking": {
				"required": false,
				"support": false,
				"desc": "是否阻塞,默认为 false。"
			}
		},
		"deprecated": false
	},
	"parameterMap": {
		"valid_child": ["parameter*"],
		"attr_list": {
			"id": {
				"required": true,
				"support": true,
				"desc": ""
			},
			"type": {
				"required": true,
				"support": true,
				"desc": ""
			}
		},
		"deprecated": true
	},
	"parameter": {
		"valid_child": [],
		"attr_list": {
			"property": {
				"required": true,
				"support": true,
				"desc": ""
			},
			"javaType": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"jdbcType": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"mode": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"scale": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"typeHandler": {
				"required": false,
				"support": true,
				"desc": ""
			}
		},
		"deprecated": true
	},
	"resultMap": {
		"valid_child": ["constructor?", "id*", "result*", "association*", "collection*", "discriminator?"],
		"attr_list": {
			"id": {
				"required": true,
				"support": true,
				"desc": "唯一性标识"
			},
			"type": {
				"required": true,
				"support": true,
				"desc": """gdscript variant type or a class name,
eg. int, String, SysDept, Dictionary
				"""
			},
			"extends": {
				"required": false,
				"support": true,
				"desc": """extends 属性允许一个 resultMap 继承另一个 resultMap 
的配置。这意味着你可以创建一个基础的 resultMap，然后创建
其他 resultMap 来继承这个基础配置，从而避免重复定义相同
的映射规则。另一方面，对被继承的配置还有覆盖能力（如果定义
了相同的property）。
				"""
			},
			"autoMapping": {
				"required": false,
				"support": true,
				"desc": """是否继承全局自动映射等级。
Regardless of the auto-mapping level 
configured you can enable or disable the 
automapping for an specific ResultMap by 
adding the attribute autoMapping to it.

default: unset 按全局
true: automapp properties when 
	  related columns are selected but not 
	  configured;
false: do not automap columns to 
	   properties which are not configured.
				"""
			}
		},
		"deprecated": false
	},
	"id": {
		"valid_child": [],
		"attr_list": {
			"property": {
				"required": true,
				"support": true,
				"desc": "Object's property name"
			},
			"javaType": {
				"required": false,
				"support": true,
				"desc": """gdscript variant type or a class name, 
eg. int, String, SysDept, Dictionary
				"""
			},
			"column": {
				"required": true,
				"support": true,
				"desc": "Column name of ResultSet."
			},
			"jdbcType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"typeHandler": {
				"required": false,
				"support": false,
				"desc": ""
			}
		},
		"deprecated": false
	},
	"result": {
		"valid_child": [],
		"attr_list": {
			"property": {
				"required": true,
				"support": true,
				"desc": "Object's property name"
			},
			"javaType": {
				"required": false,
				"support": true,
				"desc": """gdscript variant type or a class name, 
eg. int, String, SysDept, Dictionary
				"""
			},
			"column": {
				"required": true,
				"support": true,
				"desc": "Column name of ResultSet."
			},
			"jdbcType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"typeHandler": {
				"required": false,
				"support": false,
				"desc": ""
			}
		},
		"deprecated": false
	},
	"idArg": {
		"valid_child": [],
		"attr_list": {
			"javaType": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"column": {
				"required": true,
				"support": true,
				"desc": ""
			},
			"jdbcType": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"typeHandler": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"select": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"name": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"columnPrefix": {
				"required": false,
				"support": true,
				"desc": ""
			}
		},
		"deprecated": true
	},
	"arg": {
		"valid_child": [],
		"attr_list": {
			"javaType": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"column": {
				"required": true,
				"support": true,
				"desc": ""
			},
			"jdbcType": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"typeHandler": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"select": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"name": {
				"required": false,
				"support": true,
				"desc": ""
			},
			"columnPrefix": {
				"required": false,
				"support": true,
				"desc": ""
			}
		},
		"deprecated": true
	},
	"collection": {
		"valid_child": ["constructor?", "id*", "result*", "association*", "collection*", "discriminator?"],
		"attr_list": {
			"property": {
				"required": true,
				"support": true,
				"desc": "Object's property name"
			},
			"javaType": {
				"required": false,
				"support": true,
				"desc": """ClassName
如果obj中的property属性没有定义是什么类型的对象，
则需要在此指定一下。
				"""
			},
			"ofType": {
				"required": false,
				"support": true,
				"desc": "集合元素的GdScript类型"
			},
			"jdbcType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"typeHandler": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"column": {
				"required": false,
				"support": true,
				"desc": """集合的嵌套 Select 查询：
associate column name. When using multiple 
resultset this attribute specifies the 
columns (separated by commas) that will be 
correlated with the foreignColumn to identify
the parent and the child of a relationship.
NOTICE column belongs to parent fetch.
				"""
			},
			"select": {
				"required": false,
				"support": true,
				"desc": """集合的嵌套 Select 查询：
auto fetch data by configured <select>'s 
id when needed. If this attr is set, then 
NRM(Nested Result Mapping) which uses 
some `JOIN`s will not work.
				"""
			},
			"fetchType": {
				"required": false,
				"support": false,
				"desc": """集合的嵌套 Select 查询：
INFO _get() will not be
called if properties are defined in 
Object. So we couldn't find a proper
way to achieve this lazy feature.

lazy: [default] fetch data when this 
	  property is getted;
eager: fetch data immediately.
				"""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": """集合的嵌套结果映射：
configured result map.
				"""
			},
			"columnPrefix": {
				"required": false,
				"support": true,
				"desc": """集合的嵌套结果映射：
当连接多个表时，你可能会不得不使用列别名来避免在 
ResultSet 中产生重复的列名。指定 columnPrefix 
列名前缀允许你将带有这些前缀的列映射到一个外部的
结果映射中。这在结果集中拥有多个相同类型的子对象时
很有用，可以共享同一个resultMap，但是又用前缀做了
区分。
				"""
			},
			"notNullColumn": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"autoMapping": {
				"required": false,
				"support": true,
				"desc": """集合的嵌套结果映射：
是否继承全局自动映射等级。
Regardless of the auto-mapping level 
configured you can enable or disable the 
automapping for an specific ResultMap by 
adding the attribute autoMapping to it.

default: unset 按全局
true: automapp properties when 
	  related columns are selected but not 
	  configured;
false: do not automap columns to 
	   properties which are not configured.
				"""
			}
		},
		"deprecated": false
	},
	"association": {
		"valid_child": ["constructor?", "id*", "result*", "association*", "collection*", "discriminator?"],
		"attr_list": {
			"property": {
				"required": true,
				"support": true,
				"desc": "property name"
			},
			"javaType": {
				"required": false,
				"support": true,
				"desc": """ClassName
如果obj中的property属性没有定义是什么类型的对象，
则需要在此指定一下。
				"""
			},
			"jdbcType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"typeHandler": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"column": {
				"required": false,
				"support": true,
				"desc": """关联的嵌套 Select 查询：
associate column name. When using multiple 
resultset this attribute specifies the 
columns (separated by commas) that will be 
correlated with the foreignColumn to identify
the parent and the child of a relationship.
NOTICE column belongs to parent fetch.
				"""
			},
			"select": {
				"required": false,
				"support": true,
				"desc": """关联的嵌套 Select 查询：
auto fetch data by configured <select>'s 
id when needed. If this attr is set, then 
NRM(Nested Result Mapping) which uses 
some `JOIN`s will not work.
				"""
			},
			"fetchType": {
				"required": false,
				"support": false,
				"desc": """关联的嵌套 Select 查询：
INFO _get() will not be
called if properties are defined in 
Object. So we couldn't find a proper
way to achieve this lazy feature.

lazy: [default] fetch data when this 
	  property is getted;
eager: fetch data immediately.
				"""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": """关联的嵌套结果映射：
configured result map.
				"""
			},
			"columnPrefix": {
				"required": false,
				"support": true,
				"desc": """关联的嵌套结果映射：
当连接多个表时，你可能会不得不使用列别名来避免在 
ResultSet 中产生重复的列名。指定 columnPrefix 
列名前缀允许你将带有这些前缀的列映射到一个外部的
结果映射中。这在结果集中拥有多个相同类型的子对象时
很有用，可以共享同一个resultMap，但是又用前缀做了
区分。
				"""
			},
			"notNullColumn": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"autoMapping": {
				"required": false,
				"support": true,
				"desc": """关联的嵌套结果映射：
是否继承全局自动映射等级。
Regardless of the auto-mapping level 
configured you can enable or disable the 
automapping for an specific ResultMap by 
adding the attribute autoMapping to it.

default: unset 按全局
true: automapp properties when 
	  related columns are selected but not 
	  configured;
false: do not automap columns to 
	   properties which are not configured.
				"""
			}
		},
		"deprecated": false
	},
	"discriminator": {
		"valid_child": ["case+"],
		"attr_list": {
			"column": {
				"required": true,
				"support": true,
				"desc": "Column name of ResultSet."
			},
			"javaType": {
				"required": true,
				"support": true,
				"desc": """gdscript simple variant type. 
eg. int, String, bool
				"""
			},
			"jdbcType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"typeHandler": {
				"required": false,
				"support": false,
				"desc": ""
			}
		},
		"deprecated": false
	},
	"case": {
		"valid_child": [],
		"attr_list": {
			"value": {
				"required": true,
				"support": true,
				"desc": "Value of parent discriminator's column."
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": "Configured resultMap id."
			},
			"resultType": {
				"required": false,
				"support": true,
				"desc": "Class name of Object."
			}
		},
		"deprecated": false
	},
	"property": {
		"valid_child": [],
		"attr_list": {
			"name": {
				"required": true,
				"support": true,
				"desc": ""
			},
			"value": {
				"required": true,
				"support": true,
				"desc": ""
			}
		},
		"deprecated": true
	},
	"typeAlias": {
		"valid_child": [],
		"attr_list": {
			"alias": {
				"required": true,
				"support": true,
				"desc": ""
			},
			"type": {
				"required": true,
				"support": true,
				"desc": ""
			}
		},
		"deprecated": true
	},
	"select": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {
			"id": {
				"required": true,
				"support": true,
				"desc": "唯一性id"
			},
			"parameterMap": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"parameterType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": "Configured resultMap id."
			},
			"resultType": {
				"required": false,
				"support": true,
				"desc": "Class name."
			},
			"resultSetType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"statementType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"fetchSize": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"timeout": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"flushCache": {
				"required": false,
				"support": true,
				"desc": "Clear cache before select."
			},
			"useCache": {
				"required": false,
				"support": true,
				"desc": "Use cached data."
			},
			"databaseId": {
				"required": false,
				"support": true,
				"desc": "Use database name."
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"resultOrdered": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"resultSets": {
				"required": false,
				"support": false,
				"desc": """Identifies the name of 
the result set where this complex type 
will be loaded from. 
eg. resultSets="blogs,authors"
				"""
			}
		},
		"deprecated": false
	},
	"insert": {
		"valid_child": ["#PCDATA", "selectKey", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {
			"id": {
				"required": true,
				"support": true,
				"desc": "唯一性id"
			},
			"parameterMap": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"parameterType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"timeout": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"flushCache": {
				"required": false,
				"support": true,
				"desc": "Clear cache. default: true"
			},
			"statementType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"useGeneratedKeys": {
				"required": false,
				"support": true,
				"desc": "将自动生成字段值填充到Obj中，比如自增键、填充了默认值的字段。"
			},
			"keyProperty": {
				"required": false,
				"support": true,
				"desc": """由数据库内部生成的主键对应的对象
的属性或字典的键，多个用逗号分割，
配合useGeneratedKeys使用，如
果useGeneratedKeys为true，但
是未配置该特性，则默认属性和列名
完全相同时，才进行设置。
				"""
			},
			"keyColumn": {
				"required": false,
				"support": true,
				"desc": """keyProperty对应的列名。如果
property和column名称一样，可
以省略该特性；否则请按照和
keyProperty相同的顺序填写相应
的列名。
				"""
			},
			"databaseId": {
				"required": false,
				"support": true,
				"desc": "Use database name."
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": ""
			}
		},
		"deprecated": false
	},
	"replace": {
		"valid_child": ["#PCDATA", "selectKey", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {
			"id": {
				"required": true,
				"support": true,
				"desc": "唯一性id"
			},
			"parameterMap": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"parameterType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"timeout": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"flushCache": {
				"required": false,
				"support": true,
				"desc": "Clear cache. default: true"
			},
			"statementType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"useGeneratedKeys": {
				"required": false,
				"support": true,
				"desc": "将自动生成字段值填充到Obj中，比如自增键、填充了默认值的字段。"
			},
			"keyProperty": {
				"required": false,
				"support": true,
				"desc": """由数据库内部生成的主键对应的对象
的属性或字典的键，多个用逗号分割，
配合useGeneratedKeys使用，如
果useGeneratedKeys为true，但
是未配置该特性，则默认属性和列名
完全相同时，才进行设置。
				"""
			},
			"keyColumn": {
				"required": false,
				"support": true,
				"desc": """keyProperty对应的列名。如果
property和column名称一样，可
以省略该特性；否则请按照和
keyProperty相同的顺序填写相应
的列名。
				"""
			},
			"databaseId": {
				"required": false,
				"support": true,
				"desc": "Use database name."
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": ""
			}
		},
		"deprecated": false
	},
	"update": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {
			"id": {
				"required": true,
				"support": true,
				"desc": "唯一性id"
			},
			"parameterMap": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"parameterType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"timeout": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"flushCache": {
				"required": false,
				"support": true,
				"desc": "Clear cache. Default: true"
			},
			"statementType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"databaseId": {
				"required": false,
				"support": true,
				"desc": "Use database name."
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": ""
			}
		},
		"deprecated": false
	},
	"delete": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {
			"id": {
				"required": true,
				"support": true,
				"desc": "唯一性id"
			},
			"parameterMap": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"parameterType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"timeout": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"flushCache": {
				"required": false,
				"support": true,
				"desc": "Clear cache. Default: true"
			},
			"statementType": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"databaseId": {
				"required": false,
				"support": true,
				"desc": "Use database name."
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": ""
			}
		},
		"deprecated": false
	},
	"selectKey": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {
		},
		"deprecated": true
	},
	"include": {
		"valid_child": ["property+"],
		"attr_list": {
			"refid": {
				"required": true,
				"support": true,
				"desc": "引用的sql的id"
			}
		},
		"deprecated": false
	},
	"bind": {
		"valid_child": [],
		"attr_list": {
			"name": {
				"required": true,
				"support": true,
				"desc": "绑定的变量名称"
			},
			"value": {
				"required": true,
				"support": true,
				"desc": "绑定的变量值"
			}
		},
		"deprecated": false
	},
	"sql": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {
			"id": {
				"required": true,
				"support": true,
				"desc": "唯一性id"
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": ""
			},
			"databaseId": {
				"required": false,
				"support": false,
				"desc": ""
			}
		},
		"deprecated": false
	},
	"trim": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {
			"prefix": {
				"required": false,
				"support": true,
				"desc": "在trim包裹的SQL语句前面添加的指定内容。"
			},
			"suffix": {
				"required": false,
				"support": true,
				"desc": "表示在trim包裹的SQL末尾添加指定内容"
			},
			"prefixOverrides": {
				"required": false,
				"support": true,
				"desc": "去掉（覆盖）trim包裹的SQL的指定首部内容"
			},
			"suffixOverrides": {
				"required": false,
				"support": true,
				"desc": "去掉（覆盖）trim包裹的SQL的指定尾部内容"
			}
		},
		"deprecated": false
	},
	"where": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {},
		"deprecated": false
	},
	"set": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {},
		"deprecated": false
	},
	"foreach": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {
			"collection": {
				"required": true,
				"support": true,
				"desc": "要遍历的集合或数组的变量名称"
			},
			"item": {
				"required": false,
				"support": true,
				"desc": "设置每次迭代变量的名称"
			},
			"index": {
				"required": false,
				"support": true,
				"desc": "若遍历的是list，index代表下标；若遍历的是map，index代表键"
			},
			"open": {
				"required": false,
				"support": true,
				"desc": "设置循环体的开始内容"
			},
			"close": {
				"required": false,
				"support": true,
				"desc": "设置循环体的结束内容"
			},
			"separator": {
				"required": false,
				"support": true,
				"desc": "设置每一次循环之间的分隔符"
			}
		},
		"deprecated": false
	},
	"choose": {
		"valid_child": ["when*", "otherwise?"],
		"attr_list": {},
		"deprecated": false
	},
	"when": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {
			"test": {
				"required": true,
				"support": true,
				"desc": "检查条件"
			}
		},
		"deprecated": false
	},
	"otherwise": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {},
		"deprecated": false
	},
	"if": {
		"valid_child": ["#PCDATA", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"],
		"attr_list": {
			"test": {
				"required": true,
				"support": true,
				"desc": "检查条件"
			}
		},
		"deprecated": false
	}
}

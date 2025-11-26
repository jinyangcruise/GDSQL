extends RefCounted

const rule = {
	"cache-ref": {
		"valid_child": [],
		"attr_list": {
			"namespace": {
				"required": true,
				"support": false,
				"desc": "",
				"default": ""
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
				"desc": "",
				"default": ""
			},
			"eviction": {
				"required": false,
				"support": true,
				"desc": "缓存回收策略，可以不设置，默认值为 LRU（最近最少使用）\n策略。其他可能的值包括 FIFO（先进先出）、\nSOFT（软引用）❌和 WEAK（弱引用）❌",
				"default": "LRU"
			},
			"flushInterval": {
				"required": false,
				"support": true,
				"desc": "缓存刷新间隔,单位为毫秒。如果设置为非零值,MyBatis会在指定的时间间隔内自动刷新缓存。",
				"default": "0"
			},
			"size": {
				"required": false,
				"support": true,
				"desc": "缓存大小,默认值为 1024。如果设置为非零值,MyBatis会在缓存大小超过指定值时开始回收缓存。",
				"default": "1024"
			},
			"readOnly": {
				"required": false,
				"support": false,
				"desc": "是否只读,默认为 false。只读的缓存会给所有调用者返回同一个实例,因此这些对象不能被修改,这提供了性能优势。",
				"default": "false"
			},
			"blocking": {
				"required": false,
				"support": false,
				"desc": "是否阻塞,默认为 false。",
				"default": "false"
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
				"desc": "",
				"default": ""
			},
			"type": {
				"required": true,
				"support": true,
				"desc": "",
				"default": ""
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
				"desc": "",
				"default": ""
			},
			"javaType": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"jdbcType": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"mode": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"scale": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"typeHandler": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
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
				"desc": "唯一性标识",
				"default": ""
			},
			"type": {
				"required": true,
				"support": true,
				"desc": """gdscript variant type or a class name,
eg. int, String, SysDept, Dictionary
				""",
				"default": ""
			},
			"extends": {
				"required": false,
				"support": true,
				"desc": """extends 属性允许一个 resultMap 继承另一个 resultMap 
的配置。这意味着你可以创建一个基础的 resultMap，然后创建
其他 resultMap 来继承这个基础配置，从而避免重复定义相同
的映射规则。另一方面，对被继承的配置还有覆盖能力（如果定义
了相同的property）。
				""",
				"default": ""
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
				""",
				"default": ""
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
				"desc": "Object's property name",
				"default": ""
			},
			"javaType": {
				"required": false,
				"support": true,
				"desc": """gdscript variant type or a class name, 
eg. int, String, SysDept, Dictionary
				""",
				"default": ""
			},
			"column": {
				"required": true,
				"support": true,
				"desc": "Column name of ResultSet.",
				"default": ""
			},
			"jdbcType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"typeHandler": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				"desc": "Object's property name",
				"default": ""
			},
			"javaType": {
				"required": false,
				"support": true,
				"desc": """gdscript variant type or a class name, 
eg. int, String, SysDept, Dictionary
				""",
				"default": ""
			},
			"column": {
				"required": true,
				"support": true,
				"desc": "Column name of ResultSet.",
				"default": ""
			},
			"jdbcType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"typeHandler": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				"desc": "",
				"default": ""
			},
			"column": {
				"required": true,
				"support": true,
				"desc": "",
				"default": ""
			},
			"jdbcType": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"typeHandler": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"select": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"name": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"columnPrefix": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
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
				"desc": "",
				"default": ""
			},
			"column": {
				"required": true,
				"support": true,
				"desc": "",
				"default": ""
			},
			"jdbcType": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"typeHandler": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"select": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"name": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
			},
			"columnPrefix": {
				"required": false,
				"support": true,
				"desc": "",
				"default": ""
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
				"desc": "Object's property name",
				"default": ""
			},
			"javaType": {
				"required": false,
				"support": true,
				"desc": """ClassName,
如果obj中的property属性没有定义是什么类型的对象，
则需要在此指定一下。
				""",
				"default": ""
			},
			"ofType": {
				"required": false,
				"support": true,
				"desc": "集合元素的GdScript类型",
				"default": ""
			},
			"jdbcType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"typeHandler": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				""",
				"default": ""
			},
			"select": {
				"required": false,
				"support": true,
				"desc": """集合的嵌套 Select 查询：
auto fetch data by configured <select>'s 
id when needed. If this attr is set, then 
NRM(Nested Result Mapping) which uses 
some `JOIN`s will not work.
				""",
				"default": ""
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
				""",
				"default": ""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": """集合的嵌套结果映射：
configured result map.
				""",
				"default": ""
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
				""",
				"default": ""
			},
			"notNullColumn": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				""",
				"default": ""
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
				"desc": "property name",
				"default": ""
			},
			"javaType": {
				"required": false,
				"support": true,
				"desc": """ClassName,
如果obj中的property属性没有定义是什么类型的对象，
则需要在此指定一下。
				""",
				"default": ""
			},
			"jdbcType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"typeHandler": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				""",
				"default": ""
			},
			"select": {
				"required": false,
				"support": true,
				"desc": """关联的嵌套 Select 查询：
auto fetch data by configured <select>'s 
id when needed. If this attr is set, then 
NRM(Nested Result Mapping) which uses 
some `JOIN`s will not work.
				""",
				"default": ""
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
				""",
				"default": "lazy"
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": """关联的嵌套结果映射：
configured result map.
				""",
				"default": ""
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
				""",
				"default": ""
			},
			"notNullColumn": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				""",
				"default": ""
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
				"desc": "Column name of ResultSet.",
				"default": ""
			},
			"javaType": {
				"required": true,
				"support": true,
				"desc": """gdscript simple variant type. 
eg. int, String, bool
				""",
				"default": ""
			},
			"jdbcType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"typeHandler": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				"desc": "Value of parent discriminator's column.",
				"default": ""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": "Configured resultMap id.",
				"default": ""
			},
			"resultType": {
				"required": false,
				"support": true,
				"desc": "Class name of Object.",
				"default": ""
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
				"desc": "",
				"default": ""
			},
			"value": {
				"required": true,
				"support": true,
				"desc": "",
				"default": ""
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
				"desc": "",
				"default": ""
			},
			"type": {
				"required": true,
				"support": true,
				"desc": "",
				"default": ""
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
				"desc": "唯一性id",
				"default": ""
			},
			"parameterMap": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"parameterType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"resultMap": {
				"required": false,
				"support": true,
				"desc": "Configured resultMap id.",
				"default": ""
			},
			"resultType": {
				"required": false,
				"support": true,
				"desc": "Class name.",
				"default": ""
			},
			"resultSetType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"statementType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"fetchSize": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"timeout": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"flushCache": {
				"required": false,
				"support": true,
				"desc": "Clear cache before select.",
				"default": "false"
			},
			"useCache": {
				"required": false,
				"support": true,
				"desc": "Use cached data.",
				"default": "true"
			},
			"databaseId": {
				"required": false,
				"support": true,
				"desc": "Use database name.",
				"default": ""
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"resultOrdered": {
				"required": false,
				"support": false,
				"desc": "",
				"default": "false"
			},
			"resultSets": {
				"required": false,
				"support": false,
				"desc": """Identifies the name of 
the result set where this complex type 
will be loaded from. 
eg. resultSets="blogs,authors"
				""",
				"default": ""
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
				"desc": "唯一性id",
				"default": ""
			},
			"parameterMap": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"parameterType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"timeout": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"flushCache": {
				"required": false,
				"support": true,
				"desc": "Clear cache. default: true",
				"default": "true"
			},
			"statementType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"useGeneratedKeys": {
				"required": false,
				"support": true,
				"desc": "将自动生成字段值填充到Obj中，比如自增键、填充了默认值的字段。",
				"default": "false"
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
				""",
				"default": ""
			},
			"keyColumn": {
				"required": false,
				"support": true,
				"desc": """keyProperty对应的列名。如果
property和column名称一样，可
以省略该特性；否则请按照和
keyProperty相同的顺序填写相应
的列名。
				""",
				"default": ""
			},
			"databaseId": {
				"required": false,
				"support": true,
				"desc": "Use database name.",
				"default": ""
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				"desc": "唯一性id",
				"default": ""
			},
			"parameterMap": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"parameterType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"timeout": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"flushCache": {
				"required": false,
				"support": true,
				"desc": "Clear cache. default: true",
				"default": "true"
			},
			"statementType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"useGeneratedKeys": {
				"required": false,
				"support": true,
				"desc": "将自动生成字段值填充到Obj中，比如自增键、填充了默认值的字段。",
				"default": "false"
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
				""",
				"default": ""
			},
			"keyColumn": {
				"required": false,
				"support": true,
				"desc": """keyProperty对应的列名。如果
property和column名称一样，可
以省略该特性；否则请按照和
keyProperty相同的顺序填写相应
的列名。
				""",
				"default": ""
			},
			"databaseId": {
				"required": false,
				"support": true,
				"desc": "Use database name.",
				"default": ""
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				"desc": "唯一性id",
				"default": ""
			},
			"parameterMap": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"parameterType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"timeout": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"flushCache": {
				"required": false,
				"support": true,
				"desc": "Clear cache. Default: true",
				"default": "true"
			},
			"statementType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"databaseId": {
				"required": false,
				"support": true,
				"desc": "Use database name.",
				"default": ""
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				"desc": "唯一性id",
				"default": ""
			},
			"parameterMap": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"parameterType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"timeout": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"flushCache": {
				"required": false,
				"support": true,
				"desc": "Clear cache. Default: true",
				"default": "true"
			},
			"statementType": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"databaseId": {
				"required": false,
				"support": true,
				"desc": "Use database name.",
				"default": ""
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				"desc": "引用的sql的id",
				"default": ""
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
				"desc": "绑定的变量名称",
				"default": ""
			},
			"value": {
				"required": true,
				"support": true,
				"desc": "绑定的变量值",
				"default": ""
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
				"desc": "唯一性id",
				"default": ""
			},
			"lang": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
			},
			"databaseId": {
				"required": false,
				"support": false,
				"desc": "",
				"default": ""
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
				"desc": "在trim包裹的SQL语句前面添加的指定内容。",
				"default": ""
			},
			"suffix": {
				"required": false,
				"support": true,
				"desc": "表示在trim包裹的SQL末尾添加指定内容",
				"default": ""
			},
			"prefixOverrides": {
				"required": false,
				"support": true,
				"desc": "去掉（覆盖）trim包裹的SQL的指定首部内容",
				"default": ""
			},
			"suffixOverrides": {
				"required": false,
				"support": true,
				"desc": "去掉（覆盖）trim包裹的SQL的指定尾部内容",
				"default": ""
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
				"desc": "要遍历的集合或数组的变量名称",
				"default": ""
			},
			"item": {
				"required": false,
				"support": true,
				"desc": "设置每次迭代变量的名称",
				"default": ""
			},
			"index": {
				"required": false,
				"support": true,
				"desc": "若遍历的是list，index代表下标；若遍历的是map，index代表键",
				"default": ""
			},
			"open": {
				"required": false,
				"support": true,
				"desc": "设置循环体的开始内容",
				"default": ""
			},
			"close": {
				"required": false,
				"support": true,
				"desc": "设置循环体的结束内容",
				"default": ""
			},
			"separator": {
				"required": false,
				"support": true,
				"desc": "设置每一次循环之间的分隔符",
				"default": ""
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
				"desc": "检查条件",
				"default": ""
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
				"desc": "检查条件",
				"default": ""
			}
		},
		"deprecated": false
	}
}

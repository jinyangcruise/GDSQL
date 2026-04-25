@tool
extends RefCounted

## SQL模式。
## true：开启SQL模式，那么涉及到null的运算始终返回null，AggregateFunctions对象可以参与运算。
## false：gdscript常规语法
var sql_mode: bool = false

var inputs: Array
var output_type: int = TYPE_NIL
var expression: String
var sequenced = false
var str_ofs = 0
var expression_dirty = false

enum TokenType {
	TK_CURLY_BRACKET_OPEN, # 0
	TK_CURLY_BRACKET_CLOSE,
	TK_BRACKET_OPEN,
	TK_BRACKET_CLOSE,
	TK_PARENTHESIS_OPEN,
	TK_PARENTHESIS_CLOSE, # 5
	TK_IDENTIFIER,
	TK_BUILTIN_FUNC,
	TK_SELF,
	TK_CONSTANT,
	TK_BASIC_TYPE, # 10
	TK_COLON,
	TK_COMMA,
	TK_PERIOD,
	TK_OP_IN,
	TK_OP_EQUAL,
	TK_OP_NOT_EQUAL,
	TK_OP_LESS,
	TK_OP_LESS_EQUAL,
	TK_OP_GREATER,
	TK_OP_GREATER_EQUAL, # 20
	TK_OP_AND,
	TK_OP_OR,
	TK_OP_NOT,
	TK_OP_ADD,
	TK_OP_SUB, # 25
	TK_OP_MUL,
	TK_OP_DIV,
	TK_OP_MOD,
	TK_OP_POW,
	TK_OP_SHIFT_LEFT, # 30
	TK_OP_SHIFT_RIGHT,
	TK_OP_BIT_AND,
	TK_OP_BIT_OR,
	TK_OP_BIT_XOR,
	TK_OP_BIT_INVERT,
	TK_INPUT,
	TK_EOF,
	TK_ERROR,
	TK_MAX # 39
}

const token_name: Array = [
	"CURLY BRACKET OPEN",
	"CURLY BRACKET CLOSE",
	"BRACKET OPEN",
	"BRACKET CLOSE",
	"PARENTHESIS OPEN",
	"PARENTHESIS CLOSE",
	"IDENTIFIER",
	"BUILTIN FUNC",
	"SELF",
	"CONSTANT",
	"BASIC TYPE",
	"COLON",
	"COMMA",
	"PERIOD",
	"OP IN",
	"OP EQUAL",
	"OP NOT EQUAL",
	"OP LESS",
	"OP LESS EQUAL",
	"OP GREATER",
	"OP GREATER EQUAL",
	"OP AND",
	"OP OR",
	"OP NOT",
	"OP ADD",
	"OP SUB",
	"OP MUL",
	"OP DIV",
	"OP MOD",
	"OP POW",
	"OP SHIFT LEFT",
	"OP SHIFT RIGHT",
	"OP BIT AND",
	"OP BIT OR",
	"OP BIT XOR",
	"OP BIT INVERT",
	"OP INPUT",
	"EOF",
	"ERROR"
]

var error_str
var error_set = true
var show_error = false

var root: ExpressionENode
var nodes: ExpressionENode

var input_names: Array
var execution_error = false

# sql_input_names 的结构：
# {
#     'x': {
#         true: 0,			# true表示x是一个普通表名
#         false: index,		# false表示x是一个补充表名（来自BaseDao的__input_names）
#         'y': 0,			# 字符串表示x是一个普通表y中的一个字段
#         N: 0,				# 整数表示x是一个补充表中的一个字段，N表示该表在__input_names中的位置
#     }
# }
var sql_input_names: Dictionary
# 固定补充数据。数组中元素的位置和sql_input_names中的某个字段的false字段的index相对应
var sql_static_inputs: Array
## 嵌套的sql
var nested_sql_queries: Dictionary

## sql模式表达式中包含了没有被放入input_names中的变量名
var lack_input_names: Array

const READING_SIGN = 0
const READING_INT = 1
const READING_HEX = 2
const READING_BIN = 3
const READING_DEC = 4
const READING_EXP = 5
const READING_DONE = 6

## 通过控制该值，可以让parse提前结束
const MAX_INT = 9223372036854775807
var max_str_ofs = MAX_INT

## 引擎自带Expression的缓存
static var EXPRESSION_CACHE: ExpressionLRULink

const xid_start = [
	 [ 0x41, 0x5a ],
	 [ 0x5f, 0x5f ],
	 [ 0x61, 0x7a ],
	 [ 0xaa, 0xaa ],
	 [ 0xb5, 0xb5 ],
	 [ 0xba, 0xba ],
	 [ 0xc0, 0xd6 ],
	 [ 0xd8, 0xf6 ],
	 [ 0xf8, 0x2c1 ],
	 [ 0x2c6, 0x2d1 ],
	 [ 0x2e0, 0x2e4 ],
	 [ 0x2ec, 0x2ec ],
	 [ 0x2ee, 0x2ee ],
	 [ 0x370, 0x374 ],
	 [ 0x376, 0x377 ],
	 [ 0x37a, 0x37d ],
	 [ 0x37f, 0x37f ],
	 [ 0x386, 0x386 ],
	 [ 0x388, 0x38a ],
	 [ 0x38c, 0x38c ],
	 [ 0x38e, 0x3a1 ],
	 [ 0x3a3, 0x3f5 ],
	 [ 0x3f7, 0x481 ],
	 [ 0x48a, 0x52f ],
	 [ 0x531, 0x556 ],
	 [ 0x559, 0x559 ],
	 [ 0x560, 0x588 ],
	 [ 0x5d0, 0x5ea ],
	 [ 0x5ef, 0x5f2 ],
	 [ 0x620, 0x64a ],
	 [ 0x66e, 0x66f ],
	 [ 0x671, 0x6d3 ],
	 [ 0x6d5, 0x6d5 ],
	 [ 0x6e5, 0x6e6 ],
	 [ 0x6ee, 0x6ef ],
	 [ 0x6fa, 0x6fc ],
	 [ 0x6ff, 0x6ff ],
	 [ 0x710, 0x710 ],
	 [ 0x712, 0x72f ],
	 [ 0x74d, 0x7a5 ],
	 [ 0x7b1, 0x7b1 ],
	 [ 0x7ca, 0x7ea ],
	 [ 0x7f4, 0x7f5 ],
	 [ 0x7fa, 0x7fa ],
	 [ 0x800, 0x815 ],
	 [ 0x81a, 0x81a ],
	 [ 0x824, 0x824 ],
	 [ 0x828, 0x828 ],
	 [ 0x840, 0x858 ],
	 [ 0x860, 0x86a ],
	 [ 0x870, 0x887 ],
	 [ 0x889, 0x88e ],
	 [ 0x8a0, 0x8c9 ],
	 [ 0x904, 0x939 ],
	 [ 0x93d, 0x93d ],
	 [ 0x950, 0x950 ],
	 [ 0x958, 0x961 ],
	 [ 0x971, 0x980 ],
	 [ 0x985, 0x98c ],
	 [ 0x98f, 0x990 ],
	 [ 0x993, 0x9a8 ],
	 [ 0x9aa, 0x9b0 ],
	 [ 0x9b2, 0x9b2 ],
	 [ 0x9b6, 0x9b9 ],
	 [ 0x9bd, 0x9bd ],
	 [ 0x9ce, 0x9ce ],
	 [ 0x9dc, 0x9dd ],
	 [ 0x9df, 0x9e1 ],
	 [ 0x9f0, 0x9f1 ],
	 [ 0x9fc, 0x9fc ],
	 [ 0xa05, 0xa0a ],
	 [ 0xa0f, 0xa10 ],
	 [ 0xa13, 0xa28 ],
	 [ 0xa2a, 0xa30 ],
	 [ 0xa32, 0xa33 ],
	 [ 0xa35, 0xa36 ],
	 [ 0xa38, 0xa39 ],
	 [ 0xa59, 0xa5c ],
	 [ 0xa5e, 0xa5e ],
	 [ 0xa72, 0xa74 ],
	 [ 0xa85, 0xa8d ],
	 [ 0xa8f, 0xa91 ],
	 [ 0xa93, 0xaa8 ],
	 [ 0xaaa, 0xab0 ],
	 [ 0xab2, 0xab3 ],
	 [ 0xab5, 0xab9 ],
	 [ 0xabd, 0xabd ],
	 [ 0xad0, 0xad0 ],
	 [ 0xae0, 0xae1 ],
	 [ 0xaf9, 0xaf9 ],
	 [ 0xb05, 0xb0c ],
	 [ 0xb0f, 0xb10 ],
	 [ 0xb13, 0xb28 ],
	 [ 0xb2a, 0xb30 ],
	 [ 0xb32, 0xb33 ],
	 [ 0xb35, 0xb39 ],
	 [ 0xb3d, 0xb3d ],
	 [ 0xb5c, 0xb5d ],
	 [ 0xb5f, 0xb61 ],
	 [ 0xb71, 0xb71 ],
	 [ 0xb83, 0xb83 ],
	 [ 0xb85, 0xb8a ],
	 [ 0xb8e, 0xb90 ],
	 [ 0xb92, 0xb95 ],
	 [ 0xb99, 0xb9a ],
	 [ 0xb9c, 0xb9c ],
	 [ 0xb9e, 0xb9f ],
	 [ 0xba3, 0xba4 ],
	 [ 0xba8, 0xbaa ],
	 [ 0xbae, 0xbb9 ],
	 [ 0xbd0, 0xbd0 ],
	 [ 0xc05, 0xc0c ],
	 [ 0xc0e, 0xc10 ],
	 [ 0xc12, 0xc28 ],
	 [ 0xc2a, 0xc39 ],
	 [ 0xc3d, 0xc3d ],
	 [ 0xc58, 0xc5a ],
	 [ 0xc5d, 0xc5d ],
	 [ 0xc60, 0xc61 ],
	 [ 0xc80, 0xc80 ],
	 [ 0xc85, 0xc8c ],
	 [ 0xc8e, 0xc90 ],
	 [ 0xc92, 0xca8 ],
	 [ 0xcaa, 0xcb3 ],
	 [ 0xcb5, 0xcb9 ],
	 [ 0xcbd, 0xcbd ],
	 [ 0xcdd, 0xcde ],
	 [ 0xce0, 0xce1 ],
	 [ 0xcf1, 0xcf2 ],
	 [ 0xd04, 0xd0c ],
	 [ 0xd0e, 0xd10 ],
	 [ 0xd12, 0xd3a ],
	 [ 0xd3d, 0xd3d ],
	 [ 0xd4e, 0xd4e ],
	 [ 0xd54, 0xd56 ],
	 [ 0xd5f, 0xd61 ],
	 [ 0xd7a, 0xd7f ],
	 [ 0xd85, 0xd96 ],
	 [ 0xd9a, 0xdb1 ],
	 [ 0xdb3, 0xdbb ],
	 [ 0xdbd, 0xdbd ],
	 [ 0xdc0, 0xdc6 ],
	 [ 0xe01, 0xe30 ],
	 [ 0xe32, 0xe33 ],
	 [ 0xe40, 0xe46 ],
	 [ 0xe81, 0xe82 ],
	 [ 0xe84, 0xe84 ],
	 [ 0xe86, 0xe8a ],
	 [ 0xe8c, 0xea3 ],
	 [ 0xea5, 0xea5 ],
	 [ 0xea7, 0xeb0 ],
	 [ 0xeb2, 0xeb3 ],
	 [ 0xebd, 0xebd ],
	 [ 0xec0, 0xec4 ],
	 [ 0xec6, 0xec6 ],
	 [ 0xedc, 0xedf ],
	 [ 0xf00, 0xf00 ],
	 [ 0xf40, 0xf47 ],
	 [ 0xf49, 0xf6c ],
	 [ 0xf88, 0xf8c ],
	 [ 0x1000, 0x102a ],
	 [ 0x103f, 0x103f ],
	 [ 0x1050, 0x1055 ],
	 [ 0x105a, 0x105d ],
	 [ 0x1061, 0x1061 ],
	 [ 0x1065, 0x1066 ],
	 [ 0x106e, 0x1070 ],
	 [ 0x1075, 0x1081 ],
	 [ 0x108e, 0x108e ],
	 [ 0x10a0, 0x10c5 ],
	 [ 0x10c7, 0x10c7 ],
	 [ 0x10cd, 0x10cd ],
	 [ 0x10d0, 0x10fa ],
	 [ 0x10fc, 0x1248 ],
	 [ 0x124a, 0x124d ],
	 [ 0x1250, 0x1256 ],
	 [ 0x1258, 0x1258 ],
	 [ 0x125a, 0x125d ],
	 [ 0x1260, 0x1288 ],
	 [ 0x128a, 0x128d ],
	 [ 0x1290, 0x12b0 ],
	 [ 0x12b2, 0x12b5 ],
	 [ 0x12b8, 0x12be ],
	 [ 0x12c0, 0x12c0 ],
	 [ 0x12c2, 0x12c5 ],
	 [ 0x12c8, 0x12d6 ],
	 [ 0x12d8, 0x1310 ],
	 [ 0x1312, 0x1315 ],
	 [ 0x1318, 0x135a ],
	 [ 0x1380, 0x138f ],
	 [ 0x13a0, 0x13f5 ],
	 [ 0x13f8, 0x13fd ],
	 [ 0x1401, 0x166c ],
	 [ 0x166f, 0x167f ],
	 [ 0x1681, 0x169a ],
	 [ 0x16a0, 0x16ea ],
	 [ 0x16ee, 0x16f8 ],
	 [ 0x1700, 0x1711 ],
	 [ 0x171f, 0x1731 ],
	 [ 0x1740, 0x1751 ],
	 [ 0x1760, 0x176c ],
	 [ 0x176e, 0x1770 ],
	 [ 0x1780, 0x17b3 ],
	 [ 0x17d7, 0x17d7 ],
	 [ 0x17dc, 0x17dc ],
	 [ 0x1820, 0x1878 ],
	 [ 0x1880, 0x1884 ],
	 [ 0x1887, 0x18a8 ],
	 [ 0x18aa, 0x18aa ],
	 [ 0x18b0, 0x18f5 ],
	 [ 0x1900, 0x191e ],
	 [ 0x1950, 0x196d ],
	 [ 0x1970, 0x1974 ],
	 [ 0x1980, 0x19ab ],
	 [ 0x19b0, 0x19c9 ],
	 [ 0x1a00, 0x1a16 ],
	 [ 0x1a20, 0x1a54 ],
	 [ 0x1aa7, 0x1aa7 ],
	 [ 0x1b05, 0x1b33 ],
	 [ 0x1b45, 0x1b4c ],
	 [ 0x1b83, 0x1ba0 ],
	 [ 0x1bae, 0x1baf ],
	 [ 0x1bba, 0x1be5 ],
	 [ 0x1c00, 0x1c23 ],
	 [ 0x1c4d, 0x1c4f ],
	 [ 0x1c5a, 0x1c7d ],
	 [ 0x1c80, 0x1c88 ],
	 [ 0x1c90, 0x1cba ],
	 [ 0x1cbd, 0x1cbf ],
	 [ 0x1ce9, 0x1cec ],
	 [ 0x1cee, 0x1cf3 ],
	 [ 0x1cf5, 0x1cf6 ],
	 [ 0x1cfa, 0x1cfa ],
	 [ 0x1d00, 0x1dbf ],
	 [ 0x1e00, 0x1f15 ],
	 [ 0x1f18, 0x1f1d ],
	 [ 0x1f20, 0x1f45 ],
	 [ 0x1f48, 0x1f4d ],
	 [ 0x1f50, 0x1f57 ],
	 [ 0x1f59, 0x1f59 ],
	 [ 0x1f5b, 0x1f5b ],
	 [ 0x1f5d, 0x1f5d ],
	 [ 0x1f5f, 0x1f7d ],
	 [ 0x1f80, 0x1fb4 ],
	 [ 0x1fb6, 0x1fbc ],
	 [ 0x1fbe, 0x1fbe ],
	 [ 0x1fc2, 0x1fc4 ],
	 [ 0x1fc6, 0x1fcc ],
	 [ 0x1fd0, 0x1fd3 ],
	 [ 0x1fd6, 0x1fdb ],
	 [ 0x1fe0, 0x1fec ],
	 [ 0x1ff2, 0x1ff4 ],
	 [ 0x1ff6, 0x1ffc ],
	 [ 0x2071, 0x2071 ],
	 [ 0x207f, 0x207f ],
	 [ 0x2090, 0x209c ],
	 [ 0x2102, 0x2102 ],
	 [ 0x2107, 0x2107 ],
	 [ 0x210a, 0x2113 ],
	 [ 0x2115, 0x2115 ],
	 [ 0x2118, 0x211d ],
	 [ 0x2124, 0x2124 ],
	 [ 0x2126, 0x2126 ],
	 [ 0x2128, 0x2128 ],
	 [ 0x212a, 0x2139 ],
	 [ 0x213c, 0x213f ],
	 [ 0x2145, 0x2149 ],
	 [ 0x214e, 0x214e ],
	 [ 0x2160, 0x2188 ],
	 [ 0x2c00, 0x2ce4 ],
	 [ 0x2ceb, 0x2cee ],
	 [ 0x2cf2, 0x2cf3 ],
	 [ 0x2d00, 0x2d25 ],
	 [ 0x2d27, 0x2d27 ],
	 [ 0x2d2d, 0x2d2d ],
	 [ 0x2d30, 0x2d67 ],
	 [ 0x2d6f, 0x2d6f ],
	 [ 0x2d80, 0x2d96 ],
	 [ 0x2da0, 0x2da6 ],
	 [ 0x2da8, 0x2dae ],
	 [ 0x2db0, 0x2db6 ],
	 [ 0x2db8, 0x2dbe ],
	 [ 0x2dc0, 0x2dc6 ],
	 [ 0x2dc8, 0x2dce ],
	 [ 0x2dd0, 0x2dd6 ],
	 [ 0x2dd8, 0x2dde ],
	 [ 0x3005, 0x3007 ],
	 [ 0x3021, 0x3029 ],
	 [ 0x3031, 0x3035 ],
	 [ 0x3038, 0x303c ],
	 [ 0x3041, 0x3096 ],
	 [ 0x309b, 0x309f ],
	 [ 0x30a1, 0x30fa ],
	 [ 0x30fc, 0x30ff ],
	 [ 0x3105, 0x312f ],
	 [ 0x3131, 0x318e ],
	 [ 0x31a0, 0x31bf ],
	 [ 0x31f0, 0x31ff ],
	 [ 0x3400, 0x4dbf ],
	 [ 0x4e00, 0xa48c ],
	 [ 0xa4d0, 0xa4fd ],
	 [ 0xa500, 0xa60c ],
	 [ 0xa610, 0xa61f ],
	 [ 0xa62a, 0xa62b ],
	 [ 0xa640, 0xa66e ],
	 [ 0xa67f, 0xa69d ],
	 [ 0xa6a0, 0xa6ef ],
	 [ 0xa717, 0xa71f ],
	 [ 0xa722, 0xa788 ],
	 [ 0xa78b, 0xa7ca ],
	 [ 0xa7d0, 0xa7d1 ],
	 [ 0xa7d3, 0xa7d3 ],
	 [ 0xa7d5, 0xa7d9 ],
	 [ 0xa7f2, 0xa801 ],
	 [ 0xa803, 0xa805 ],
	 [ 0xa807, 0xa80a ],
	 [ 0xa80c, 0xa822 ],
	 [ 0xa840, 0xa873 ],
	 [ 0xa882, 0xa8b3 ],
	 [ 0xa8f2, 0xa8f7 ],
	 [ 0xa8fb, 0xa8fb ],
	 [ 0xa8fd, 0xa8fe ],
	 [ 0xa90a, 0xa925 ],
	 [ 0xa930, 0xa946 ],
	 [ 0xa960, 0xa97c ],
	 [ 0xa984, 0xa9b2 ],
	 [ 0xa9cf, 0xa9cf ],
	 [ 0xa9e0, 0xa9e4 ],
	 [ 0xa9e6, 0xa9ef ],
	 [ 0xa9fa, 0xa9fe ],
	 [ 0xaa00, 0xaa28 ],
	 [ 0xaa40, 0xaa42 ],
	 [ 0xaa44, 0xaa4b ],
	 [ 0xaa60, 0xaa76 ],
	 [ 0xaa7a, 0xaa7a ],
	 [ 0xaa7e, 0xaaaf ],
	 [ 0xaab1, 0xaab1 ],
	 [ 0xaab5, 0xaab6 ],
	 [ 0xaab9, 0xaabd ],
	 [ 0xaac0, 0xaac0 ],
	 [ 0xaac2, 0xaac2 ],
	 [ 0xaadb, 0xaadd ],
	 [ 0xaae0, 0xaaea ],
	 [ 0xaaf2, 0xaaf4 ],
	 [ 0xab01, 0xab06 ],
	 [ 0xab09, 0xab0e ],
	 [ 0xab11, 0xab16 ],
	 [ 0xab20, 0xab26 ],
	 [ 0xab28, 0xab2e ],
	 [ 0xab30, 0xab5a ],
	 [ 0xab5c, 0xab69 ],
	 [ 0xab70, 0xabe2 ],
	 [ 0xac00, 0xd7a3 ],
	 [ 0xd7b0, 0xd7c6 ],
	 [ 0xd7cb, 0xd7fb ],
	 [ 0xf900, 0xfa6d ],
	 [ 0xfa70, 0xfad9 ],
	 [ 0xfb00, 0xfb06 ],
	 [ 0xfb13, 0xfb17 ],
	 [ 0xfb1d, 0xfb1d ],
	 [ 0xfb1f, 0xfb28 ],
	 [ 0xfb2a, 0xfb36 ],
	 [ 0xfb38, 0xfb3c ],
	 [ 0xfb3e, 0xfb3e ],
	 [ 0xfb40, 0xfb41 ],
	 [ 0xfb43, 0xfb44 ],
	 [ 0xfb46, 0xfbb1 ],
	 [ 0xfbd3, 0xfd3d ],
	 [ 0xfd50, 0xfd8f ],
	 [ 0xfd92, 0xfdc7 ],
	 [ 0xfdf0, 0xfdfb ],
	 [ 0xfe70, 0xfe74 ],
	 [ 0xfe76, 0xfefc ],
	 [ 0xff21, 0xff3a ],
	 [ 0xff41, 0xff5a ],
	 [ 0xff66, 0xffbe ],
	 [ 0xffc2, 0xffc7 ],
	 [ 0xffca, 0xffcf ],
	 [ 0xffd2, 0xffd7 ],
	 [ 0xffda, 0xffdc ],
	 [ 0x10000, 0x1000b ],
	 [ 0x1000d, 0x10026 ],
	 [ 0x10028, 0x1003a ],
	 [ 0x1003c, 0x1003d ],
	 [ 0x1003f, 0x1004d ],
	 [ 0x10050, 0x1005d ],
	 [ 0x10080, 0x100fa ],
	 [ 0x10140, 0x10174 ],
	 [ 0x10280, 0x1029c ],
	 [ 0x102a0, 0x102d0 ],
	 [ 0x10300, 0x1031f ],
	 [ 0x1032d, 0x1034a ],
	 [ 0x10350, 0x10375 ],
	 [ 0x10380, 0x1039d ],
	 [ 0x103a0, 0x103c3 ],
	 [ 0x103c8, 0x103cf ],
	 [ 0x103d1, 0x103d5 ],
	 [ 0x10400, 0x1049d ],
	 [ 0x104b0, 0x104d3 ],
	 [ 0x104d8, 0x104fb ],
	 [ 0x10500, 0x10527 ],
	 [ 0x10530, 0x10563 ],
	 [ 0x10570, 0x1057a ],
	 [ 0x1057c, 0x1058a ],
	 [ 0x1058c, 0x10592 ],
	 [ 0x10594, 0x10595 ],
	 [ 0x10597, 0x105a1 ],
	 [ 0x105a3, 0x105b1 ],
	 [ 0x105b3, 0x105b9 ],
	 [ 0x105bb, 0x105bc ],
	 [ 0x10600, 0x10736 ],
	 [ 0x10740, 0x10755 ],
	 [ 0x10760, 0x10767 ],
	 [ 0x10780, 0x10785 ],
	 [ 0x10787, 0x107b0 ],
	 [ 0x107b2, 0x107ba ],
	 [ 0x10800, 0x10805 ],
	 [ 0x10808, 0x10808 ],
	 [ 0x1080a, 0x10835 ],
	 [ 0x10837, 0x10838 ],
	 [ 0x1083c, 0x1083c ],
	 [ 0x1083f, 0x10855 ],
	 [ 0x10860, 0x10876 ],
	 [ 0x10880, 0x1089e ],
	 [ 0x108e0, 0x108f2 ],
	 [ 0x108f4, 0x108f5 ],
	 [ 0x10900, 0x10915 ],
	 [ 0x10920, 0x10939 ],
	 [ 0x10980, 0x109b7 ],
	 [ 0x109be, 0x109bf ],
	 [ 0x10a00, 0x10a00 ],
	 [ 0x10a10, 0x10a13 ],
	 [ 0x10a15, 0x10a17 ],
	 [ 0x10a19, 0x10a35 ],
	 [ 0x10a60, 0x10a7c ],
	 [ 0x10a80, 0x10a9c ],
	 [ 0x10ac0, 0x10ac7 ],
	 [ 0x10ac9, 0x10ae4 ],
	 [ 0x10b00, 0x10b35 ],
	 [ 0x10b40, 0x10b55 ],
	 [ 0x10b60, 0x10b72 ],
	 [ 0x10b80, 0x10b91 ],
	 [ 0x10c00, 0x10c48 ],
	 [ 0x10c80, 0x10cb2 ],
	 [ 0x10cc0, 0x10cf2 ],
	 [ 0x10d00, 0x10d23 ],
	 [ 0x10e80, 0x10ea9 ],
	 [ 0x10eb0, 0x10eb1 ],
	 [ 0x10f00, 0x10f1c ],
	 [ 0x10f27, 0x10f27 ],
	 [ 0x10f30, 0x10f45 ],
	 [ 0x10f70, 0x10f81 ],
	 [ 0x10fb0, 0x10fc4 ],
	 [ 0x10fe0, 0x10ff6 ],
	 [ 0x11003, 0x11037 ],
	 [ 0x11071, 0x11072 ],
	 [ 0x11075, 0x11075 ],
	 [ 0x11083, 0x110af ],
	 [ 0x110d0, 0x110e8 ],
	 [ 0x11103, 0x11126 ],
	 [ 0x11144, 0x11144 ],
	 [ 0x11147, 0x11147 ],
	 [ 0x11150, 0x11172 ],
	 [ 0x11176, 0x11176 ],
	 [ 0x11183, 0x111b2 ],
	 [ 0x111c1, 0x111c4 ],
	 [ 0x111da, 0x111da ],
	 [ 0x111dc, 0x111dc ],
	 [ 0x11200, 0x11211 ],
	 [ 0x11213, 0x1122b ],
	 [ 0x11280, 0x11286 ],
	 [ 0x11288, 0x11288 ],
	 [ 0x1128a, 0x1128d ],
	 [ 0x1128f, 0x1129d ],
	 [ 0x1129f, 0x112a8 ],
	 [ 0x112b0, 0x112de ],
	 [ 0x11305, 0x1130c ],
	 [ 0x1130f, 0x11310 ],
	 [ 0x11313, 0x11328 ],
	 [ 0x1132a, 0x11330 ],
	 [ 0x11332, 0x11333 ],
	 [ 0x11335, 0x11339 ],
	 [ 0x1133d, 0x1133d ],
	 [ 0x11350, 0x11350 ],
	 [ 0x1135d, 0x11361 ],
	 [ 0x11400, 0x11434 ],
	 [ 0x11447, 0x1144a ],
	 [ 0x1145f, 0x11461 ],
	 [ 0x11480, 0x114af ],
	 [ 0x114c4, 0x114c5 ],
	 [ 0x114c7, 0x114c7 ],
	 [ 0x11580, 0x115ae ],
	 [ 0x115d8, 0x115db ],
	 [ 0x11600, 0x1162f ],
	 [ 0x11644, 0x11644 ],
	 [ 0x11680, 0x116aa ],
	 [ 0x116b8, 0x116b8 ],
	 [ 0x11700, 0x1171a ],
	 [ 0x11740, 0x11746 ],
	 [ 0x11800, 0x1182b ],
	 [ 0x118a0, 0x118df ],
	 [ 0x118ff, 0x11906 ],
	 [ 0x11909, 0x11909 ],
	 [ 0x1190c, 0x11913 ],
	 [ 0x11915, 0x11916 ],
	 [ 0x11918, 0x1192f ],
	 [ 0x1193f, 0x1193f ],
	 [ 0x11941, 0x11941 ],
	 [ 0x119a0, 0x119a7 ],
	 [ 0x119aa, 0x119d0 ],
	 [ 0x119e1, 0x119e1 ],
	 [ 0x119e3, 0x119e3 ],
	 [ 0x11a00, 0x11a00 ],
	 [ 0x11a0b, 0x11a32 ],
	 [ 0x11a3a, 0x11a3a ],
	 [ 0x11a50, 0x11a50 ],
	 [ 0x11a5c, 0x11a89 ],
	 [ 0x11a9d, 0x11a9d ],
	 [ 0x11ab0, 0x11af8 ],
	 [ 0x11c00, 0x11c08 ],
	 [ 0x11c0a, 0x11c2e ],
	 [ 0x11c40, 0x11c40 ],
	 [ 0x11c72, 0x11c8f ],
	 [ 0x11d00, 0x11d06 ],
	 [ 0x11d08, 0x11d09 ],
	 [ 0x11d0b, 0x11d30 ],
	 [ 0x11d46, 0x11d46 ],
	 [ 0x11d60, 0x11d65 ],
	 [ 0x11d67, 0x11d68 ],
	 [ 0x11d6a, 0x11d89 ],
	 [ 0x11d98, 0x11d98 ],
	 [ 0x11ee0, 0x11ef2 ],
	 [ 0x11fb0, 0x11fb0 ],
	 [ 0x12000, 0x12399 ],
	 [ 0x12400, 0x1246e ],
	 [ 0x12480, 0x12543 ],
	 [ 0x12f90, 0x12ff0 ],
	 [ 0x13000, 0x1342e ],
	 [ 0x14400, 0x14646 ],
	 [ 0x16800, 0x16a38 ],
	 [ 0x16a40, 0x16a5e ],
	 [ 0x16a70, 0x16abe ],
	 [ 0x16ad0, 0x16aed ],
	 [ 0x16b00, 0x16b2f ],
	 [ 0x16b40, 0x16b43 ],
	 [ 0x16b63, 0x16b77 ],
	 [ 0x16b7d, 0x16b8f ],
	 [ 0x16e40, 0x16e7f ],
	 [ 0x16f00, 0x16f4a ],
	 [ 0x16f50, 0x16f50 ],
	 [ 0x16f93, 0x16f9f ],
	 [ 0x16fe0, 0x16fe1 ],
	 [ 0x16fe3, 0x16fe3 ],
	 [ 0x17000, 0x187f7 ],
	 [ 0x18800, 0x18cd5 ],
	 [ 0x18d00, 0x18d08 ],
	 [ 0x1aff0, 0x1aff3 ],
	 [ 0x1aff5, 0x1affb ],
	 [ 0x1affd, 0x1affe ],
	 [ 0x1b000, 0x1b122 ],
	 [ 0x1b150, 0x1b152 ],
	 [ 0x1b164, 0x1b167 ],
	 [ 0x1b170, 0x1b2fb ],
	 [ 0x1bc00, 0x1bc6a ],
	 [ 0x1bc70, 0x1bc7c ],
	 [ 0x1bc80, 0x1bc88 ],
	 [ 0x1bc90, 0x1bc99 ],
	 [ 0x1d400, 0x1d454 ],
	 [ 0x1d456, 0x1d49c ],
	 [ 0x1d49e, 0x1d49f ],
	 [ 0x1d4a2, 0x1d4a2 ],
	 [ 0x1d4a5, 0x1d4a6 ],
	 [ 0x1d4a9, 0x1d4ac ],
	 [ 0x1d4ae, 0x1d4b9 ],
	 [ 0x1d4bb, 0x1d4bb ],
	 [ 0x1d4bd, 0x1d4c3 ],
	 [ 0x1d4c5, 0x1d505 ],
	 [ 0x1d507, 0x1d50a ],
	 [ 0x1d50d, 0x1d514 ],
	 [ 0x1d516, 0x1d51c ],
	 [ 0x1d51e, 0x1d539 ],
	 [ 0x1d53b, 0x1d53e ],
	 [ 0x1d540, 0x1d544 ],
	 [ 0x1d546, 0x1d546 ],
	 [ 0x1d54a, 0x1d550 ],
	 [ 0x1d552, 0x1d6a5 ],
	 [ 0x1d6a8, 0x1d6c0 ],
	 [ 0x1d6c2, 0x1d6da ],
	 [ 0x1d6dc, 0x1d6fa ],
	 [ 0x1d6fc, 0x1d714 ],
	 [ 0x1d716, 0x1d734 ],
	 [ 0x1d736, 0x1d74e ],
	 [ 0x1d750, 0x1d76e ],
	 [ 0x1d770, 0x1d788 ],
	 [ 0x1d78a, 0x1d7a8 ],
	 [ 0x1d7aa, 0x1d7c2 ],
	 [ 0x1d7c4, 0x1d7cb ],
	 [ 0x1df00, 0x1df1e ],
	 [ 0x1e100, 0x1e12c ],
	 [ 0x1e137, 0x1e13d ],
	 [ 0x1e14e, 0x1e14e ],
	 [ 0x1e290, 0x1e2ad ],
	 [ 0x1e2c0, 0x1e2eb ],
	 [ 0x1e7e0, 0x1e7e6 ],
	 [ 0x1e7e8, 0x1e7eb ],
	 [ 0x1e7ed, 0x1e7ee ],
	 [ 0x1e7f0, 0x1e7fe ],
	 [ 0x1e800, 0x1e8c4 ],
	 [ 0x1e900, 0x1e943 ],
	 [ 0x1e94b, 0x1e94b ],
	 [ 0x1ee00, 0x1ee03 ],
	 [ 0x1ee05, 0x1ee1f ],
	 [ 0x1ee21, 0x1ee22 ],
	 [ 0x1ee24, 0x1ee24 ],
	 [ 0x1ee27, 0x1ee27 ],
	 [ 0x1ee29, 0x1ee32 ],
	 [ 0x1ee34, 0x1ee37 ],
	 [ 0x1ee39, 0x1ee39 ],
	 [ 0x1ee3b, 0x1ee3b ],
	 [ 0x1ee42, 0x1ee42 ],
	 [ 0x1ee47, 0x1ee47 ],
	 [ 0x1ee49, 0x1ee49 ],
	 [ 0x1ee4b, 0x1ee4b ],
	 [ 0x1ee4d, 0x1ee4f ],
	 [ 0x1ee51, 0x1ee52 ],
	 [ 0x1ee54, 0x1ee54 ],
	 [ 0x1ee57, 0x1ee57 ],
	 [ 0x1ee59, 0x1ee59 ],
	 [ 0x1ee5b, 0x1ee5b ],
	 [ 0x1ee5d, 0x1ee5d ],
	 [ 0x1ee5f, 0x1ee5f ],
	 [ 0x1ee61, 0x1ee62 ],
	 [ 0x1ee64, 0x1ee64 ],
	 [ 0x1ee67, 0x1ee6a ],
	 [ 0x1ee6c, 0x1ee72 ],
	 [ 0x1ee74, 0x1ee77 ],
	 [ 0x1ee79, 0x1ee7c ],
	 [ 0x1ee7e, 0x1ee7e ],
	 [ 0x1ee80, 0x1ee89 ],
	 [ 0x1ee8b, 0x1ee9b ],
	 [ 0x1eea1, 0x1eea3 ],
	 [ 0x1eea5, 0x1eea9 ],
	 [ 0x1eeab, 0x1eebb ],
	 [ 0x20000, 0x2a6df ],
	 [ 0x2a700, 0x2b738 ],
	 [ 0x2b740, 0x2b81d ],
	 [ 0x2b820, 0x2cea1 ],
	 [ 0x2ceb0, 0x2ebe0 ],
	 [ 0x2f800, 0x2fa1d ],
	 [ 0x30000, 0x3134a ],
]

const xid_continue = [
	[ 0x30, 0x39 ],
	[ 0x41, 0x5a ],
	[ 0x5f, 0x5f ],
	[ 0x61, 0x7a ],
	[ 0xaa, 0xaa ],
	[ 0xb5, 0xb5 ],
	[ 0xb7, 0xb7 ],
	[ 0xba, 0xba ],
	[ 0xc0, 0xd6 ],
	[ 0xd8, 0xf6 ],
	[ 0xf8, 0x2c1 ],
	[ 0x2c6, 0x2d1 ],
	[ 0x2e0, 0x2e4 ],
	[ 0x2ec, 0x2ec ],
	[ 0x2ee, 0x2ee ],
	[ 0x300, 0x374 ],
	[ 0x376, 0x377 ],
	[ 0x37a, 0x37d ],
	[ 0x37f, 0x37f ],
	[ 0x386, 0x38a ],
	[ 0x38c, 0x38c ],
	[ 0x38e, 0x3a1 ],
	[ 0x3a3, 0x3f5 ],
	[ 0x3f7, 0x481 ],
	[ 0x483, 0x487 ],
	[ 0x48a, 0x52f ],
	[ 0x531, 0x556 ],
	[ 0x559, 0x559 ],
	[ 0x560, 0x588 ],
	[ 0x591, 0x5bd ],
	[ 0x5bf, 0x5bf ],
	[ 0x5c1, 0x5c2 ],
	[ 0x5c4, 0x5c5 ],
	[ 0x5c7, 0x5c7 ],
	[ 0x5d0, 0x5ea ],
	[ 0x5ef, 0x5f2 ],
	[ 0x610, 0x61a ],
	[ 0x620, 0x669 ],
	[ 0x66e, 0x6d3 ],
	[ 0x6d5, 0x6dc ],
	[ 0x6df, 0x6e8 ],
	[ 0x6ea, 0x6fc ],
	[ 0x6ff, 0x6ff ],
	[ 0x710, 0x74a ],
	[ 0x74d, 0x7b1 ],
	[ 0x7c0, 0x7f5 ],
	[ 0x7fa, 0x7fa ],
	[ 0x7fd, 0x7fd ],
	[ 0x800, 0x82d ],
	[ 0x840, 0x85b ],
	[ 0x860, 0x86a ],
	[ 0x870, 0x887 ],
	[ 0x889, 0x88e ],
	[ 0x898, 0x8e1 ],
	[ 0x8e3, 0x963 ],
	[ 0x966, 0x96f ],
	[ 0x971, 0x983 ],
	[ 0x985, 0x98c ],
	[ 0x98f, 0x990 ],
	[ 0x993, 0x9a8 ],
	[ 0x9aa, 0x9b0 ],
	[ 0x9b2, 0x9b2 ],
	[ 0x9b6, 0x9b9 ],
	[ 0x9bc, 0x9c4 ],
	[ 0x9c7, 0x9c8 ],
	[ 0x9cb, 0x9ce ],
	[ 0x9d7, 0x9d7 ],
	[ 0x9dc, 0x9dd ],
	[ 0x9df, 0x9e3 ],
	[ 0x9e6, 0x9f1 ],
	[ 0x9fc, 0x9fc ],
	[ 0x9fe, 0x9fe ],
	[ 0xa01, 0xa03 ],
	[ 0xa05, 0xa0a ],
	[ 0xa0f, 0xa10 ],
	[ 0xa13, 0xa28 ],
	[ 0xa2a, 0xa30 ],
	[ 0xa32, 0xa33 ],
	[ 0xa35, 0xa36 ],
	[ 0xa38, 0xa39 ],
	[ 0xa3c, 0xa3c ],
	[ 0xa3e, 0xa42 ],
	[ 0xa47, 0xa48 ],
	[ 0xa4b, 0xa4d ],
	[ 0xa51, 0xa51 ],
	[ 0xa59, 0xa5c ],
	[ 0xa5e, 0xa5e ],
	[ 0xa66, 0xa75 ],
	[ 0xa81, 0xa83 ],
	[ 0xa85, 0xa8d ],
	[ 0xa8f, 0xa91 ],
	[ 0xa93, 0xaa8 ],
	[ 0xaaa, 0xab0 ],
	[ 0xab2, 0xab3 ],
	[ 0xab5, 0xab9 ],
	[ 0xabc, 0xac5 ],
	[ 0xac7, 0xac9 ],
	[ 0xacb, 0xacd ],
	[ 0xad0, 0xad0 ],
	[ 0xae0, 0xae3 ],
	[ 0xae6, 0xaef ],
	[ 0xaf9, 0xaff ],
	[ 0xb01, 0xb03 ],
	[ 0xb05, 0xb0c ],
	[ 0xb0f, 0xb10 ],
	[ 0xb13, 0xb28 ],
	[ 0xb2a, 0xb30 ],
	[ 0xb32, 0xb33 ],
	[ 0xb35, 0xb39 ],
	[ 0xb3c, 0xb44 ],
	[ 0xb47, 0xb48 ],
	[ 0xb4b, 0xb4d ],
	[ 0xb55, 0xb57 ],
	[ 0xb5c, 0xb5d ],
	[ 0xb5f, 0xb63 ],
	[ 0xb66, 0xb6f ],
	[ 0xb71, 0xb71 ],
	[ 0xb82, 0xb83 ],
	[ 0xb85, 0xb8a ],
	[ 0xb8e, 0xb90 ],
	[ 0xb92, 0xb95 ],
	[ 0xb99, 0xb9a ],
	[ 0xb9c, 0xb9c ],
	[ 0xb9e, 0xb9f ],
	[ 0xba3, 0xba4 ],
	[ 0xba8, 0xbaa ],
	[ 0xbae, 0xbb9 ],
	[ 0xbbe, 0xbc2 ],
	[ 0xbc6, 0xbc8 ],
	[ 0xbca, 0xbcd ],
	[ 0xbd0, 0xbd0 ],
	[ 0xbd7, 0xbd7 ],
	[ 0xbe6, 0xbef ],
	[ 0xc00, 0xc0c ],
	[ 0xc0e, 0xc10 ],
	[ 0xc12, 0xc28 ],
	[ 0xc2a, 0xc39 ],
	[ 0xc3c, 0xc44 ],
	[ 0xc46, 0xc48 ],
	[ 0xc4a, 0xc4d ],
	[ 0xc55, 0xc56 ],
	[ 0xc58, 0xc5a ],
	[ 0xc5d, 0xc5d ],
	[ 0xc60, 0xc63 ],
	[ 0xc66, 0xc6f ],
	[ 0xc80, 0xc83 ],
	[ 0xc85, 0xc8c ],
	[ 0xc8e, 0xc90 ],
	[ 0xc92, 0xca8 ],
	[ 0xcaa, 0xcb3 ],
	[ 0xcb5, 0xcb9 ],
	[ 0xcbc, 0xcc4 ],
	[ 0xcc6, 0xcc8 ],
	[ 0xcca, 0xccd ],
	[ 0xcd5, 0xcd6 ],
	[ 0xcdd, 0xcde ],
	[ 0xce0, 0xce3 ],
	[ 0xce6, 0xcef ],
	[ 0xcf1, 0xcf2 ],
	[ 0xd00, 0xd0c ],
	[ 0xd0e, 0xd10 ],
	[ 0xd12, 0xd44 ],
	[ 0xd46, 0xd48 ],
	[ 0xd4a, 0xd4e ],
	[ 0xd54, 0xd57 ],
	[ 0xd5f, 0xd63 ],
	[ 0xd66, 0xd6f ],
	[ 0xd7a, 0xd7f ],
	[ 0xd81, 0xd83 ],
	[ 0xd85, 0xd96 ],
	[ 0xd9a, 0xdb1 ],
	[ 0xdb3, 0xdbb ],
	[ 0xdbd, 0xdbd ],
	[ 0xdc0, 0xdc6 ],
	[ 0xdca, 0xdca ],
	[ 0xdcf, 0xdd4 ],
	[ 0xdd6, 0xdd6 ],
	[ 0xdd8, 0xddf ],
	[ 0xde6, 0xdef ],
	[ 0xdf2, 0xdf3 ],
	[ 0xe01, 0xe3a ],
	[ 0xe40, 0xe4e ],
	[ 0xe50, 0xe59 ],
	[ 0xe81, 0xe82 ],
	[ 0xe84, 0xe84 ],
	[ 0xe86, 0xe8a ],
	[ 0xe8c, 0xea3 ],
	[ 0xea5, 0xea5 ],
	[ 0xea7, 0xebd ],
	[ 0xec0, 0xec4 ],
	[ 0xec6, 0xec6 ],
	[ 0xec8, 0xecd ],
	[ 0xed0, 0xed9 ],
	[ 0xedc, 0xedf ],
	[ 0xf00, 0xf00 ],
	[ 0xf18, 0xf19 ],
	[ 0xf20, 0xf29 ],
	[ 0xf35, 0xf35 ],
	[ 0xf37, 0xf37 ],
	[ 0xf39, 0xf39 ],
	[ 0xf3e, 0xf47 ],
	[ 0xf49, 0xf6c ],
	[ 0xf71, 0xf84 ],
	[ 0xf86, 0xf97 ],
	[ 0xf99, 0xfbc ],
	[ 0xfc6, 0xfc6 ],
	[ 0x1000, 0x1049 ],
	[ 0x1050, 0x109d ],
	[ 0x10a0, 0x10c5 ],
	[ 0x10c7, 0x10c7 ],
	[ 0x10cd, 0x10cd ],
	[ 0x10d0, 0x10fa ],
	[ 0x10fc, 0x1248 ],
	[ 0x124a, 0x124d ],
	[ 0x1250, 0x1256 ],
	[ 0x1258, 0x1258 ],
	[ 0x125a, 0x125d ],
	[ 0x1260, 0x1288 ],
	[ 0x128a, 0x128d ],
	[ 0x1290, 0x12b0 ],
	[ 0x12b2, 0x12b5 ],
	[ 0x12b8, 0x12be ],
	[ 0x12c0, 0x12c0 ],
	[ 0x12c2, 0x12c5 ],
	[ 0x12c8, 0x12d6 ],
	[ 0x12d8, 0x1310 ],
	[ 0x1312, 0x1315 ],
	[ 0x1318, 0x135a ],
	[ 0x135d, 0x135f ],
	[ 0x1369, 0x1369 ],
	[ 0x1371, 0x1371 ],
	[ 0x1380, 0x138f ],
	[ 0x13a0, 0x13f5 ],
	[ 0x13f8, 0x13fd ],
	[ 0x1401, 0x166c ],
	[ 0x166f, 0x167f ],
	[ 0x1681, 0x169a ],
	[ 0x16a0, 0x16ea ],
	[ 0x16ee, 0x16f8 ],
	[ 0x1700, 0x1715 ],
	[ 0x171f, 0x1734 ],
	[ 0x1740, 0x1753 ],
	[ 0x1760, 0x176c ],
	[ 0x176e, 0x1770 ],
	[ 0x1772, 0x1773 ],
	[ 0x1780, 0x17d3 ],
	[ 0x17d7, 0x17d7 ],
	[ 0x17dc, 0x17dd ],
	[ 0x17e0, 0x17e9 ],
	[ 0x180b, 0x180d ],
	[ 0x180f, 0x1819 ],
	[ 0x1820, 0x1878 ],
	[ 0x1880, 0x18aa ],
	[ 0x18b0, 0x18f5 ],
	[ 0x1900, 0x191e ],
	[ 0x1920, 0x192b ],
	[ 0x1930, 0x193b ],
	[ 0x1946, 0x196d ],
	[ 0x1970, 0x1974 ],
	[ 0x1980, 0x19ab ],
	[ 0x19b0, 0x19c9 ],
	[ 0x19d0, 0x19da ],
	[ 0x1a00, 0x1a1b ],
	[ 0x1a20, 0x1a5e ],
	[ 0x1a60, 0x1a7c ],
	[ 0x1a7f, 0x1a89 ],
	[ 0x1a90, 0x1a99 ],
	[ 0x1aa7, 0x1aa7 ],
	[ 0x1ab0, 0x1abd ],
	[ 0x1abf, 0x1ace ],
	[ 0x1b00, 0x1b4c ],
	[ 0x1b50, 0x1b59 ],
	[ 0x1b6b, 0x1b73 ],
	[ 0x1b80, 0x1bf3 ],
	[ 0x1c00, 0x1c37 ],
	[ 0x1c40, 0x1c49 ],
	[ 0x1c4d, 0x1c7d ],
	[ 0x1c80, 0x1c88 ],
	[ 0x1c90, 0x1cba ],
	[ 0x1cbd, 0x1cbf ],
	[ 0x1cd0, 0x1cd2 ],
	[ 0x1cd4, 0x1cfa ],
	[ 0x1d00, 0x1f15 ],
	[ 0x1f18, 0x1f1d ],
	[ 0x1f20, 0x1f45 ],
	[ 0x1f48, 0x1f4d ],
	[ 0x1f50, 0x1f57 ],
	[ 0x1f59, 0x1f59 ],
	[ 0x1f5b, 0x1f5b ],
	[ 0x1f5d, 0x1f5d ],
	[ 0x1f5f, 0x1f7d ],
	[ 0x1f80, 0x1fb4 ],
	[ 0x1fb6, 0x1fbc ],
	[ 0x1fbe, 0x1fbe ],
	[ 0x1fc2, 0x1fc4 ],
	[ 0x1fc6, 0x1fcc ],
	[ 0x1fd0, 0x1fd3 ],
	[ 0x1fd6, 0x1fdb ],
	[ 0x1fe0, 0x1fec ],
	[ 0x1ff2, 0x1ff4 ],
	[ 0x1ff6, 0x1ffc ],
	[ 0x203f, 0x2040 ],
	[ 0x2054, 0x2054 ],
	[ 0x2071, 0x2071 ],
	[ 0x207f, 0x207f ],
	[ 0x2090, 0x209c ],
	[ 0x20d0, 0x20dc ],
	[ 0x20e1, 0x20e1 ],
	[ 0x20e5, 0x20f0 ],
	[ 0x2102, 0x2102 ],
	[ 0x2107, 0x2107 ],
	[ 0x210a, 0x2113 ],
	[ 0x2115, 0x2115 ],
	[ 0x2118, 0x211d ],
	[ 0x2124, 0x2124 ],
	[ 0x2126, 0x2126 ],
	[ 0x2128, 0x2128 ],
	[ 0x212a, 0x2139 ],
	[ 0x213c, 0x213f ],
	[ 0x2145, 0x2149 ],
	[ 0x214e, 0x214e ],
	[ 0x2160, 0x2188 ],
	[ 0x2c00, 0x2ce4 ],
	[ 0x2ceb, 0x2cf3 ],
	[ 0x2d00, 0x2d25 ],
	[ 0x2d27, 0x2d27 ],
	[ 0x2d2d, 0x2d2d ],
	[ 0x2d30, 0x2d67 ],
	[ 0x2d6f, 0x2d6f ],
	[ 0x2d7f, 0x2d96 ],
	[ 0x2da0, 0x2da6 ],
	[ 0x2da8, 0x2dae ],
	[ 0x2db0, 0x2db6 ],
	[ 0x2db8, 0x2dbe ],
	[ 0x2dc0, 0x2dc6 ],
	[ 0x2dc8, 0x2dce ],
	[ 0x2dd0, 0x2dd6 ],
	[ 0x2dd8, 0x2dde ],
	[ 0x2de0, 0x2dff ],
	[ 0x3005, 0x3007 ],
	[ 0x3021, 0x302f ],
	[ 0x3031, 0x3035 ],
	[ 0x3038, 0x303c ],
	[ 0x3041, 0x3096 ],
	[ 0x3099, 0x309f ],
	[ 0x30a1, 0x30fa ],
	[ 0x30fc, 0x30ff ],
	[ 0x3105, 0x312f ],
	[ 0x3131, 0x318e ],
	[ 0x31a0, 0x31bf ],
	[ 0x31f0, 0x31ff ],
	[ 0x3400, 0x4dbf ],
	[ 0x4e00, 0xa48c ],
	[ 0xa4d0, 0xa4fd ],
	[ 0xa500, 0xa60c ],
	[ 0xa610, 0xa62b ],
	[ 0xa640, 0xa66f ],
	[ 0xa674, 0xa67d ],
	[ 0xa67f, 0xa6f1 ],
	[ 0xa717, 0xa71f ],
	[ 0xa722, 0xa788 ],
	[ 0xa78b, 0xa7ca ],
	[ 0xa7d0, 0xa7d1 ],
	[ 0xa7d3, 0xa7d3 ],
	[ 0xa7d5, 0xa7d9 ],
	[ 0xa7f2, 0xa827 ],
	[ 0xa82c, 0xa82c ],
	[ 0xa840, 0xa873 ],
	[ 0xa880, 0xa8c5 ],
	[ 0xa8d0, 0xa8d9 ],
	[ 0xa8e0, 0xa8f7 ],
	[ 0xa8fb, 0xa8fb ],
	[ 0xa8fd, 0xa92d ],
	[ 0xa930, 0xa953 ],
	[ 0xa960, 0xa97c ],
	[ 0xa980, 0xa9c0 ],
	[ 0xa9cf, 0xa9d9 ],
	[ 0xa9e0, 0xa9fe ],
	[ 0xaa00, 0xaa36 ],
	[ 0xaa40, 0xaa4d ],
	[ 0xaa50, 0xaa59 ],
	[ 0xaa60, 0xaa76 ],
	[ 0xaa7a, 0xaac2 ],
	[ 0xaadb, 0xaadd ],
	[ 0xaae0, 0xaaef ],
	[ 0xaaf2, 0xaaf6 ],
	[ 0xab01, 0xab06 ],
	[ 0xab09, 0xab0e ],
	[ 0xab11, 0xab16 ],
	[ 0xab20, 0xab26 ],
	[ 0xab28, 0xab2e ],
	[ 0xab30, 0xab5a ],
	[ 0xab5c, 0xab69 ],
	[ 0xab70, 0xabea ],
	[ 0xabec, 0xabed ],
	[ 0xabf0, 0xabf9 ],
	[ 0xac00, 0xd7a3 ],
	[ 0xd7b0, 0xd7c6 ],
	[ 0xd7cb, 0xd7fb ],
	[ 0xf900, 0xfa6d ],
	[ 0xfa70, 0xfad9 ],
	[ 0xfb00, 0xfb06 ],
	[ 0xfb13, 0xfb17 ],
	[ 0xfb1d, 0xfb28 ],
	[ 0xfb2a, 0xfb36 ],
	[ 0xfb38, 0xfb3c ],
	[ 0xfb3e, 0xfb3e ],
	[ 0xfb40, 0xfb41 ],
	[ 0xfb43, 0xfb44 ],
	[ 0xfb46, 0xfbb1 ],
	[ 0xfbd3, 0xfd3d ],
	[ 0xfd50, 0xfd8f ],
	[ 0xfd92, 0xfdc7 ],
	[ 0xfdf0, 0xfdfb ],
	[ 0xfe00, 0xfe0f ],
	[ 0xfe20, 0xfe2f ],
	[ 0xfe33, 0xfe34 ],
	[ 0xfe4d, 0xfe4f ],
	[ 0xfe70, 0xfe74 ],
	[ 0xfe76, 0xfefc ],
	[ 0xff10, 0xff19 ],
	[ 0xff21, 0xff3a ],
	[ 0xff3f, 0xff3f ],
	[ 0xff41, 0xff5a ],
	[ 0xff66, 0xffbe ],
	[ 0xffc2, 0xffc7 ],
	[ 0xffca, 0xffcf ],
	[ 0xffd2, 0xffd7 ],
	[ 0xffda, 0xffdc ],
	[ 0x10000, 0x1000b ],
	[ 0x1000d, 0x10026 ],
	[ 0x10028, 0x1003a ],
	[ 0x1003c, 0x1003d ],
	[ 0x1003f, 0x1004d ],
	[ 0x10050, 0x1005d ],
	[ 0x10080, 0x100fa ],
	[ 0x10140, 0x10174 ],
	[ 0x101fd, 0x101fd ],
	[ 0x10280, 0x1029c ],
	[ 0x102a0, 0x102d0 ],
	[ 0x102e0, 0x102e0 ],
	[ 0x10300, 0x1031f ],
	[ 0x1032d, 0x1034a ],
	[ 0x10350, 0x1037a ],
	[ 0x10380, 0x1039d ],
	[ 0x103a0, 0x103c3 ],
	[ 0x103c8, 0x103cf ],
	[ 0x103d1, 0x103d5 ],
	[ 0x10400, 0x1049d ],
	[ 0x104a0, 0x104a9 ],
	[ 0x104b0, 0x104d3 ],
	[ 0x104d8, 0x104fb ],
	[ 0x10500, 0x10527 ],
	[ 0x10530, 0x10563 ],
	[ 0x10570, 0x1057a ],
	[ 0x1057c, 0x1058a ],
	[ 0x1058c, 0x10592 ],
	[ 0x10594, 0x10595 ],
	[ 0x10597, 0x105a1 ],
	[ 0x105a3, 0x105b1 ],
	[ 0x105b3, 0x105b9 ],
	[ 0x105bb, 0x105bc ],
	[ 0x10600, 0x10736 ],
	[ 0x10740, 0x10755 ],
	[ 0x10760, 0x10767 ],
	[ 0x10780, 0x10785 ],
	[ 0x10787, 0x107b0 ],
	[ 0x107b2, 0x107ba ],
	[ 0x10800, 0x10805 ],
	[ 0x10808, 0x10808 ],
	[ 0x1080a, 0x10835 ],
	[ 0x10837, 0x10838 ],
	[ 0x1083c, 0x1083c ],
	[ 0x1083f, 0x10855 ],
	[ 0x10860, 0x10876 ],
	[ 0x10880, 0x1089e ],
	[ 0x108e0, 0x108f2 ],
	[ 0x108f4, 0x108f5 ],
	[ 0x10900, 0x10915 ],
	[ 0x10920, 0x10939 ],
	[ 0x10980, 0x109b7 ],
	[ 0x109be, 0x109bf ],
	[ 0x10a00, 0x10a03 ],
	[ 0x10a05, 0x10a06 ],
	[ 0x10a0c, 0x10a13 ],
	[ 0x10a15, 0x10a17 ],
	[ 0x10a19, 0x10a35 ],
	[ 0x10a38, 0x10a3a ],
	[ 0x10a3f, 0x10a3f ],
	[ 0x10a60, 0x10a7c ],
	[ 0x10a80, 0x10a9c ],
	[ 0x10ac0, 0x10ac7 ],
	[ 0x10ac9, 0x10ae6 ],
	[ 0x10b00, 0x10b35 ],
	[ 0x10b40, 0x10b55 ],
	[ 0x10b60, 0x10b72 ],
	[ 0x10b80, 0x10b91 ],
	[ 0x10c00, 0x10c48 ],
	[ 0x10c80, 0x10cb2 ],
	[ 0x10cc0, 0x10cf2 ],
	[ 0x10d00, 0x10d27 ],
	[ 0x10d30, 0x10d39 ],
	[ 0x10e80, 0x10ea9 ],
	[ 0x10eab, 0x10eac ],
	[ 0x10eb0, 0x10eb1 ],
	[ 0x10f00, 0x10f1c ],
	[ 0x10f27, 0x10f27 ],
	[ 0x10f30, 0x10f50 ],
	[ 0x10f70, 0x10f85 ],
	[ 0x10fb0, 0x10fc4 ],
	[ 0x10fe0, 0x10ff6 ],
	[ 0x11000, 0x11046 ],
	[ 0x11066, 0x11075 ],
	[ 0x1107f, 0x110ba ],
	[ 0x110c2, 0x110c2 ],
	[ 0x110d0, 0x110e8 ],
	[ 0x110f0, 0x110f9 ],
	[ 0x11100, 0x11134 ],
	[ 0x11136, 0x1113f ],
	[ 0x11144, 0x11147 ],
	[ 0x11150, 0x11173 ],
	[ 0x11176, 0x11176 ],
	[ 0x11180, 0x111c4 ],
	[ 0x111c9, 0x111cc ],
	[ 0x111ce, 0x111da ],
	[ 0x111dc, 0x111dc ],
	[ 0x11200, 0x11211 ],
	[ 0x11213, 0x11237 ],
	[ 0x1123e, 0x1123e ],
	[ 0x11280, 0x11286 ],
	[ 0x11288, 0x11288 ],
	[ 0x1128a, 0x1128d ],
	[ 0x1128f, 0x1129d ],
	[ 0x1129f, 0x112a8 ],
	[ 0x112b0, 0x112ea ],
	[ 0x112f0, 0x112f9 ],
	[ 0x11300, 0x11303 ],
	[ 0x11305, 0x1130c ],
	[ 0x1130f, 0x11310 ],
	[ 0x11313, 0x11328 ],
	[ 0x1132a, 0x11330 ],
	[ 0x11332, 0x11333 ],
	[ 0x11335, 0x11339 ],
	[ 0x1133b, 0x11344 ],
	[ 0x11347, 0x11348 ],
	[ 0x1134b, 0x1134d ],
	[ 0x11350, 0x11350 ],
	[ 0x11357, 0x11357 ],
	[ 0x1135d, 0x11363 ],
	[ 0x11366, 0x1136c ],
	[ 0x11370, 0x11374 ],
	[ 0x11400, 0x1144a ],
	[ 0x11450, 0x11459 ],
	[ 0x1145e, 0x11461 ],
	[ 0x11480, 0x114c5 ],
	[ 0x114c7, 0x114c7 ],
	[ 0x114d0, 0x114d9 ],
	[ 0x11580, 0x115b5 ],
	[ 0x115b8, 0x115c0 ],
	[ 0x115d8, 0x115dd ],
	[ 0x11600, 0x11640 ],
	[ 0x11644, 0x11644 ],
	[ 0x11650, 0x11659 ],
	[ 0x11680, 0x116b8 ],
	[ 0x116c0, 0x116c9 ],
	[ 0x11700, 0x1171a ],
	[ 0x1171d, 0x1172b ],
	[ 0x11730, 0x11739 ],
	[ 0x11740, 0x11746 ],
	[ 0x11800, 0x1183a ],
	[ 0x118a0, 0x118e9 ],
	[ 0x118ff, 0x11906 ],
	[ 0x11909, 0x11909 ],
	[ 0x1190c, 0x11913 ],
	[ 0x11915, 0x11916 ],
	[ 0x11918, 0x11935 ],
	[ 0x11937, 0x11938 ],
	[ 0x1193b, 0x11943 ],
	[ 0x11950, 0x11959 ],
	[ 0x119a0, 0x119a7 ],
	[ 0x119aa, 0x119d7 ],
	[ 0x119da, 0x119e1 ],
	[ 0x119e3, 0x119e4 ],
	[ 0x11a00, 0x11a3e ],
	[ 0x11a47, 0x11a47 ],
	[ 0x11a50, 0x11a99 ],
	[ 0x11a9d, 0x11a9d ],
	[ 0x11ab0, 0x11af8 ],
	[ 0x11c00, 0x11c08 ],
	[ 0x11c0a, 0x11c36 ],
	[ 0x11c38, 0x11c40 ],
	[ 0x11c50, 0x11c59 ],
	[ 0x11c72, 0x11c8f ],
	[ 0x11c92, 0x11ca7 ],
	[ 0x11ca9, 0x11cb6 ],
	[ 0x11d00, 0x11d06 ],
	[ 0x11d08, 0x11d09 ],
	[ 0x11d0b, 0x11d36 ],
	[ 0x11d3a, 0x11d3a ],
	[ 0x11d3c, 0x11d3d ],
	[ 0x11d3f, 0x11d47 ],
	[ 0x11d50, 0x11d59 ],
	[ 0x11d60, 0x11d65 ],
	[ 0x11d67, 0x11d68 ],
	[ 0x11d6a, 0x11d8e ],
	[ 0x11d90, 0x11d91 ],
	[ 0x11d93, 0x11d98 ],
	[ 0x11da0, 0x11da9 ],
	[ 0x11ee0, 0x11ef6 ],
	[ 0x11fb0, 0x11fb0 ],
	[ 0x12000, 0x12399 ],
	[ 0x12400, 0x1246e ],
	[ 0x12480, 0x12543 ],
	[ 0x12f90, 0x12ff0 ],
	[ 0x13000, 0x1342e ],
	[ 0x14400, 0x14646 ],
	[ 0x16800, 0x16a38 ],
	[ 0x16a40, 0x16a5e ],
	[ 0x16a60, 0x16a69 ],
	[ 0x16a70, 0x16abe ],
	[ 0x16ac0, 0x16ac9 ],
	[ 0x16ad0, 0x16aed ],
	[ 0x16af0, 0x16af4 ],
	[ 0x16b00, 0x16b36 ],
	[ 0x16b40, 0x16b43 ],
	[ 0x16b50, 0x16b59 ],
	[ 0x16b63, 0x16b77 ],
	[ 0x16b7d, 0x16b8f ],
	[ 0x16e40, 0x16e7f ],
	[ 0x16f00, 0x16f4a ],
	[ 0x16f4f, 0x16f87 ],
	[ 0x16f8f, 0x16f9f ],
	[ 0x16fe0, 0x16fe1 ],
	[ 0x16fe3, 0x16fe4 ],
	[ 0x16ff0, 0x16ff1 ],
	[ 0x17000, 0x187f7 ],
	[ 0x18800, 0x18cd5 ],
	[ 0x18d00, 0x18d08 ],
	[ 0x1aff0, 0x1aff3 ],
	[ 0x1aff5, 0x1affb ],
	[ 0x1affd, 0x1affe ],
	[ 0x1b000, 0x1b122 ],
	[ 0x1b150, 0x1b152 ],
	[ 0x1b164, 0x1b167 ],
	[ 0x1b170, 0x1b2fb ],
	[ 0x1bc00, 0x1bc6a ],
	[ 0x1bc70, 0x1bc7c ],
	[ 0x1bc80, 0x1bc88 ],
	[ 0x1bc90, 0x1bc99 ],
	[ 0x1bc9d, 0x1bc9e ],
	[ 0x1cf00, 0x1cf2d ],
	[ 0x1cf30, 0x1cf46 ],
	[ 0x1d165, 0x1d169 ],
	[ 0x1d16d, 0x1d172 ],
	[ 0x1d17b, 0x1d182 ],
	[ 0x1d185, 0x1d18b ],
	[ 0x1d1aa, 0x1d1ad ],
	[ 0x1d242, 0x1d244 ],
	[ 0x1d400, 0x1d454 ],
	[ 0x1d456, 0x1d49c ],
	[ 0x1d49e, 0x1d49f ],
	[ 0x1d4a2, 0x1d4a2 ],
	[ 0x1d4a5, 0x1d4a6 ],
	[ 0x1d4a9, 0x1d4ac ],
	[ 0x1d4ae, 0x1d4b9 ],
	[ 0x1d4bb, 0x1d4bb ],
	[ 0x1d4bd, 0x1d4c3 ],
	[ 0x1d4c5, 0x1d505 ],
	[ 0x1d507, 0x1d50a ],
	[ 0x1d50d, 0x1d514 ],
	[ 0x1d516, 0x1d51c ],
	[ 0x1d51e, 0x1d539 ],
	[ 0x1d53b, 0x1d53e ],
	[ 0x1d540, 0x1d544 ],
	[ 0x1d546, 0x1d546 ],
	[ 0x1d54a, 0x1d550 ],
	[ 0x1d552, 0x1d6a5 ],
	[ 0x1d6a8, 0x1d6c0 ],
	[ 0x1d6c2, 0x1d6da ],
	[ 0x1d6dc, 0x1d6fa ],
	[ 0x1d6fc, 0x1d714 ],
	[ 0x1d716, 0x1d734 ],
	[ 0x1d736, 0x1d74e ],
	[ 0x1d750, 0x1d76e ],
	[ 0x1d770, 0x1d788 ],
	[ 0x1d78a, 0x1d7a8 ],
	[ 0x1d7aa, 0x1d7c2 ],
	[ 0x1d7c4, 0x1d7cb ],
	[ 0x1d7ce, 0x1d7ff ],
	[ 0x1da00, 0x1da36 ],
	[ 0x1da3b, 0x1da6c ],
	[ 0x1da75, 0x1da75 ],
	[ 0x1da84, 0x1da84 ],
	[ 0x1da9b, 0x1da9f ],
	[ 0x1daa1, 0x1daaf ],
	[ 0x1df00, 0x1df1e ],
	[ 0x1e000, 0x1e006 ],
	[ 0x1e008, 0x1e018 ],
	[ 0x1e01b, 0x1e021 ],
	[ 0x1e023, 0x1e024 ],
	[ 0x1e026, 0x1e02a ],
	[ 0x1e100, 0x1e12c ],
	[ 0x1e130, 0x1e13d ],
	[ 0x1e140, 0x1e149 ],
	[ 0x1e14e, 0x1e14e ],
	[ 0x1e290, 0x1e2ae ],
	[ 0x1e2c0, 0x1e2f9 ],
	[ 0x1e7e0, 0x1e7e6 ],
	[ 0x1e7e8, 0x1e7eb ],
	[ 0x1e7ed, 0x1e7ee ],
	[ 0x1e7f0, 0x1e7fe ],
	[ 0x1e800, 0x1e8c4 ],
	[ 0x1e8d0, 0x1e8d6 ],
	[ 0x1e900, 0x1e94b ],
	[ 0x1e950, 0x1e959 ],
	[ 0x1ee00, 0x1ee03 ],
	[ 0x1ee05, 0x1ee1f ],
	[ 0x1ee21, 0x1ee22 ],
	[ 0x1ee24, 0x1ee24 ],
	[ 0x1ee27, 0x1ee27 ],
	[ 0x1ee29, 0x1ee32 ],
	[ 0x1ee34, 0x1ee37 ],
	[ 0x1ee39, 0x1ee39 ],
	[ 0x1ee3b, 0x1ee3b ],
	[ 0x1ee42, 0x1ee42 ],
	[ 0x1ee47, 0x1ee47 ],
	[ 0x1ee49, 0x1ee49 ],
	[ 0x1ee4b, 0x1ee4b ],
	[ 0x1ee4d, 0x1ee4f ],
	[ 0x1ee51, 0x1ee52 ],
	[ 0x1ee54, 0x1ee54 ],
	[ 0x1ee57, 0x1ee57 ],
	[ 0x1ee59, 0x1ee59 ],
	[ 0x1ee5b, 0x1ee5b ],
	[ 0x1ee5d, 0x1ee5d ],
	[ 0x1ee5f, 0x1ee5f ],
	[ 0x1ee61, 0x1ee62 ],
	[ 0x1ee64, 0x1ee64 ],
	[ 0x1ee67, 0x1ee6a ],
	[ 0x1ee6c, 0x1ee72 ],
	[ 0x1ee74, 0x1ee77 ],
	[ 0x1ee79, 0x1ee7c ],
	[ 0x1ee7e, 0x1ee7e ],
	[ 0x1ee80, 0x1ee89 ],
	[ 0x1ee8b, 0x1ee9b ],
	[ 0x1eea1, 0x1eea3 ],
	[ 0x1eea5, 0x1eea9 ],
	[ 0x1eeab, 0x1eebb ],
	[ 0x1fbf0, 0x1fbf9 ],
	[ 0x20000, 0x2a6df ],
	[ 0x2a700, 0x2b738 ],
	[ 0x2b740, 0x2b81d ],
	[ 0x2b820, 0x2cea1 ],
	[ 0x2ceb0, 0x2ebe0 ],
	[ 0x2f800, 0x2fa1d ],
	[ 0x30000, 0x3134a ],
	[ 0xe0100, 0xe01ef ],
]

const utility_function_table = {
	# under @GlobalScope
	'sin': [1, 'FUNCBINDR(sin, sarray("angle_rad"), Variant::UTILITY_FUNC_TYPE_MATH);', sin],
	'cos': [1, ' FUNCBINDR(cos, sarray("angle_rad"), Variant::UTILITY_FUNC_TYPE_MATH);', cos],
	'tan': [1, ' FUNCBINDR(tan, sarray("angle_rad"), Variant::UTILITY_FUNC_TYPE_MATH);', tan],
	'sinh': [1, ' FUNCBINDR(sinh, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', sinh],
	'cosh': [1, ' FUNCBINDR(cosh, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', cosh],
	'tanh': [1, ' FUNCBINDR(tanh, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', tanh],
	'asin': [1, ' FUNCBINDR(asin, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', asin],
	'acos': [1, ' FUNCBINDR(acos, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', acos],
	'atan': [1, ' FUNCBINDR(atan, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', atan],
	'atan2': [2, ' FUNCBINDR(atan2, sarray("y", "x"), Variant::UTILITY_FUNC_TYPE_MATH);', atan2],
	'asinh': [1, ' FUNCBINDR(asinh, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', asinh],
	'acosh': [1, ' FUNCBINDR(acosh, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', acosh],
	'atanh': [1, ' FUNCBINDR(atanh, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', atanh],
	'sqrt': [1, ' FUNCBINDR(sqrt, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', sqrt],
	'fmod': [2, ' FUNCBINDR(fmod, sarray("x", "y"), Variant::UTILITY_FUNC_TYPE_MATH);', fmod],
	'fposmod': [2, ' FUNCBINDR(fposmod, sarray("x", "y"), Variant::UTILITY_FUNC_TYPE_MATH);', fposmod],
	'posmod': [2, ' FUNCBINDR(posmod, sarray("x", "y"), Variant::UTILITY_FUNC_TYPE_MATH);', posmod],
	'floor': [1, ' FUNCBINDVR(floor, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', floor],
	'floorf': [1, ' FUNCBINDR(floorf, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', floorf],
	'floori': [1, ' FUNCBINDR(floori, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', floori],
	'ceil': [1, ' FUNCBINDVR(ceil, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', ceil],
	'ceilf': [1, ' FUNCBINDR(ceilf, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', ceilf],
	'ceili': [1, ' FUNCBINDR(ceili, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', ceili],
	'round': [1, ' FUNCBINDVR(round, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', round],
	'roundf': [1, ' FUNCBINDR(roundf, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', roundf],
	'roundi': [1, ' FUNCBINDR(roundi, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', roundi],
	'abs': [1, ' FUNCBINDVR(abs, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', abs],
	'absf': [1, ' FUNCBINDR(absf, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', absf],
	'absi': [1, ' FUNCBINDR(absi, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', absi],
	'sign': [1, ' FUNCBINDVR(sign, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', sign],
	'signf': [1, ' FUNCBINDR(signf, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', signf],
	'signi': [1, ' FUNCBINDR(signi, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', signi],
	'snapped': [2, ' FUNCBINDVR2(snapped, sarray("x", "step"), Variant::UTILITY_FUNC_TYPE_MATH);', snapped],
	'snappedf': [2, ' FUNCBINDR(snappedf, sarray("x", "step"), Variant::UTILITY_FUNC_TYPE_MATH);', snappedf],
	'snappedi': [2, ' FUNCBINDR(snappedi, sarray("x", "step"), Variant::UTILITY_FUNC_TYPE_MATH);', snappedi],
	'pow': [2, ' FUNCBINDR(pow, sarray("base", "exp"), Variant::UTILITY_FUNC_TYPE_MATH);', pow],
	'log': [1, ' FUNCBINDR(log, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', log],
	'exp': [1, ' FUNCBINDR(exp, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', exp],
	'is_nan': [1, ' FUNCBINDR(is_nan, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', is_nan],
	'is_inf': [1, ' FUNCBINDR(is_inf, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', is_inf],
	'is_equal_approx': [2, ' FUNCBINDR(is_equal_approx, sarray("a", "b"), Variant::UTILITY_FUNC_TYPE_MATH);', is_equal_approx],
	'is_zero_approx': [1, ' FUNCBINDR(is_zero_approx, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', is_zero_approx],
	'is_finite': [1, ' FUNCBINDR(is_finite, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', is_finite],
	'ease': [2, ' FUNCBINDR(ease, sarray("x", "curve"), Variant::UTILITY_FUNC_TYPE_MATH);', ease],
	'step_decimals': [1, ' FUNCBINDR(step_decimals, sarray("x"), Variant::UTILITY_FUNC_TYPE_MATH);', step_decimals],
	'lerp': [3, ' FUNCBINDVR3(lerp, sarray("from", "to", "weight"), Variant::UTILITY_FUNC_TYPE_MATH);', lerp],
	'lerpf': [3, ' FUNCBINDR(lerpf, sarray("from", "to", "weight"), Variant::UTILITY_FUNC_TYPE_MATH);', lerpf],
	'cubic_interpolate': [5, ' FUNCBINDR(cubic_interpolate, sarray("from", "to", "pre", "post", "weight"), Variant::UTILITY_FUNC_TYPE_MATH);', cubic_interpolate],
	'cubic_interpolate_angle': [5, ' FUNCBINDR(cubic_interpolate_angle, sarray("from", "to", "pre", "post", "weight"), Variant::UTILITY_FUNC_TYPE_MATH);', cubic_interpolate_angle],
	'cubic_interpolate_in_time': [8, ' FUNCBINDR(cubic_interpolate_in_time, sarray("from", "to", "pre", "post", "weight", "to_t", "pre_t", "post_t"), Variant::UTILITY_FUNC_TYPE_MATH);', cubic_interpolate_in_time],
	'cubic_interpolate_angle_in_time': [8, ' FUNCBINDR(cubic_interpolate_angle_in_time, sarray("from", "to", "pre", "post", "weight", "to_t", "pre_t", "post_t"), Variant::UTILITY_FUNC_TYPE_MATH);', cubic_interpolate_angle_in_time],
	'bezier_interpolate': [5, ' FUNCBINDR(bezier_interpolate, sarray("start", "control_1", "control_2", "end", "t"), Variant::UTILITY_FUNC_TYPE_MATH);', bezier_interpolate],
	'bezier_derivative': [5, ' FUNCBINDR(bezier_derivative, sarray("start", "control_1", "control_2", "end", "t"), Variant::UTILITY_FUNC_TYPE_MATH);', bezier_derivative],
	'angle_difference': [2, ' FUNCBINDR(angle_difference, sarray("from", "to"), Variant::UTILITY_FUNC_TYPE_MATH);', angle_difference],
	'lerp_angle': [3, ' FUNCBINDR(lerp_angle, sarray("from", "to", "weight"), Variant::UTILITY_FUNC_TYPE_MATH);', lerp_angle],
	'inverse_lerp': [3, ' FUNCBINDR(inverse_lerp, sarray("from", "to", "weight"), Variant::UTILITY_FUNC_TYPE_MATH);', inverse_lerp],
	'remap': [5, ' FUNCBINDR(remap, sarray("value", "istart", "istop", "ostart", "ostop"), Variant::UTILITY_FUNC_TYPE_MATH);', remap],
	'smoothstep': [3, ' FUNCBINDR(smoothstep, sarray("from", "to", "x"), Variant::UTILITY_FUNC_TYPE_MATH);', smoothstep],
	'move_toward': [3, ' FUNCBINDR(move_toward, sarray("from", "to", "delta"), Variant::UTILITY_FUNC_TYPE_MATH);', move_toward],
	'rotate_toward': [3, ' FUNCBINDR(rotate_toward, sarray("from", "to", "delta"), Variant::UTILITY_FUNC_TYPE_MATH);', rotate_toward],
	'deg_to_rad': [1, ' FUNCBINDR(deg_to_rad, sarray("deg"), Variant::UTILITY_FUNC_TYPE_MATH);', deg_to_rad],
	'rad_to_deg': [1, ' FUNCBINDR(rad_to_deg, sarray("rad"), Variant::UTILITY_FUNC_TYPE_MATH);', rad_to_deg],
	'linear_to_db': [1, ' FUNCBINDR(linear_to_db, sarray("lin"), Variant::UTILITY_FUNC_TYPE_MATH);', linear_to_db],
	'db_to_linear': [1, ' FUNCBINDR(db_to_linear, sarray("db"), Variant::UTILITY_FUNC_TYPE_MATH);', db_to_linear],
	'wrap': [3, ' FUNCBINDVR3(wrap, sarray("value", "min", "max"), Variant::UTILITY_FUNC_TYPE_MATH);', wrap],
	'wrapi': [3, ' FUNCBINDR(wrapi, sarray("value", "min", "max"), Variant::UTILITY_FUNC_TYPE_MATH);',wrapi],
	'wrapf': [3, ' FUNCBINDR(wrapf, sarray("value", "min", "max"), Variant::UTILITY_FUNC_TYPE_MATH);', wrapf],
	'max': [-1, ' FUNCBINDVARARG(max, sarray(), Variant::UTILITY_FUNC_TYPE_MATH);', max],
	'maxi': [2, ' FUNCBINDR(maxi, sarray("a", "b"), Variant::UTILITY_FUNC_TYPE_MATH);', maxi],
	'maxf': [2, ' FUNCBINDR(maxf, sarray("a", "b"), Variant::UTILITY_FUNC_TYPE_MATH);', maxf],
	'min': [-1, ' FUNCBINDVARARG(min, sarray(), Variant::UTILITY_FUNC_TYPE_MATH);', min],
	'mini': [2, ' FUNCBINDR(mini, sarray("a", "b"), Variant::UTILITY_FUNC_TYPE_MATH);', mini],
	'minf': [2, ' FUNCBINDR(minf, sarray("a", "b"), Variant::UTILITY_FUNC_TYPE_MATH);', minf],
	'clamp': [3, ' FUNCBINDVR3(clamp, sarray("value", "min", "max"), Variant::UTILITY_FUNC_TYPE_MATH);', clamp],
	'clampi': [3, ' FUNCBINDR(clampi, sarray("value", "min", "max"), Variant::UTILITY_FUNC_TYPE_MATH);', clampi],
	'clampf': [3, ' FUNCBINDR(clampf, sarray("value", "min", "max"), Variant::UTILITY_FUNC_TYPE_MATH);', clampf],
	'nearest_po2': [1, ' FUNCBINDR(nearest_po2, sarray("value"), Variant::UTILITY_FUNC_TYPE_MATH);', nearest_po2],
	'pingpong': [2, ' FUNCBINDR(pingpong, sarray("value", "length"), Variant::UTILITY_FUNC_TYPE_MATH);', pingpong],
	'randomize': [0, ' FUNCBIND(randomize, sarray(), Variant::UTILITY_FUNC_TYPE_RANDOM);', randomize],
	'randi': [0, ' FUNCBINDR(randi, sarray(), Variant::UTILITY_FUNC_TYPE_RANDOM);', randi],
	'randf': [0, ' FUNCBINDR(randf, sarray(), Variant::UTILITY_FUNC_TYPE_RANDOM);', randf],
	'randi_range': [2, ' FUNCBINDR(randi_range, sarray("from", "to"), Variant::UTILITY_FUNC_TYPE_RANDOM);', randi_range],
	'randf_range': [2, ' FUNCBINDR(randf_range, sarray("from", "to"), Variant::UTILITY_FUNC_TYPE_RANDOM);', randf_range],
	'randfn': [2, ' FUNCBINDR(randfn, sarray("mean", "deviation"), Variant::UTILITY_FUNC_TYPE_RANDOM);', randfn],
	'seed': [1, ' FUNCBIND(seed, sarray("base"), Variant::UTILITY_FUNC_TYPE_RANDOM);', seed],
	'rand_from_seed': [1, ' FUNCBINDR(rand_from_seed, sarray("seed"), Variant::UTILITY_FUNC_TYPE_RANDOM);', rand_from_seed],
	'weakref': [1, ' FUNCBINDVR(weakref, sarray("obj"), Variant::UTILITY_FUNC_TYPE_GENERAL);', weakref],
	'typeof': [1, ' FUNCBINDR(_typeof, sarray("variable"), Variant::UTILITY_FUNC_TYPE_GENERAL);', typeof],
	'type_convert': [2, ' FUNCBINDR(type_convert, sarray("variant", "type"), Variant::UTILITY_FUNC_TYPE_GENERAL);', type_convert],
	'str': [-1, ' FUNCBINDVARARGS(str, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', str],
	'error_string': [1, ' FUNCBINDR(error_string, sarray("error"), Variant::UTILITY_FUNC_TYPE_GENERAL);', error_string],
	'type_string': [1, ' FUNCBINDR(type_string, sarray("type"), Variant::UTILITY_FUNC_TYPE_GENERAL);', type_string],
	'print': [-1, ' FUNCBINDVARARGV(print, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', print],
	'print_rich': [-1, ' FUNCBINDVARARGV(print_rich, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', print_rich],
	'printerr': [-1, ' FUNCBINDVARARGV(printerr, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', printerr],
	'printt': [-1, ' FUNCBINDVARARGV(printt, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', printt],
	'prints': [-1, ' FUNCBINDVARARGV(prints, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', prints],
	'printraw': [-1, ' FUNCBINDVARARGV(printraw, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', printraw],
	'print_verbose': [-1, ' FUNCBINDVARARGV(print_verbose, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', print_verbose],
	'push_error': [-1, ' FUNCBINDVARARGV(push_error, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', push_error],
	'push_warning': [-1, ' FUNCBINDVARARGV(push_warning, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', push_warning],
	'var_to_str': [1, ' FUNCBINDR(var_to_str, sarray("variable"), Variant::UTILITY_FUNC_TYPE_GENERAL);', var_to_str],
	'str_to_var': [1, ' FUNCBINDR(str_to_var, sarray("string"), Variant::UTILITY_FUNC_TYPE_GENERAL);', str_to_var],
	'var_to_bytes': [1, ' FUNCBINDR(var_to_bytes, sarray("variable"), Variant::UTILITY_FUNC_TYPE_GENERAL);', var_to_bytes],
	'bytes_to_var': [1, ' FUNCBINDR(bytes_to_var, sarray("bytes"), Variant::UTILITY_FUNC_TYPE_GENERAL);', bytes_to_var],
	'var_to_bytes_with_objects': [1, ' FUNCBINDR(var_to_bytes_with_objects, sarray("variable"), Variant::UTILITY_FUNC_TYPE_GENERAL);', var_to_bytes_with_objects],
	'bytes_to_var_with_objects': [1, ' FUNCBINDR(bytes_to_var_with_objects, sarray("bytes"), Variant::UTILITY_FUNC_TYPE_GENERAL);', bytes_to_var_with_objects],
	'hash': [1, ' FUNCBINDR(hash, sarray("variable"), Variant::UTILITY_FUNC_TYPE_GENERAL);', hash],
	'instance_from_id': [1, ' FUNCBINDR(instance_from_id, sarray("instance_id"), Variant::UTILITY_FUNC_TYPE_GENERAL);', instance_from_id],
	'is_instance_id_valid': [1, ' FUNCBINDR(is_instance_id_valid, sarray("id"), Variant::UTILITY_FUNC_TYPE_GENERAL);', is_instance_id_valid],
	'is_instance_valid': [1, ' FUNCBINDR(is_instance_valid, sarray("instance"), Variant::UTILITY_FUNC_TYPE_GENERAL);', is_instance_valid],
	'rid_allocate_id': [0, ' FUNCBINDR(rid_allocate_id, Vector<String>(), Variant::UTILITY_FUNC_TYPE_GENERAL);', rid_allocate_id],
	'rid_from_int64': [1, ' FUNCBINDR(rid_from_int64, sarray("base"), Variant::UTILITY_FUNC_TYPE_GENERAL);', rid_from_int64],
	'is_same': [2, ' FUNCBINDR(is_same, sarray("a", "b"), Variant::UTILITY_FUNC_TYPE_GENERAL);', is_same],
	# under @GDScript
	'convert': [2, 'REGISTER_FUNC( convert,        true,  RETVAR,             ARGS( ARGVAR("what"), ARGTYPE("type") ), false, varray(     ));', convert, false],
	'type_exists': [1, 'REGISTER_FUNC( type_exists,    true,  RET(BOOL),          ARGS( ARG("type", STRING_NAME)        ), false, varray(     ));', type_exists, false],
	'char': [1, 'REGISTER_FUNC( _char,          true,  RET(STRING),        ARGS( ARG("code", INT)                ), false, varray(     ));', char, false],
	'ord': [1, 'REGISTER_FUNC( ord,            true,  RET(INT),           ARGS( ARG("char", STRING)             ), false, varray(     ));', ord, false],
	'range': [-1, 'REGISTER_FUNC( range,          false, RET(ARRAY),         NOARGS,                                  true,  varray(     ));', range, true],
	'load': [1, 'REGISTER_FUNC( load,           false, RETCLS("Resource"), ARGS( ARG("path", STRING)             ), false, varray(     ));', load, false],
	'inst_to_dict': [1, 'REGISTER_FUNC( inst_to_dict,   false, RET(DICTIONARY),    ARGS( ARG("instance", OBJECT)         ), false, varray(     ));', inst_to_dict, false],
	'dict_to_inst': [1, 'REGISTER_FUNC( dict_to_inst,   false, RET(OBJECT),        ARGS( ARG("dictionary", DICTIONARY)   ), false, varray(     ));', dict_to_inst, false],
	'Color8': [4, 'REGISTER_FUNC( Color8,         true,  RET(COLOR),         ARGS( ARG("r8", INT), ARG("g8", INT),
																ARG("b8", INT), ARG("a8", INT)  ), false, varray( 255 ));', Color8, false],
	'print_debug': [-1, 'REGISTER_FUNC( print_debug,    false, RET(NIL),           NOARGS,                                  true,  varray(     ));', print_debug, true],
	'print_stack': [-1, 'REGISTER_FUNC( print_stack,    false, RET(NIL),           NOARGS,                                  false, varray(     ));', print_stack, false],
	'get_stack': [0, 'REGISTER_FUNC( get_stack,      false, RET(ARRAY),         NOARGS,                                  false, varray(     ));', get_stack, false],
	'len': [1, 'REGISTER_FUNC( len,            true,  RET(INT),           ARGS( ARGVAR("var")                   ), false, varray(     ));', len, false],
	'is_instance_of': [2, 'REGISTER_FUNC( is_instance_of, true,  RET(BOOL),          ARGS( ARGVAR("value"), ARGVAR("type") ), false, varray(     ));', is_instance_of, false],
	# Not really "functions", but show in documentation.
	'preload': [1, '', load],
	'assert': [-1, '', Callable()]
}

## NOTICE 复制 @GlobalScope 文档内容到一个文件（例如：22.txt）中，然后执行下面的命令：
## file="22.txt"; head -`grep -n 属性说明 22.txt | awk -F ':' '{print $1}'` 22.txt | tail -n +`grep -nE '^枚举$' 22.txt | awk -F ':' '{print $1}'` | grep -E '^enum|^flags|^● ' | sed "s/:/': {/g;" | sed "s/enum /\t}\n\t'/g" | sed "s/flags /\t}\n\t'/g" | sed "s/● /\t\t'/g" | sed "s/ = /': /g" | sed "s/$/,/g" | sed 's/{,/{/g' | tail -n +2 | awk 'BEGIN{print "const GLOBAL_ENUM_AND_FLAG = {"}{print $0}END{print "\t}\n}"}' 
const GLOBAL_ENUM_AND_FLAG = {
	'Side': {
		'SIDE_LEFT': 0,
		'SIDE_TOP': 1,
		'SIDE_RIGHT': 2,
		'SIDE_BOTTOM': 3,
	},
	'Corner': {
		'CORNER_TOP_LEFT': 0,
		'CORNER_TOP_RIGHT': 1,
		'CORNER_BOTTOM_RIGHT': 2,
		'CORNER_BOTTOM_LEFT': 3,
	},
	'Orientation': {
		'VERTICAL': 1,
		'HORIZONTAL': 0,
	},
	'ClockDirection': {
		'CLOCKWISE': 0,
		'COUNTERCLOCKWISE': 1,
	},
	'HorizontalAlignment': {
		'HORIZONTAL_ALIGNMENT_LEFT': 0,
		'HORIZONTAL_ALIGNMENT_CENTER': 1,
		'HORIZONTAL_ALIGNMENT_RIGHT': 2,
		'HORIZONTAL_ALIGNMENT_FILL': 3,
	},
	'VerticalAlignment': {
		'VERTICAL_ALIGNMENT_TOP': 0,
		'VERTICAL_ALIGNMENT_CENTER': 1,
		'VERTICAL_ALIGNMENT_BOTTOM': 2,
		'VERTICAL_ALIGNMENT_FILL': 3,
	},
	'InlineAlignment': {
		'INLINE_ALIGNMENT_TOP_TO': 0,
		'INLINE_ALIGNMENT_CENTER_TO': 1,
		'INLINE_ALIGNMENT_BASELINE_TO': 3,
		'INLINE_ALIGNMENT_BOTTOM_TO': 2,
		'INLINE_ALIGNMENT_TO_TOP': 0,
		'INLINE_ALIGNMENT_TO_CENTER': 4,
		'INLINE_ALIGNMENT_TO_BASELINE': 8,
		'INLINE_ALIGNMENT_TO_BOTTOM': 12,
		'INLINE_ALIGNMENT_TOP': 0,
		'INLINE_ALIGNMENT_CENTER': 5,
		'INLINE_ALIGNMENT_BOTTOM': 14,
		'INLINE_ALIGNMENT_IMAGE_MASK': 3,
		'INLINE_ALIGNMENT_TEXT_MASK': 12,
	},
	'EulerOrder': {
		'EULER_ORDER_XYZ': 0,
		'EULER_ORDER_XZY': 1,
		'EULER_ORDER_YXZ': 2,
		'EULER_ORDER_YZX': 3,
		'EULER_ORDER_ZXY': 4,
		'EULER_ORDER_ZYX': 5,
	},
	'Key': {
		'KEY_NONE': 0,
		'KEY_SPECIAL': 4194304,
		'KEY_ESCAPE': 4194305,
		'KEY_TAB': 4194306,
		'KEY_BACKTAB': 4194307,
		'KEY_BACKSPACE': 4194308,
		'KEY_ENTER': 4194309,
		'KEY_KP_ENTER': 4194310,
		'KEY_INSERT': 4194311,
		'KEY_DELETE': 4194312,
		'KEY_PAUSE': 4194313,
		'KEY_PRINT': 4194314,
		'KEY_SYSREQ': 4194315,
		'KEY_CLEAR': 4194316,
		'KEY_HOME': 4194317,
		'KEY_END': 4194318,
		'KEY_LEFT': 4194319,
		'KEY_UP': 4194320,
		'KEY_RIGHT': 4194321,
		'KEY_DOWN': 4194322,
		'KEY_PAGEUP': 4194323,
		'KEY_PAGEDOWN': 4194324,
		'KEY_SHIFT': 4194325,
		'KEY_CTRL': 4194326,
		'KEY_META': 4194327,
		'KEY_ALT': 4194328,
		'KEY_CAPSLOCK': 4194329,
		'KEY_NUMLOCK': 4194330,
		'KEY_SCROLLLOCK': 4194331,
		'KEY_F1': 4194332,
		'KEY_F2': 4194333,
		'KEY_F3': 4194334,
		'KEY_F4': 4194335,
		'KEY_F5': 4194336,
		'KEY_F6': 4194337,
		'KEY_F7': 4194338,
		'KEY_F8': 4194339,
		'KEY_F9': 4194340,
		'KEY_F10': 4194341,
		'KEY_F11': 4194342,
		'KEY_F12': 4194343,
		'KEY_F13': 4194344,
		'KEY_F14': 4194345,
		'KEY_F15': 4194346,
		'KEY_F16': 4194347,
		'KEY_F17': 4194348,
		'KEY_F18': 4194349,
		'KEY_F19': 4194350,
		'KEY_F20': 4194351,
		'KEY_F21': 4194352,
		'KEY_F22': 4194353,
		'KEY_F23': 4194354,
		'KEY_F24': 4194355,
		'KEY_F25': 4194356,
		'KEY_F26': 4194357,
		'KEY_F27': 4194358,
		'KEY_F28': 4194359,
		'KEY_F29': 4194360,
		'KEY_F30': 4194361,
		'KEY_F31': 4194362,
		'KEY_F32': 4194363,
		'KEY_F33': 4194364,
		'KEY_F34': 4194365,
		'KEY_F35': 4194366,
		'KEY_KP_MULTIPLY': 4194433,
		'KEY_KP_DIVIDE': 4194434,
		'KEY_KP_SUBTRACT': 4194435,
		'KEY_KP_PERIOD': 4194436,
		'KEY_KP_ADD': 4194437,
		'KEY_KP_0': 4194438,
		'KEY_KP_1': 4194439,
		'KEY_KP_2': 4194440,
		'KEY_KP_3': 4194441,
		'KEY_KP_4': 4194442,
		'KEY_KP_5': 4194443,
		'KEY_KP_6': 4194444,
		'KEY_KP_7': 4194445,
		'KEY_KP_8': 4194446,
		'KEY_KP_9': 4194447,
		'KEY_MENU': 4194370,
		'KEY_HYPER': 4194371,
		'KEY_HELP': 4194373,
		'KEY_BACK': 4194376,
		'KEY_FORWARD': 4194377,
		'KEY_STOP': 4194378,
		'KEY_REFRESH': 4194379,
		'KEY_VOLUMEDOWN': 4194380,
		'KEY_VOLUMEMUTE': 4194381,
		'KEY_VOLUMEUP': 4194382,
		'KEY_MEDIAPLAY': 4194388,
		'KEY_MEDIASTOP': 4194389,
		'KEY_MEDIAPREVIOUS': 4194390,
		'KEY_MEDIANEXT': 4194391,
		'KEY_MEDIARECORD': 4194392,
		'KEY_HOMEPAGE': 4194393,
		'KEY_FAVORITES': 4194394,
		'KEY_SEARCH': 4194395,
		'KEY_STANDBY': 4194396,
		'KEY_OPENURL': 4194397,
		'KEY_LAUNCHMAIL': 4194398,
		'KEY_LAUNCHMEDIA': 4194399,
		'KEY_LAUNCH0': 4194400,
		'KEY_LAUNCH1': 4194401,
		'KEY_LAUNCH2': 4194402,
		'KEY_LAUNCH3': 4194403,
		'KEY_LAUNCH4': 4194404,
		'KEY_LAUNCH5': 4194405,
		'KEY_LAUNCH6': 4194406,
		'KEY_LAUNCH7': 4194407,
		'KEY_LAUNCH8': 4194408,
		'KEY_LAUNCH9': 4194409,
		'KEY_LAUNCHA': 4194410,
		'KEY_LAUNCHB': 4194411,
		'KEY_LAUNCHC': 4194412,
		'KEY_LAUNCHD': 4194413,
		'KEY_LAUNCHE': 4194414,
		'KEY_LAUNCHF': 4194415,
		'KEY_GLOBE': 4194416,
		'KEY_KEYBOARD': 4194417,
		'KEY_JIS_EISU': 4194418,
		'KEY_JIS_KANA': 4194419,
		'KEY_UNKNOWN': 8388607,
		'KEY_SPACE': 32,
		'KEY_EXCLAM': 33,
		'KEY_QUOTEDBL': 34,
		'KEY_NUMBERSIGN': 35,
		'KEY_DOLLAR': 36,
		'KEY_PERCENT': 37,
		'KEY_AMPERSAND': 38,
		'KEY_APOSTROPHE': 39,
		'KEY_PARENLEFT': 40,
		'KEY_PARENRIGHT': 41,
		'KEY_ASTERISK': 42,
		'KEY_PLUS': 43,
		'KEY_COMMA': 44,
		'KEY_MINUS': 45,
		'KEY_PERIOD': 46,
		'KEY_SLASH': 47,
		'KEY_0': 48,
		'KEY_1': 49,
		'KEY_2': 50,
		'KEY_3': 51,
		'KEY_4': 52,
		'KEY_5': 53,
		'KEY_6': 54,
		'KEY_7': 55,
		'KEY_8': 56,
		'KEY_9': 57,
		'KEY_COLON': 58,
		'KEY_SEMICOLON': 59,
		'KEY_LESS': 60,
		'KEY_EQUAL': 61,
		'KEY_GREATER': 62,
		'KEY_QUESTION': 63,
		'KEY_AT': 64,
		'KEY_A': 65,
		'KEY_B': 66,
		'KEY_C': 67,
		'KEY_D': 68,
		'KEY_E': 69,
		'KEY_F': 70,
		'KEY_G': 71,
		'KEY_H': 72,
		'KEY_I': 73,
		'KEY_J': 74,
		'KEY_K': 75,
		'KEY_L': 76,
		'KEY_M': 77,
		'KEY_N': 78,
		'KEY_O': 79,
		'KEY_P': 80,
		'KEY_Q': 81,
		'KEY_R': 82,
		'KEY_S': 83,
		'KEY_T': 84,
		'KEY_U': 85,
		'KEY_V': 86,
		'KEY_W': 87,
		'KEY_X': 88,
		'KEY_Y': 89,
		'KEY_Z': 90,
		'KEY_BRACKETLEFT': 91,
		'KEY_BACKSLASH': 92,
		'KEY_BRACKETRIGHT': 93,
		'KEY_ASCIICIRCUM': 94,
		'KEY_UNDERSCORE': 95,
		'KEY_QUOTELEFT': 96,
		'KEY_BRACELEFT': 123,
		'KEY_BAR': 124,
		'KEY_BRACERIGHT': 125,
		'KEY_ASCIITILDE': 126,
		'KEY_YEN': 165,
		'KEY_SECTION': 167,
	},
	'KeyModifierMask': {
		'KEY_CODE_MASK': 8388607,
		'KEY_MODIFIER_MASK': 532676608,
		'KEY_MASK_CMD_OR_CTRL': 16777216,
		'KEY_MASK_SHIFT': 33554432,
		'KEY_MASK_ALT': 67108864,
		'KEY_MASK_META': 134217728,
		'KEY_MASK_CTRL': 268435456,
		'KEY_MASK_KPAD': 536870912,
		'KEY_MASK_GROUP_SWITCH': 1073741824,
	},
	'KeyLocation': {
		'KEY_LOCATION_UNSPECIFIED': 0,
		'KEY_LOCATION_LEFT': 1,
		'KEY_LOCATION_RIGHT': 2,
	},
	'MouseButton': {
		'MOUSE_BUTTON_NONE': 0,
		'MOUSE_BUTTON_LEFT': 1,
		'MOUSE_BUTTON_RIGHT': 2,
		'MOUSE_BUTTON_MIDDLE': 3,
		'MOUSE_BUTTON_WHEEL_UP': 4,
		'MOUSE_BUTTON_WHEEL_DOWN': 5,
		'MOUSE_BUTTON_WHEEL_LEFT': 6,
		'MOUSE_BUTTON_WHEEL_RIGHT': 7,
		'MOUSE_BUTTON_XBUTTON1': 8,
		'MOUSE_BUTTON_XBUTTON2': 9,
	},
	'MouseButtonMask': {
		'MOUSE_BUTTON_MASK_LEFT': 1,
		'MOUSE_BUTTON_MASK_RIGHT': 2,
		'MOUSE_BUTTON_MASK_MIDDLE': 4,
		'MOUSE_BUTTON_MASK_MB_XBUTTON1': 128,
		'MOUSE_BUTTON_MASK_MB_XBUTTON2': 256,
	},
	'JoyButton': {
		'JOY_BUTTON_INVALID': -1,
		'JOY_BUTTON_A': 0,
		'JOY_BUTTON_B': 1,
		'JOY_BUTTON_X': 2,
		'JOY_BUTTON_Y': 3,
		'JOY_BUTTON_BACK': 4,
		'JOY_BUTTON_GUIDE': 5,
		'JOY_BUTTON_START': 6,
		'JOY_BUTTON_LEFT_STICK': 7,
		'JOY_BUTTON_RIGHT_STICK': 8,
		'JOY_BUTTON_LEFT_SHOULDER': 9,
		'JOY_BUTTON_RIGHT_SHOULDER': 10,
		'JOY_BUTTON_DPAD_UP': 11,
		'JOY_BUTTON_DPAD_DOWN': 12,
		'JOY_BUTTON_DPAD_LEFT': 13,
		'JOY_BUTTON_DPAD_RIGHT': 14,
		'JOY_BUTTON_MISC1': 15,
		'JOY_BUTTON_PADDLE1': 16,
		'JOY_BUTTON_PADDLE2': 17,
		'JOY_BUTTON_PADDLE3': 18,
		'JOY_BUTTON_PADDLE4': 19,
		'JOY_BUTTON_TOUCHPAD': 20,
		'JOY_BUTTON_SDL_MAX': 21,
		'JOY_BUTTON_MAX': 128,
	},
	'JoyAxis': {
		'JOY_AXIS_INVALID': -1,
		'JOY_AXIS_LEFT_X': 0,
		'JOY_AXIS_LEFT_Y': 1,
		'JOY_AXIS_RIGHT_X': 2,
		'JOY_AXIS_RIGHT_Y': 3,
		'JOY_AXIS_TRIGGER_LEFT': 4,
		'JOY_AXIS_TRIGGER_RIGHT': 5,
		'JOY_AXIS_SDL_MAX': 6,
		'JOY_AXIS_MAX': 10,
	},
	'MIDIMessage': {
		'MIDI_MESSAGE_NONE': 0,
		'MIDI_MESSAGE_NOTE_OFF': 8,
		'MIDI_MESSAGE_NOTE_ON': 9,
		'MIDI_MESSAGE_AFTERTOUCH': 10,
		'MIDI_MESSAGE_CONTROL_CHANGE': 11,
		'MIDI_MESSAGE_PROGRAM_CHANGE': 12,
		'MIDI_MESSAGE_CHANNEL_PRESSURE': 13,
		'MIDI_MESSAGE_PITCH_BEND': 14,
		'MIDI_MESSAGE_SYSTEM_EXCLUSIVE': 240,
		'MIDI_MESSAGE_QUARTER_FRAME': 241,
		'MIDI_MESSAGE_SONG_POSITION_POINTER': 242,
		'MIDI_MESSAGE_SONG_SELECT': 243,
		'MIDI_MESSAGE_TUNE_REQUEST': 246,
		'MIDI_MESSAGE_TIMING_CLOCK': 248,
		'MIDI_MESSAGE_START': 250,
		'MIDI_MESSAGE_CONTINUE': 251,
		'MIDI_MESSAGE_STOP': 252,
		'MIDI_MESSAGE_ACTIVE_SENSING': 254,
		'MIDI_MESSAGE_SYSTEM_RESET': 255,
	},
	'Error': {
		'OK': 0,
		'FAILED': 1,
		'ERR_UNAVAILABLE': 2,
		'ERR_UNCONFIGURED': 3,
		'ERR_UNAUTHORIZED': 4,
		'ERR_PARAMETER_RANGE_ERROR': 5,
		'ERR_OUT_OF_MEMORY': 6,
		'ERR_FILE_NOT_FOUND': 7,
		'ERR_FILE_BAD_DRIVE': 8,
		'ERR_FILE_BAD_PATH': 9,
		'ERR_FILE_NO_PERMISSION': 10,
		'ERR_FILE_ALREADY_IN_USE': 11,
		'ERR_FILE_CANT_OPEN': 12,
		'ERR_FILE_CANT_WRITE': 13,
		'ERR_FILE_CANT_READ': 14,
		'ERR_FILE_UNRECOGNIZED': 15,
		'ERR_FILE_CORRUPT': 16,
		'ERR_FILE_MISSING_DEPENDENCIES': 17,
		'ERR_FILE_EOF': 18,
		'ERR_CANT_OPEN': 19,
		'ERR_CANT_CREATE': 20,
		'ERR_QUERY_FAILED': 21,
		'ERR_ALREADY_IN_USE': 22,
		'ERR_LOCKED': 23,
		'ERR_TIMEOUT': 24,
		'ERR_CANT_CONNECT': 25,
		'ERR_CANT_RESOLVE': 26,
		'ERR_CONNECTION_ERROR': 27,
		'ERR_CANT_ACQUIRE_RESOURCE': 28,
		'ERR_CANT_FORK': 29,
		'ERR_INVALID_DATA': 30,
		'ERR_INVALID_PARAMETER': 31,
		'ERR_ALREADY_EXISTS': 32,
		'ERR_DOES_NOT_EXIST': 33,
		'ERR_DATABASE_CANT_READ': 34,
		'ERR_DATABASE_CANT_WRITE': 35,
		'ERR_COMPILATION_FAILED': 36,
		'ERR_METHOD_NOT_FOUND': 37,
		'ERR_LINK_FAILED': 38,
		'ERR_SCRIPT_FAILED': 39,
		'ERR_CYCLIC_LINK': 40,
		'ERR_INVALID_DECLARATION': 41,
		'ERR_DUPLICATE_SYMBOL': 42,
		'ERR_PARSE_ERROR': 43,
		'ERR_BUSY': 44,
		'ERR_SKIP': 45,
		'ERR_HELP': 46,
		'ERR_BUG': 47,
		'ERR_PRINTER_ON_FIRE': 48,
	},
	'PropertyHint': {
		'PROPERTY_HINT_NONE': 0,
		'PROPERTY_HINT_RANGE': 1,
		'PROPERTY_HINT_ENUM': 2,
		'PROPERTY_HINT_ENUM_SUGGESTION': 3,
		'PROPERTY_HINT_EXP_EASING': 4,
		'PROPERTY_HINT_LINK': 5,
		'PROPERTY_HINT_FLAGS': 6,
		'PROPERTY_HINT_LAYERS_2D_RENDER': 7,
		'PROPERTY_HINT_LAYERS_2D_PHYSICS': 8,
		'PROPERTY_HINT_LAYERS_2D_NAVIGATION': 9,
		'PROPERTY_HINT_LAYERS_3D_RENDER': 10,
		'PROPERTY_HINT_LAYERS_3D_PHYSICS': 11,
		'PROPERTY_HINT_LAYERS_3D_NAVIGATION': 12,
		'PROPERTY_HINT_LAYERS_AVOIDANCE': 37,
		'PROPERTY_HINT_FILE': 13,
		'PROPERTY_HINT_DIR': 14,
		'PROPERTY_HINT_GLOBAL_FILE': 15,
		'PROPERTY_HINT_GLOBAL_DIR': 16,
		'PROPERTY_HINT_RESOURCE_TYPE': 17,
		'PROPERTY_HINT_MULTILINE_TEXT': 18,
		'PROPERTY_HINT_EXPRESSION': 19,
		'PROPERTY_HINT_PLACEHOLDER_TEXT': 20,
		'PROPERTY_HINT_COLOR_NO_ALPHA': 21,
		'PROPERTY_HINT_OBJECT_ID': 22,
		'PROPERTY_HINT_TYPE_STRING': 23,
		'PROPERTY_HINT_NODE_PATH_TO_EDITED_NODE': 24,
		'PROPERTY_HINT_OBJECT_TOO_BIG': 25,
		'PROPERTY_HINT_NODE_PATH_VALID_TYPES': 26,
		'PROPERTY_HINT_SAVE_FILE': 27,
		'PROPERTY_HINT_GLOBAL_SAVE_FILE': 28,
		'PROPERTY_HINT_INT_IS_OBJECTID': 29,
		'PROPERTY_HINT_INT_IS_POINTER': 30,
		'PROPERTY_HINT_ARRAY_TYPE': 31,
		'PROPERTY_HINT_LOCALE_ID': 32,
		'PROPERTY_HINT_LOCALIZABLE_STRING': 33,
		'PROPERTY_HINT_NODE_TYPE': 34,
		'PROPERTY_HINT_HIDE_QUATERNION_EDIT': 35,
		'PROPERTY_HINT_PASSWORD': 36,
		'PROPERTY_HINT_MAX': 38,
	},
	'PropertyUsageFlags': {
		'PROPERTY_USAGE_NONE': 0,
		'PROPERTY_USAGE_STORAGE': 2,
		'PROPERTY_USAGE_EDITOR': 4,
		'PROPERTY_USAGE_INTERNAL': 8,
		'PROPERTY_USAGE_CHECKABLE': 16,
		'PROPERTY_USAGE_CHECKED': 32,
		'PROPERTY_USAGE_GROUP': 64,
		'PROPERTY_USAGE_CATEGORY': 128,
		'PROPERTY_USAGE_SUBGROUP': 256,
		'PROPERTY_USAGE_CLASS_IS_BITFIELD': 512,
		'PROPERTY_USAGE_NO_INSTANCE_STATE': 1024,
		'PROPERTY_USAGE_RESTART_IF_CHANGED': 2048,
		'PROPERTY_USAGE_SCRIPT_VARIABLE': 4096,
		'PROPERTY_USAGE_STORE_IF_NULL': 8192,
		'PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED': 16384,
		'PROPERTY_USAGE_SCRIPT_DEFAULT_VALUE': 32768,
		'PROPERTY_USAGE_CLASS_IS_ENUM': 65536,
		'PROPERTY_USAGE_NIL_IS_VARIANT': 131072,
		'PROPERTY_USAGE_ARRAY': 262144,
		'PROPERTY_USAGE_ALWAYS_DUPLICATE': 524288,
		'PROPERTY_USAGE_NEVER_DUPLICATE': 1048576,
		'PROPERTY_USAGE_HIGH_END_GFX': 2097152,
		'PROPERTY_USAGE_NODE_PATH_FROM_SCENE_ROOT': 4194304,
		'PROPERTY_USAGE_RESOURCE_NOT_PERSISTENT': 8388608,
		'PROPERTY_USAGE_KEYING_INCREMENTS': 16777216,
		'PROPERTY_USAGE_DEFERRED_SET_RESOURCE': 33554432,
		'PROPERTY_USAGE_EDITOR_INSTANTIATE_OBJECT': 67108864,
		'PROPERTY_USAGE_EDITOR_BASIC_SETTING': 134217728,
		'PROPERTY_USAGE_READ_ONLY': 268435456,
		'PROPERTY_USAGE_SECRET': 536870912,
		'PROPERTY_USAGE_DEFAULT': 6,
		'PROPERTY_USAGE_NO_EDITOR': 2,
	},
	'MethodFlags': {
		'METHOD_FLAG_NORMAL': 1,
		'METHOD_FLAG_EDITOR': 2,
		'METHOD_FLAG_CONST': 4,
		'METHOD_FLAG_VIRTUAL': 8,
		'METHOD_FLAG_VARARG': 16,
		'METHOD_FLAG_STATIC': 32,
		'METHOD_FLAG_OBJECT_CORE': 64,
		'METHOD_FLAGS_DEFAULT': 1,
	},
	'Variant.Type': {
		'TYPE_NIL': 0,
		'TYPE_BOOL': 1,
		'TYPE_INT': 2,
		'TYPE_FLOAT': 3,
		'TYPE_STRING': 4,
		'TYPE_VECTOR2': 5,
		'TYPE_VECTOR2I': 6,
		'TYPE_RECT2': 7,
		'TYPE_RECT2I': 8,
		'TYPE_VECTOR3': 9,
		'TYPE_VECTOR3I': 10,
		'TYPE_TRANSFORM2D': 11,
		'TYPE_VECTOR4': 12,
		'TYPE_VECTOR4I': 13,
		'TYPE_PLANE': 14,
		'TYPE_QUATERNION': 15,
		'TYPE_AABB': 16,
		'TYPE_BASIS': 17,
		'TYPE_TRANSFORM3D': 18,
		'TYPE_PROJECTION': 19,
		'TYPE_COLOR': 20,
		'TYPE_STRING_NAME': 21,
		'TYPE_NODE_PATH': 22,
		'TYPE_RID': 23,
		'TYPE_OBJECT': 24,
		'TYPE_CALLABLE': 25,
		'TYPE_SIGNAL': 26,
		'TYPE_DICTIONARY': 27,
		'TYPE_ARRAY': 28,
		'TYPE_PACKED_BYTE_ARRAY': 29,
		'TYPE_PACKED_INT32_ARRAY': 30,
		'TYPE_PACKED_INT64_ARRAY': 31,
		'TYPE_PACKED_FLOAT32_ARRAY': 32,
		'TYPE_PACKED_FLOAT64_ARRAY': 33,
		'TYPE_PACKED_STRING_ARRAY': 34,
		'TYPE_PACKED_VECTOR2_ARRAY': 35,
		'TYPE_PACKED_VECTOR3_ARRAY': 36,
		'TYPE_PACKED_COLOR_ARRAY': 37,
		'TYPE_PACKED_VECTOR4_ARRAY': 38,
		'TYPE_MAX': 39,
	},
	'Variant.Operator': {
		'OP_EQUAL': 0,
		'OP_NOT_EQUAL': 1,
		'OP_LESS': 2,
		'OP_LESS_EQUAL': 3,
		'OP_GREATER': 4,
		'OP_GREATER_EQUAL': 5,
		'OP_ADD': 6,
		'OP_SUBTRACT': 7,
		'OP_MULTIPLY': 8,
		'OP_DIVIDE': 9,
		'OP_NEGATE': 10,
		'OP_POSITIVE': 11,
		'OP_MODULE': 12,
		'OP_POWER': 13,
		'OP_SHIFT_LEFT': 14,
		'OP_SHIFT_RIGHT': 15,
		'OP_BIT_AND': 16,
		'OP_BIT_OR': 17,
		'OP_BIT_XOR': 18,
		'OP_BIT_NEGATE': 19,
		'OP_AND': 20,
		'OP_OR': 21,
		'OP_XOR': 22,
		'OP_NOT': 23,
		'OP_IN': 24,
		'OP_MAX': 25,
	}
}

const op_names = {
	OP_EQUAL: '==',
	OP_NOT_EQUAL: '!=',
	OP_LESS: '<',
	OP_LESS_EQUAL: '<=',
	OP_GREATER: '>',
	OP_GREATER_EQUAL: '>=',
	OP_ADD: '+',
	OP_SUBTRACT: '-',
	OP_MULTIPLY: '*',
	OP_DIVIDE: '/',
	OP_NEGATE: 'unary-',
	OP_POSITIVE: 'unary+',
	OP_MODULE: '%',
	OP_POWER: '**',
	OP_SHIFT_LEFT: '<<',
	OP_SHIFT_RIGHT: '>>',
	OP_BIT_AND: '&',
	OP_BIT_OR: '|',
	OP_BIT_XOR: '^',
	OP_BIT_NEGATE: '~',
	OP_AND: 'and',
	OP_OR: 'or',
	OP_XOR: 'xor',
	OP_NOT: 'not',
	OP_IN: 'in',
}

static func _static_init() -> void:
	EXPRESSION_CACHE = ExpressionLRULink.new()
	EXPRESSION_CACHE.capacity = 1024

func _init() -> void:
	if Engine.is_editor_hint():
		if TranslationServer.has_domain("GDSQL"):
			set_translation_domain("GDSQL")
			
func get_operator_name(p_op):
	return op_names[p_op]
	
func get_lack_input_names() -> Array:
	return lack_input_names
	
func clear_lack_input_names():
	lack_input_names.clear()
	
func _set_error(p_err):
	if error_set:
		return
		
	error_str = p_err + ' in ' + expression
	error_set = true
	assert(false, error_str)
	
func alloc_node(type: String) -> ExpressionENode:
	var node
	match type:
		"InputNode":
			node = ExpressionInputNode.new()
		"ConstantNode":
			node = ExpressionConstantNode.new()
		"OperatorNode":
			node = ExpressionOperatorNode.new()
		"SelfNode":
			node = ExpressionSelfNode.new()
		"IndexNode":
			node = ExpressionIndexNode.new()
		"NamedIndexNode":
			node = ExpressionNamedIndexNode.new()
		"ConstructorNode":
			node = ExpressionConstructorNode.new()
		"CallNode":
			node = ExpressionCallNode.new()
		"ArrayNode":
			node = ExpressionArrayNode.new()
		"DictionaryNode":
			node = ExpressionDictionaryNode.new()
		"BuiltinFuncNode":
			node = ExpressionBuiltinFuncNode.new()
		"BuiltinFuncCallableNode":
			node = ExpressionBuiltinFuncCallableNode.new()
		"ClassNode":
			node = ExpressionClassNode.new()
		"SelectNode":
			node = ExpressionSelectNode.new()
		"SQLInputNode":
			node = ExpressionSQLInputNode.new()
		_:
			assert(false, "Inner error expression.gd 2281.")
	node.next = nodes
	nodes = node
	return node

func GET_CHAR():
	if str_ofs >= max_str_ofs or str_ofs >= expression.length():
		str_ofs += 1 # 外部有些地方 -=1， 在遇到EOF的时候会导致回退
		return ''
	var ret = expression[str_ofs]
	str_ofs += 1
	return ret

func ERR_FAIL_V(m_retval):
	push_error("Method/function failed. Returning: %s" % m_retval)
	return m_retval

static func is_digit(c: String) -> bool:
	return c >= '0' and c <= '9'
	
static func is_hex_digit(c: String):
	return (is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))

static func is_unicode_identifier_start(c: String) -> bool:
	return BSEARCH_CHAR_RANGE(xid_start, c)
	
static func is_binary_digit(c: String) -> bool:
	return (c == '0' || c == '1')
	
static func is_unicode_identifier_continue(c: String) -> bool:
	return BSEARCH_CHAR_RANGE(xid_continue, c)
	
static func BSEARCH_CHAR_RANGE(m_array, c: String):
	if c == '':
		return false
	var low = 0
	@warning_ignore("integer_division")
	var high = len(m_array) / len(m_array[0]) - 1
	var middle
	while (low <= high):
		@warning_ignore("integer_division")
		middle = (low + high) / 2
		if (c.unicode_at(0) < m_array[middle][0]):
			high = middle - 1
		elif (c.unicode_at(0) > m_array[middle][1]):
			low = middle + 1                 
		else:
			return true                                   
	return false
	
static func has_utility_function(p_name) -> bool:
	return utility_function_table.has(p_name)
	
func is_utility_function_vararg(p_name) -> bool:
	if not utility_function_table.has(p_name):
		return false
	return utility_function_table[p_name][1].begins_with("FUNCBINDVARARG(") or \
	utility_function_table[p_name][1].begins_with("FUNCBINDVARARGS(") or \
	utility_function_table[p_name][1].begins_with("FUNCBINDVARARGV(") or \
	(utility_function_table[p_name].size() == 4 and utility_function_table[p_name][3])
	
func get_utility_function_argument_count(p_name) -> int:
	if not utility_function_table.has(p_name):
		return 0
	return utility_function_table[p_name][0]
	
func _get_token(r_token: ExpressionToken) -> Error:
	while (true) :


		var cchar = GET_CHAR()

		match cchar:
			'':
				r_token.type = TokenType.TK_EOF
				return OK

			'{':
				r_token.type = TokenType.TK_CURLY_BRACKET_OPEN
				return OK

			'}':
				r_token.type = TokenType.TK_CURLY_BRACKET_CLOSE
				return OK

			'[':
				r_token.type = TokenType.TK_BRACKET_OPEN
				return OK

			']':
				r_token.type = TokenType.TK_BRACKET_CLOSE
				return OK

			'(':
				r_token.type = TokenType.TK_PARENTHESIS_OPEN
				return OK

			')':
				r_token.type = TokenType.TK_PARENTHESIS_CLOSE
				return OK

			',':
				r_token.type = TokenType.TK_COMMA
				return OK

			':':
				r_token.type = TokenType.TK_COLON
				return OK

			'$':
				r_token.type = TokenType.TK_INPUT
				var index = 0
				while true:
					if (str_ofs >= expression.length() or !is_digit(expression[str_ofs])) :
						_set_error("Expected number after '$'")
						r_token.type = TokenType.TK_ERROR
						return ERR_PARSE_ERROR
		
					index *= 10
					index += expression[str_ofs].unicode_at(0) - '0'.unicode_at(0)
					str_ofs += 1

					if str_ofs >= expression.length() or not is_digit(expression[str_ofs]):
						break

				r_token.value = index
				return OK

			'=':
				cchar = GET_CHAR()
				if (cchar == '=') :
					r_token.type = TokenType.TK_OP_EQUAL
				else:
					_set_error("Expected '='")
					r_token.type = TokenType.TK_ERROR
					return ERR_PARSE_ERROR
	
				return OK

			'!':
				if (expression[str_ofs] == '=') :
					r_token.type = TokenType.TK_OP_NOT_EQUAL
					str_ofs += 1
				else:
					r_token.type = TokenType.TK_OP_NOT
	
				return OK

			'>':
				if (expression[str_ofs] == '=') :
					r_token.type = TokenType.TK_OP_GREATER_EQUAL
					str_ofs += 1
				elif (expression[str_ofs] == '>') :
					r_token.type = TokenType.TK_OP_SHIFT_RIGHT
					str_ofs += 1
				else:
					r_token.type = TokenType.TK_OP_GREATER
	
				return OK

			'<':
				if (expression[str_ofs] == '=') :
					r_token.type = TokenType.TK_OP_LESS_EQUAL
					str_ofs += 1
				elif (expression[str_ofs] == '<') :
					r_token.type = TokenType.TK_OP_SHIFT_LEFT
					str_ofs += 1
				else:
					r_token.type = TokenType.TK_OP_LESS
	
				return OK

			'+':
				r_token.type = TokenType.TK_OP_ADD
				return OK

			'-':
				r_token.type = TokenType.TK_OP_SUB
				return OK

			'/':
				r_token.type = TokenType.TK_OP_DIV
				return OK

			'*':
				if (expression[str_ofs] == '*') :
					r_token.type = TokenType.TK_OP_POW
					str_ofs += 1
				else:
					r_token.type = TokenType.TK_OP_MUL
	
				return OK

			'%':
				r_token.type = TokenType.TK_OP_MOD
				return OK

			'&':
				if (expression[str_ofs] == '&') :
					r_token.type = TokenType.TK_OP_AND
					str_ofs += 1
				else:
					r_token.type = TokenType.TK_OP_BIT_AND
	
				return OK

			'|':
				if (expression[str_ofs] == '|') :
					r_token.type = TokenType.TK_OP_OR
					str_ofs += 1
				else:
					r_token.type = TokenType.TK_OP_BIT_OR
	
				return OK

			'^':
				r_token.type = TokenType.TK_OP_BIT_XOR

				return OK

			'~':
				r_token.type = TokenType.TK_OP_BIT_INVERT

				return OK

			#'\'':
			'\'', '"':
				var _str = ""
				var prev = 0
				while (true) :
					var ch = GET_CHAR()

					if (ch == '') :
						_set_error("Unterminated String")
						r_token.type = TokenType.TK_ERROR
						return ERR_PARSE_ERROR
					elif (ch == cchar) :
						#  cchar contain a corresponding quote symbol
						break
					#elif (ch == '\\') :
						## escaped characters...
#
						#var next = GET_CHAR()
						#if (next == '') :
							#_set_error("Unterminated String")
							#r_token.type = TokenType.TK_ERROR
							#return ERR_PARSE_ERROR
			#
						#var res = 0
#
						#match next :
							#'b':
								#res = 8
								##break
							#'t':
								#res = 9
								##break
							#'n':
								#res = 10
								##break
							#'f':
								#res = 12
								##break
							#'r':
								#res = 13
								##break
							##'U':
							#'U', 'u':
								##  Hexadecimal sequence.
								#var hex_len = 6 if (next == 'U') else 4
								#for j in hex_len :
									#var c = GET_CHAR()
#
									#if (c == '') :
										#_set_error("Unterminated String")
										#r_token.type = TokenType.TK_ERROR
										#return ERR_PARSE_ERROR
						#
									#if (!is_hex_digit(c)) :
										#_set_error("Malformed hex constant in string")
										#r_token.type = TokenType.TK_ERROR
										#return ERR_PARSE_ERROR
						#
									#var v
									#if (is_digit(c)) :
										#v = c.unicode_at(0) - '0'.unicode_at(0)
									#elif (c >= 'a' && c <= 'f') :
										#v = c.unicode_at(0) - 'a'.unicode_at(0)
										#v += 10
									#elif (c >= 'A' && c <= 'F') :
										#v = c.unicode_at(0) - 'A'.unicode_at(0)
										#v += 10
									#else:
										#push_error("Bug parsing hex constant.")
										#v = 0
						#
#
									#res <<= 4
									#res |= v
					#
#
				 				##break
							#_:
								#res = next
				 				##break
			#
#
						##  Parse UTF-16 pair.
						#if ((res & 0xfffffc00) == 0xd800) :
							#if (prev == 0) :
								#prev = res
								#continue
							#else:
								#_set_error("Invalid UTF-16 sequence in string, unpaired lead surrogate")
								#r_token.type = TokenType.TK_ERROR
								#return ERR_PARSE_ERROR
				#
						#elif ((res & 0xfffffc00) == 0xdc00) :
							#if (prev == 0) :
								#_set_error("Invalid UTF-16 sequence in string, unpaired trail surrogate")
								#r_token.type = TokenType.TK_ERROR
								#return ERR_PARSE_ERROR
						#else:
								#res = (prev << 10) + res - ((0xd800 << 10) + 0xdc00 - 0x10000)
								#prev = 0
				#
			#
						#if (prev != 0) :
							#_set_error("Invalid UTF-16 sequence in string, unpaired lead surrogate")
							#r_token.type = TokenType.TK_ERROR
							#return ERR_PARSE_ERROR
			#
						#_str += res
					else:
						#if (prev != 0) :
							#_set_error("Invalid UTF-16 sequence in string, unpaired lead surrogate")
							#r_token.type = TokenType.TK_ERROR
							#return ERR_PARSE_ERROR
			
						_str += ch
		
	
				if (prev != 0) :
					_set_error("Invalid UTF-16 sequence in string, unpaired lead surrogate")
					r_token.type = TokenType.TK_ERROR
					return ERR_PARSE_ERROR
	

				r_token.type = TokenType.TK_CONSTANT
				r_token.value = _str
				return OK

				#break
			_: # default:
				if (cchar.unicode_at(0) <= 32) :
					continue # break
	

				var next_char = "" if (str_ofs >= expression.length()) else expression[str_ofs]
				if (is_digit(cchar) || (cchar == '.' && is_digit(next_char))) :
					# a number

					var num: String = ""
#define READING_SIGN 0
#define READING_INT 1
#define READING_HEX 2
#define READING_BIN 3
#define READING_DEC 4
#define READING_EXP 5
#define READING_DONE 6
					var reading = READING_INT

					var c = cchar
					var exp_sign = false
					var exp_beg = false
					var bin_beg = false
					var hex_beg = false
					var is_float = false
					var is_first_char = true

					while (true) :
						match (reading) :
							READING_INT:
								if (is_digit(c)) :
									if (is_first_char && c == '0') :
										if (next_char == 'b' or next_char == "B") :
											reading = READING_BIN
										elif (next_char == 'x' or next_char == "X") :
											reading = READING_HEX
							
						
								elif (c == '.') :
									reading = READING_DEC
									is_float = true
								elif (c == 'e' or c == "E") :
									reading = READING_EXP
									is_float = true
								else:
									reading = READING_DONE
					

								#break
							READING_BIN:
								if (bin_beg && !is_binary_digit(c)) :
									reading = READING_DONE
								elif (c == 'b' or c == "B") :
									bin_beg = true
					

								#break
							READING_HEX:
								if (hex_beg && !is_hex_digit(c)) :
									reading = READING_DONE
								elif (c == 'x' or c == "X") :
									hex_beg = true
					

								#break
							READING_DEC:
								if (is_digit(c)) : pass
								elif (c == 'e' or c == "E") :
									reading = READING_EXP
								else:
									reading = READING_DONE
					

								#break
							READING_EXP:
								if (is_digit(c)) :
									exp_beg = true

								elif ((c == '-' || c == '+') && !exp_sign && !exp_beg) :
									exp_sign = true

								else:
									reading = READING_DONE
					
								#break
			

						if (reading == READING_DONE) :
							break
							
						num += c
						c = GET_CHAR()
						is_first_char = false
						
					if (c != ""):
						str_ofs -= 1
						
					r_token.type = TokenType.TK_CONSTANT

					if (is_float) :
						r_token.value = num.to_float()
					elif (bin_beg) :
						r_token.value = num.bin_to_int()
					elif (hex_beg) :
						r_token.value = num.hex_to_int()
					else:
						r_token.value = num.to_int()
		
					return OK

				elif (is_unicode_identifier_start(cchar)) :
					var id = cchar
					cchar = GET_CHAR()

					while (is_unicode_identifier_continue(cchar)) :
						id += cchar
						cchar = GET_CHAR()
						
					str_ofs -= 1 # go back one
					
					# 1. 如果id是global enum名称，不用特殊处理，就是一个identifier；
					# 2. 如果id是global enum名称的一部分，需要检查一下后续是否跟着剩下的部分，
					# 如果组合起来是一个global enum的完整名称，那么就标记该token可能是一个
					# global enum。
					# NOTICE 不论（1）还是（2），都有可能是base的一个属性、enum、函数等，
					# 但是目前还未确定base，要执行的时候才能确认。所以只能标记为可能是。
					if GLOBAL_ENUM_AND_FLAG.has(id):
						r_token.may_be_global_enum = true
					var id_ = id + "."
					var cofs_bak = str_ofs
					var cofs_after_period = 0
					var find_enum = false
					var next_token1 = ExpressionToken.new()
					for enum_name: String in GLOBAL_ENUM_AND_FLAG:
						if enum_name.begins_with(id_):
							# 已经确认后面是一个period token的情况下，可以跳过get period token
							if cofs_after_period > 0:
								_get_token(next_token1)
								if next_token1.type == TokenType.TK_IDENTIFIER and \
								enum_name == id_ + next_token1.value:
									# also keep str_ofs' current value
									id = id_ + next_token1.value
									find_enum = true
									break
								else:
									str_ofs = cofs_after_period
									# continue check next enum name
							# 该分支只会在第一次执行
							else:
								_get_token(next_token1)
								if next_token1.type == TokenType.TK_PERIOD:
									cofs_after_period = str_ofs
									_get_token(next_token1)
									if next_token1.type == TokenType.TK_IDENTIFIER and \
									enum_name == id_ + next_token1.value:
										# also keep str_ofs' current value
										id = id_ + next_token1.value
										find_enum = true
										break
									else:
										str_ofs = cofs_after_period
										# continue next enum name
								# 不是.号，那么不符合要求，直接退出循环
								else:
									break
					if find_enum:
						r_token.may_be_global_enum = true
					else:
						str_ofs = cofs_bak
		


					if (id == "in") :
						r_token.type = TokenType.TK_OP_IN
					elif (id == "null") :
						r_token.type = TokenType.TK_CONSTANT
						r_token.value = null
					elif (id == "true") :
						r_token.type = TokenType.TK_CONSTANT
						r_token.value = true
					elif (id == "false") :
						r_token.type = TokenType.TK_CONSTANT
						r_token.value = false
					elif (id == "PI") :
						r_token.type = TokenType.TK_CONSTANT
						r_token.value = PI
					elif (id == "TAU") :
						r_token.type = TokenType.TK_CONSTANT
						r_token.value = TAU
					elif (id == "INF") :
						r_token.type = TokenType.TK_CONSTANT
						r_token.value = INF
					elif (id == "NAN") :
						r_token.type = TokenType.TK_CONSTANT
						r_token.value = NAN
					elif (id == "not") :
						r_token.type = TokenType.TK_OP_NOT
					elif (id == "or") :
						r_token.type = TokenType.TK_OP_OR
					elif (id == "and") :
						r_token.type = TokenType.TK_OP_AND
					elif (id == "self") :
						r_token.type = TokenType.TK_SELF
					else:
						# DATA_TYPE_COMMON_NAMES
						var a_type = GDSQL.DataTypeDef.DATA_TYPE_COMMON_NAMES.get(id, -1)
						if (a_type >= 0 and a_type != TYPE_OBJECT) : # Object moves to CLASS_TYPE
							r_token.type = TokenType.TK_BASIC_TYPE
							r_token.value = a_type
							return OK
				
			

						if (has_utility_function(id)) :
							# fix not support parse('abs')
							var next_token = ExpressionToken.new()
							var cofs = str_ofs
							_get_token(next_token)
							str_ofs = cofs
							# 如果要进行内置函数调用，才把它当作内置函数，否则当成identifier
							if next_token.type == TokenType.TK_PARENTHESIS_OPEN:
								r_token.type = TokenType.TK_BUILTIN_FUNC
								r_token.value = id
								return OK

						r_token.type = TokenType.TK_IDENTIFIER
						r_token.value = id
		

					return OK

				elif (cchar == '.') :
					#  Handled down there as we support '.[0-9]' as numbers above
					r_token.type = TokenType.TK_PERIOD
					return OK

				else:
					_set_error("Unexpected character.")
					r_token.type = TokenType.TK_ERROR
					return ERR_PARSE_ERROR
	

		
#undef GET_CHAR
	

	r_token.type = TokenType.TK_ERROR
	return ERR_PARSE_ERROR



func _parse_expression() -> ExpressionENode:
	var expression_nodes = []

	while (true) :
		# keep appending stuff to expression
		var expr: ExpressionENode

		var tk = ExpressionToken.new()
		_get_token(tk)
		if (error_set) :
			return null
		

		match (tk.type) :
			TokenType.TK_CURLY_BRACKET_OPEN:
				# a dictionary
				var dn = alloc_node("DictionaryNode")

				while (true) :
					var cofs = str_ofs
					_get_token(tk)
					if (tk.type == TokenType.TK_CURLY_BRACKET_CLOSE) :
						break
		
					str_ofs = cofs # revert
					# parse an expression
					var subexpr = _parse_expression()
					if (!subexpr) :
						return null
		
					dn.dict.push_back(subexpr)

					_get_token(tk)
					if (tk.type != TokenType.TK_COLON) :
						_set_error("Expected ':'")
						return null
		

					subexpr = _parse_expression()
					if (!subexpr) :
						return null
		

					dn.dict.push_back(subexpr)

					cofs = str_ofs
					_get_token(tk)
					if (tk.type == TokenType.TK_COMMA) :
						pass # all good
					elif (tk.type == TokenType.TK_CURLY_BRACKET_CLOSE) :
						str_ofs = cofs
					else:
						_set_error("Expected ',' or '}'")
						return null
		
	

				expr = dn
 				#break
			TokenType.TK_BRACKET_OPEN:
				# an array

				var an = alloc_node('ArrayNode')

				while (true) :
					var cofs = str_ofs
					_get_token(tk)
					if (tk.type == TokenType.TK_BRACKET_CLOSE) :
						break
		
					str_ofs = cofs # revert
					# parse an expression
					var subexpr = _parse_expression()
					if (!subexpr) :
						return null
		
					an.array.push_back(subexpr)

					cofs = str_ofs
					_get_token(tk)
					if (tk.type == TokenType.TK_COMMA) :
						pass # all good
					elif (tk.type == TokenType.TK_BRACKET_CLOSE) :
						str_ofs = cofs
					else:
						_set_error("Expected ',' or ']'")
						return null
		
	

				expr = an
				#break
			TokenType.TK_PARENTHESIS_OPEN:
				# a suexpression
				var e = _parse_expression()
				if (error_set) :
					return null
	
				_get_token(tk)
				if (tk.type != TokenType.TK_PARENTHESIS_CLOSE) :
					_set_error("Expected ')'")
					return null
	

				expr = e

				#break
			TokenType.TK_IDENTIFIER:
				var err = [null]
				var identifier = _identifier_to_input_if_match(tk.value, err) # fix未判定identifier是input名称的问题
				if err[0]:
					_set_error(err[0])
					return null

				var cofs = str_ofs
				_get_token(tk)
				if (tk.type == TokenType.TK_PARENTHESIS_OPEN) :
					if identifier is ExpressionSelectNode:
						_set_error("Un expected '('")
						return null
						
					# 表名/字段名 后面跟一个左括号，说不通，所以还原为字符串
					if identifier is ExpressionSQLInputNode:
						identifier = tk.value
						
					# function call
					var func_call = alloc_node('CallNode') as ExpressionCallNode
					func_call.method = identifier
					var self_node = alloc_node('SelfNode')
					func_call.base = self_node

					var arguments_ref = func_call.arguments
					# group_concat 特殊处理. eg: group_concat(distinct id, "+", id order by id separator ':')
					# NOTICE 不支持identifier是 ExpressionInputNode 来实现parse阶段
					# 不明确调用group_concat而运行时才明确要调用group_concat
					if sql_mode and identifier is String and identifier.to_lower() == "group_concat":
						# group_concat具有多列（不仅仅是多行）拼接的功能，所以要用Array包装一下
						var cons = alloc_node('ConstructorNode') as ExpressionConstructorNode
						cons.data_type = TYPE_ARRAY
						arguments_ref = cons.arguments
						func_call.arguments.push_back(cons)
						
						var separator = alloc_node('ConstantNode') as ExpressionConstantNode
						separator.value = ','
						func_call.arguments.push_back(separator)
						
						var order_by = alloc_node('ConstantNode') as ExpressionConstantNode
						order_by.value = ''
						func_call.arguments.push_back(order_by)
						
					var index = -1
					while (true) :
						index += 1
						var cofs2 = str_ofs
						_get_token(tk)
						if (tk.type == TokenType.TK_PARENTHESIS_CLOSE) :
							break
							
						# count(*) 特殊处理，相当于count('*')
						var subexpr
						if sql_mode and identifier is String and identifier.to_lower() == "count" and tk.type == TokenType.TK_OP_MUL:
							var cofs3 = str_ofs
							_get_token(tk)
							if tk.type == TokenType.TK_PARENTHESIS_CLOSE:
								var constant = alloc_node('ConstantNode') as ExpressionConstantNode
								constant.value = '*'
								subexpr = constant
								str_ofs = cofs3
							else:
								_set_error("Expected ')'")
								return null
						elif sql_mode and identifier is String and identifier.to_lower() == "group_concat":
							if index == 0 and tk.type == TokenType.TK_IDENTIFIER and tk.value.to_lower() == "distinct":
								func_call.method = "distinct_group_concat"
								# keep str_ofs also: str_ofs = str_ofs
							else:
								str_ofs = cofs2
						else:
							str_ofs = cofs2 # revert
							
						# parse an expression
						if !subexpr:
							subexpr = _parse_expression()
						if (!subexpr) :
							return null
			

						arguments_ref.push_back(subexpr)

						cofs2 = str_ofs
						_get_token(tk)
						if (tk.type == TokenType.TK_COMMA) :
							pass # all good
						elif (tk.type == TokenType.TK_PARENTHESIS_CLOSE) :
							str_ofs = cofs2
						elif sql_mode and identifier is String and identifier.to_lower() == "group_concat" and tk.type == TokenType.TK_IDENTIFIER:
							match tk.value.to_lower():
								"order":
									if func_call.has_meta('order'):
										_set_error("Duplicate 'order' in group_concat")
										return null
										
									func_call.set_meta('order', true)
									_get_token(tk)
									if not (tk.type == TokenType.TK_IDENTIFIER and tk.value.to_lower() == "by"):
										_set_error("Expectd 'by' after order")
										return null
										
									var order_str_begin = str_ofs
									var order_str_end = str_ofs
									var quote_types = {
										# _get_token会处理引号，所以这里不写引号
										TokenType.TK_CURLY_BRACKET_OPEN: TokenType.TK_CURLY_BRACKET_CLOSE,
										TokenType.TK_BRACKET_OPEN: TokenType.TK_BRACKET_CLOSE,
										TokenType.TK_PARENTHESIS_OPEN: TokenType.TK_PARENTHESIS_CLOSE,
									}
									var quote_types_values = quote_types.values()
									var stack = []
									var in_quote = false
									while (true) :
										var cofs3 = str_ofs
										_get_token(tk)
										if tk.type == TokenType.TK_EOF:
											break
											
										if not in_quote and tk.type == TokenType.TK_PARENTHESIS_CLOSE:
											str_ofs = cofs3
											break
											
										if tk.type in quote_types or tk.type in quote_types_values:
											if not in_quote and tk.type in quote_types: # 如果不在引号内，遇到引号则开始记录
												stack.push_back(tk.type)
												in_quote = true
											elif in_quote:  # 已在引号内，遇到相同类型的引号结束记录
												if quote_types[stack.back()] == tk.type:
													stack.pop_back()  # 移除栈顶的引号类型
													in_quote = not stack.is_empty()
												else:
													# 遇到不同类型的引号，视为普通字符
													if tk.type in quote_types:
														stack.push_back(tk.type)
													elif tk.type in quote_types_values:
														var which = ''
														match tk.type:
															TokenType.TK_CURLY_BRACKET_CLOSE: which = '}'
															TokenType.TK_BRACKET_CLOSE: which = ']'
															TokenType.TK_PARENTHESIS_CLOSE: which = ')'
														_set_error("Unmatched '%s' in group_concat" % which)
														return null
													else:
														order_str_end = str_ofs
											else:
												var which = ''
												match tk.type:
													TokenType.TK_CURLY_BRACKET_CLOSE: which = '}'
													TokenType.TK_BRACKET_CLOSE: which = ']'
													TokenType.TK_PARENTHESIS_CLOSE: which = ')'
												_set_error("Unmatched '%s' in group_concat" % which)
												return null
										else:  # 非引号字符
											if in_quote:
												order_str_end = str_ofs
											elif tk.type == TokenType.TK_IDENTIFIER and \
											tk.value.to_lower() == "separator":
												if func_call.has_meta('separator'):
													_set_error("Duplicate 'separator' in group_concat")
													return null
													
												func_call.set_meta('separator', true)
												_get_token(tk)
												if not tk.type == TokenType.TK_CONSTANT:
													_set_error("Expected constant after 'separator' in group_concat")
													return null
													
												# set order by's text
												(func_call.arguments[1] as ExpressionConstantNode).value = tk.value
												var cofs4 = str_ofs
												_get_token(tk)
												if tk.type == TokenType.TK_PARENTHESIS_CLOSE:
													str_ofs = cofs4
												else:
													_set_error("Expected ')' in group_concat")
													return null
											else:
												order_str_end = str_ofs
												
									# 如果栈不为空，说明有开始引号没有匹配的结束引号
									if not stack.is_empty():
										var expected = ''
										match stack.back():
											TokenType.TK_CURLY_BRACKET_OPEN: expected = '}'
											TokenType.TK_BRACKET_OPEN: expected = ']'
											TokenType.TK_PARENTHESIS_OPEN: expected = ')'
										_set_error("Expected '%s'" % expected)
										return null
										
									# set order by which might be an expression
									#var cofs5 = str_ofs
									#str_ofs = order_str_begin
									#max_str_ofs = order_str_end
									#var by = _parse_expression() # 会更改str_ofs
									#if str_ofs != order_str_end:
										#assert(str_ofs < order_str_end, "Inner error expression.gd 3151")
										#var builtin = alloc_node('BuiltinFuncNode') as ExpressionBuiltinFuncNode
										#var constan = alloc_node('ConstantNode') as ExpressionConstantNode
										#constan.value = expression.substr(str_ofs, order_str_end - str_ofs)
										#builtin._func = 'str'
										#builtin.arguments = [by, constan]
										#by = builtin
									#str_ofs = cofs5
									#max_str_ofs = MAX_INT
									#func_call.arguments[2] = by
									var by = expression.substr(order_str_begin, order_str_end - order_str_begin).strip_edges()
									func_call.arguments[2].value = by
								"separator":
									if func_call.has_meta('separator'):
										_set_error("Duplicate 'separator' in group_concat")
										return null
										
									func_call.set_meta('separator', true)
									_get_token(tk)
									if not tk.type == TokenType.TK_CONSTANT:
										_set_error("Expected constant after 'separator' in group_concat")
										return null
										
									# set order by's text
									(func_call.arguments[1] as ExpressionConstantNode).value = tk.value
									var cofs4 = str_ofs
									_get_token(tk)
									if tk.type == TokenType.TK_PARENTHESIS_CLOSE:
										str_ofs = cofs4
									else:
										_set_error("Expected ')' in group_concat")
										return null
								_:
									_set_error("Unexpectd '%s' in group_concat" % tk.value)
									return null
						else:
							_set_error("Expected ',' or ')'")
							return null
			
		

					expr = func_call
				else:
					# named indexing
					str_ofs = cofs


					if (identifier is ExpressionInputNode) :
						expr = identifier
					elif identifier is ExpressionSelectNode:
						expr = identifier
					elif identifier is ExpressionSQLInputNode:
						expr = identifier
					elif (has_utility_function(identifier)):
						var callable = alloc_node('BuiltinFuncCallableNode')
						callable._func = identifier
						expr = callable
					elif _is_class(identifier):
						var clazz = alloc_node('ClassNode')
						clazz._class = identifier
						expr = clazz
					else:
						var index = alloc_node('NamedIndexNode')
						var self_node = alloc_node('SelfNode')
						if tk.may_be_global_enum:
							self_node.possible_global_enum = true # means self may be GDScript's @GlobalSCope Enum
						index.base = self_node
						index.name = identifier
						expr = index
		
	
				#break
			TokenType.TK_INPUT:
				var input = alloc_node('InputNode')
				input.index = tk.value
				expr = input
				#break
			TokenType.TK_SELF:
				var _self = alloc_node('SelfNode')
				expr = _self
				#break
			TokenType.TK_CONSTANT:
				var constant = alloc_node('ConstantNode')
				constant.value = tk.value
				expr = constant
				#break
			TokenType.TK_BASIC_TYPE:
				# constructor..

				var bt = int(tk.value)
				_get_token(tk)
				if (tk.type != TokenType.TK_PARENTHESIS_OPEN) :
					_set_error("Expected '('")
					return null
	

				var constructor = alloc_node('ConstructorNode')
				constructor.data_type = bt

				while (true) :
					var cofs = str_ofs
					_get_token(tk)
					if (tk.type == TokenType.TK_PARENTHESIS_CLOSE) :
						break
		
					str_ofs = cofs # revert
					# parse an expression
					var subexpr = _parse_expression()
					if (!subexpr) :
						return null
		

					constructor.arguments.push_back(subexpr)

					cofs = str_ofs
					_get_token(tk)
					if (tk.type == TokenType.TK_COMMA) :
						pass # all good
					elif (tk.type == TokenType.TK_PARENTHESIS_CLOSE) :
						str_ofs = cofs
					else:
						_set_error("Expected ',' or ')'")
						return null
		
	

				expr = constructor

				#break
			TokenType.TK_BUILTIN_FUNC:
				# builtin function

				var _func = tk.value

				_get_token(tk)
				if (tk.type != TokenType.TK_PARENTHESIS_OPEN) :
					_set_error("Expected '('")
					return null
	

				var bifunc = alloc_node('BuiltinFuncNode')
				bifunc._func = _func

				while (true) :
					var cofs = str_ofs
					_get_token(tk)
					if (tk.type == TokenType.TK_PARENTHESIS_CLOSE) :
						break
		
					str_ofs = cofs # revert
					# parse an expression
					var subexpr = _parse_expression()
					if (!subexpr) :
						return null
		

					bifunc.arguments.push_back(subexpr)

					cofs = str_ofs
					_get_token(tk)
					if (tk.type == TokenType.TK_COMMA) :
						pass # all good
					elif (tk.type == TokenType.TK_PARENTHESIS_CLOSE) :
						str_ofs = cofs
					else:
						_set_error("Expected ',' or ')'")
						return null
		
	

				if (!is_utility_function_vararg(bifunc._func)) :
					var expected_args = get_utility_function_argument_count(bifunc._func)
					if (expected_args != -1 and expected_args != bifunc.arguments.size()) :
						_set_error("Builtin func '" + str(bifunc._func) + "' expects " + str(expected_args) + " argument(s).")
						return null
		
	

				expr = bifunc

				#break
			TokenType.TK_OP_ADD: # NOTICE not in C++
				var e = ExpressionExpressionNode.new()
				e.is_op = true
				e.op = OP_POSITIVE
				expression_nodes.push_back(e)
				continue
				#break
			TokenType.TK_OP_SUB:
				var e = ExpressionExpressionNode.new()
				e.is_op = true
				e.op = OP_NEGATE
				expression_nodes.push_back(e)
				continue
				#break
			TokenType.TK_OP_NOT:
				var e = ExpressionExpressionNode.new()
				e.is_op = true
				e.op = OP_NOT
				expression_nodes.push_back(e)
				continue
				#break
			TokenType.TK_OP_BIT_INVERT: # NOTICE not in C++
				var e = ExpressionExpressionNode.new()
				e.is_op = true
				e.op = OP_BIT_NEGATE
				expression_nodes.push_back(e)
				continue
				#break

			_: # default:
				_set_error("Expected expression.")
				return null
				#break
		

		# before going to operators, must check indexing!

		while (true) :
			var cofs2 = str_ofs
			_get_token(tk)
			if (error_set) :
				return null


			var done = false

			match (tk.type) :
				TokenType.TK_BRACKET_OPEN:
					# value indexing

					var index = alloc_node('IndexNode')
					index.base = expr

					var what = _parse_expression()
					if (!what) :
						return null
		

					index.index = what

					_get_token(tk)
					if (tk.type != TokenType.TK_BRACKET_CLOSE) :
						_set_error("Expected ']' at end of index.")
						return null
		
					expr = index

					#break
				TokenType.TK_PERIOD:
					# named indexing or function call
					_get_token(tk)
					var tk_type = tk.type
					if (tk.type != TokenType.TK_IDENTIFIER && tk.type != TokenType.TK_BUILTIN_FUNC) :
						_set_error("Expected identifier after '.'")
						return null
		

					var identifier = tk.value

					var cofs = str_ofs
					_get_token(tk)
					if (tk.type == TokenType.TK_PARENTHESIS_OPEN) :
						var err = [null]
						# function call
						var func_call = alloc_node('CallNode')
						func_call.method = _identifier_to_input_if_match(identifier, err) # fix未判定identifier是input名称的问题
						if err[0]:
							_set_error(err[0])
							return null
						func_call.base = expr

						while (true) :
							var cofs3 = str_ofs
							_get_token(tk)
							if (tk.type == TokenType.TK_PARENTHESIS_CLOSE) :
								break
				
							str_ofs = cofs3 # revert
							# parse an expression
							var subexpr = _parse_expression()
							if (!subexpr) :
								return null
				

							func_call.arguments.push_back(subexpr)

							cofs3 = str_ofs
							_get_token(tk)
							if (tk.type == TokenType.TK_COMMA) :
								pass # all good
							elif (tk.type == TokenType.TK_PARENTHESIS_CLOSE) :
								str_ofs = cofs3
							else:
								_set_error("Expected ',' or ')'")
								return null
				
			

						expr = func_call
					else:
						# named indexing
						str_ofs = cofs

						var index = alloc_node('NamedIndexNode')
						index.base = expr
						index.name = identifier # 这里不支持identifier是一个input
						if sql_mode:
							if expr is ExpressionInputNode:
								index.base_name = input_names[expr.index]
							elif expr is ExpressionSQLInputNode:
								index.base_name = expr.name
								expr.subname = identifier
							elif expr is ExpressionNamedIndexNode:
								index.base_name = expr.name
								# 可能缺表的情况
								if tk_type == TokenType.TK_IDENTIFIER and \
								expr.base is ExpressionSelfNode and \
								expr.base.possible_global_enum == false:
									if not lack_input_names.has(expr.name):
										lack_input_names.push_back(expr.name)
						expr = index
		

					#break
				_: # default:
					str_ofs = cofs2
					done = true
	 				#break


			if (done) :
				break

		# 如果代表一个补充表中的字段，那么就可以把具体值计算出来
		if expr is ExpressionSQLInputNode:
			var err = [null]
			expr.parse(sql_input_names, sql_static_inputs, err)
			if err[0]:
				_set_error(err[0])
				return null

		# push expression
		if true:#{
			var e = ExpressionExpressionNode.new()
			e.is_op = false
			e.node = expr
			expression_nodes.push_back(e)
		#}

		# ok finally look for an operator

		var _cofs = str_ofs
		_get_token(tk)
		if (error_set) :
			return null
		

		var op = OP_MAX

		match (tk.type) :
			TokenType.TK_OP_IN:
				op = OP_IN
				#break
			TokenType.TK_OP_EQUAL:
				op = OP_EQUAL
				#break
			TokenType.TK_OP_NOT_EQUAL:
				op = OP_NOT_EQUAL
				#break
			TokenType.TK_OP_LESS:
				op = OP_LESS
				#break
			TokenType.TK_OP_LESS_EQUAL:
				op = OP_LESS_EQUAL
				#break
			TokenType.TK_OP_GREATER:
				op = OP_GREATER
				#break
			TokenType.TK_OP_GREATER_EQUAL:
				op = OP_GREATER_EQUAL
				#break
			TokenType.TK_OP_AND:
				op = OP_AND
				#break
			TokenType.TK_OP_OR:
				op = OP_OR
				#break
			TokenType.TK_OP_NOT:
				op = OP_NOT
				#break
			TokenType.TK_OP_ADD:
				op = OP_ADD
				#break
			TokenType.TK_OP_SUB:
				op = OP_SUBTRACT
				#break
			TokenType.TK_OP_MUL:
				op = OP_MULTIPLY
				#break
			TokenType.TK_OP_DIV:
				op = OP_DIVIDE
				#break
			TokenType.TK_OP_MOD:
				op = OP_MODULE
				#break
			TokenType.TK_OP_POW:
				op = OP_POWER
				#break
			TokenType.TK_OP_SHIFT_LEFT:
				op = OP_SHIFT_LEFT
				#break
			TokenType.TK_OP_SHIFT_RIGHT:
				op = OP_SHIFT_RIGHT
				#break
			TokenType.TK_OP_BIT_AND:
				op = OP_BIT_AND
				#break
			TokenType.TK_OP_BIT_OR:
				op = OP_BIT_OR
				#break
			TokenType.TK_OP_BIT_XOR:
				op = OP_BIT_XOR
				#break
			TokenType.TK_OP_BIT_INVERT:
				op = OP_BIT_NEGATE
				#break
			_: # default:
				pass
		

		if (op == OP_MAX) : # stop appending stuff
			str_ofs = _cofs
			break
		

		# push operator and go on
		if true:#{
			var e = ExpressionExpressionNode.new()
			e.is_op = true
			e.op = op
			expression_nodes.push_back(e)
		#}
	

	##  Reduce the set of expressions and place them in an operator tree, respecting precedence */

	while (expression_nodes.size() > 1) :
		var next_op = -1
		var min_priority = 0xFFFFF
		var is_unary = false

		for i in expression_nodes.size():
			if (!expression_nodes[i].is_op) :
				continue


			var priority

			var unary = false

			match (expression_nodes[i].op) :
				OP_POWER:
					priority = 0
					#break
				OP_BIT_NEGATE:
					priority = 1
					unary = true
					#break
				OP_POSITIVE, OP_NEGATE: # NOTICE OP_POSITIVE not in C++
					priority = 2
					unary = true
					#break
				#OP_MULTIPLY:
				#OP_DIVIDE:
				OP_MULTIPLY, OP_DIVIDE, OP_MODULE:
					priority = 3
					#break
				#OP_ADD:
				OP_ADD, OP_SUBTRACT:
					priority = 4
					#break
				#OP_SHIFT_LEFT:
				OP_SHIFT_LEFT, OP_SHIFT_RIGHT:
					priority = 5
					#break
				OP_BIT_AND:
					priority = 6
					#break
				OP_BIT_XOR:
					priority = 7
					#break
				OP_BIT_OR:
					priority = 8
					#break
				#OP_LESS:
				#OP_LESS_EQUAL:
				#OP_GREATER:
				#OP_GREATER_EQUAL:
				#OP_EQUAL:
				OP_LESS, OP_LESS_EQUAL, OP_GREATER, OP_GREATER_EQUAL, OP_EQUAL, OP_NOT_EQUAL:
					priority = 9
					#break
				OP_IN:
					priority = 11
					#break
				OP_NOT:
					priority = 12
					unary = true
					#break
				OP_AND:
					priority = 13
					#break
				OP_OR:
					priority = 14
					#break
				_: # default:
					_set_error("Parser bug, invalid operator in expression: " + str(expression_nodes[i].op))
					return null
	


			if (priority < min_priority) :
				#  < is used for left to right (default)
				#  <= is used for right to left

				next_op = i
				min_priority = priority
				is_unary = unary

		

		if (next_op == -1) :
			_set_error("Yet another parser bug....")
			return ERR_FAIL_V(null)
		

		#  OK! create operator..
		if (is_unary) :
			var expr_pos = next_op
			while (expression_nodes[expr_pos].is_op) :
				expr_pos += 1
				if (expr_pos == expression_nodes.size()) :
					# can happen..
					_set_error("Unexpected end of expression...")
					return null
	


			# consecutively do unary operators
			for i in range(expr_pos -1, next_op - 1, -1):
				var op = alloc_node('OperatorNode')
				op.op = expression_nodes[i].op
				op.nodes[0] = expression_nodes[i + 1].node
				op.nodes[1] = null
				expression_nodes[i].is_op = false
				expression_nodes[i].node = op
				expression_nodes.remove_at(i + 1)


		else:
			if (next_op < 1 || next_op >= (expression_nodes.size() - 1)) :
				_set_error("Parser bug...")
				return ERR_FAIL_V(null)


			var op = alloc_node('OperatorNode')
			op.op = expression_nodes[next_op].op

			if (expression_nodes[next_op - 1].is_op) :
				_set_error("Parser bug...")
				return ERR_FAIL_V(null)


			if (expression_nodes[next_op + 1].is_op) :
				#  this is not invalid and can really appear
				#  but it becomes invalid anyway because no binary op
				#  can be followed by a unary op in a valid combination,
				#  due to how precedence works, unaries will always disappear first

				_set_error("Unexpected two consecutive operators.")
				return null


			op.nodes[0] = expression_nodes[next_op - 1].node # expression goes as left
			op.nodes[1] = expression_nodes[next_op + 1].node # next expression goes as right

			# replace all 3 nodes by this operator and make it an expression
			expression_nodes[next_op - 1].node = op
			expression_nodes.remove_at(next_op)
			expression_nodes.remove_at(next_op)
		
	

	return expression_nodes[0].node

func search_input_name_equal(node, input_name: String, sub_name: String, tree: Dictionary):
	if node == null or node is not ExpressionOperatorNode:
		return
	var input_index = input_names.find(input_name)
	var sub_index = input_names.find(sub_name)
	
	# 解析另一个操作数（在一个操作中，有两个操作数，外部已经确认其中一个是需要的字段，然后把另一个操作数传入来解析）
	var parse_node = func(p_node):
		if p_node is ExpressionNamedIndexNode:
			if p_node.base is ExpressionInputNode:
				# {
				#    "base": "", # table alias
				#    "name": "", # column name
				#    "index": "", # (base或name).在input_names的位置，暂时没用
				# }
				return {
					'base': input_names[p_node.base.index],
					'name': p_node.name,
					'index': -1 # '%s:%s' % [input_names[p_node.base.index], p_node.base.index]
				}
			elif p_node.base is ExpressionSQLInputNode:
				# 做为一个NamedIndexNode的base，怎么可能是一个常数呢
				if p_node.base.value_set:
					assert(false, "Inner error 3855 in expression.gd")
					return null
				if p_node.base.info.has(false) and not sql_static_inputs.is_empty():
					return sql_static_inputs[p_node.base.info[false]][p_node.name]
				return {
					'base': p_node.base.name,
					'name': p_node.name,
					'index': -1 # '%s:-1' % p_node.base.name,
				}
			elif p_node.base is ExpressionNamedIndexNode:
				return {
					'base': p_node.base.base_name,
					'name': p_node.name,
					'index': -1 # '%s:-1' % p_node.base.base_name,
				}
			else:
				assert(false, "Inner error 3830 in expression.gd") # 没考虑到的情况
				return null
		if p_node is ExpressionInputNode:
			return null # 无法确认该inputnode代表哪个表，返回null代表复杂情况
		if p_node is ExpressionSQLInputNode:
			if p_node.base.value_set:
				return p_node.base.value # 返回一个常数（说明该节点代表一个补充表的字段）
			# 非 补充表的字段 的情况（if 和 else都是）
			if p_node.subname != "":
				return {
					'base': p_node.name,
					'name': p_node.subname,
					'index': -1 # '%s:-1' % p_node.subname, # 随便吧，这个字段暂时没什么用
				}
			else:
				# p_node.info的结构：
				# {
				#     true: ['a', 'b'],	# true表示x是一个普通表名，value是一个数组表示x中的字段（可能是多个表合并起来的）
				#     false: index,		# false表示x是一个补充表名（来自__input_names）
				#     'y': 0,			# 字符串表示x是一个普通表y中的一个字段
				#     N: 0,				# 整数表示x是一个补充表中的一个字段，N表示该表在__input_names中的位置
				# }
				for k in p_node.info:
					if k is String:
						return {
							'base': k,
							'name': p_node.name,
							'index': -1 # '%s:-1' % p_node.name,
						}
				return null # 复杂情况
				
		if all_constant_node(p_node):
			var ret = [null]
			var err = []
			_execute([], {}, null, p_node, ret, false, err)
			if err.is_empty():
				return ret[0]
		return p_node
		
	if node.op == OP_AND or node.op == OP_OR:
		tree[op_names[node.op]] = {"left": {}, "right": {}}
		search_input_name_equal(node.nodes[0], input_name, sub_name, tree[op_names[node.op]].left)
		search_input_name_equal(node.nodes[1], input_name, sub_name, tree[op_names[node.op]].right)
	elif node.op == OP_NOT:
		tree[op_names[node.op]] = {"left": {}}
		search_input_name_equal(node.nodes[0], input_name, sub_name, tree[op_names[node.op]].left)
	else:
		var dealed = false
		if not dealed and node.nodes[0] is ExpressionInputNode:
			if node.nodes[0].index == input_index or node.nodes[0].index == sub_index:
				tree[op_names[node.op]] = parse_node.call(node.nodes[1])
				dealed = true
		if not dealed and node.nodes[1] is ExpressionInputNode:
			if node.nodes[1].index == input_index or node.nodes[1].index == sub_index:
				tree['r' + op_names[node.op]] = parse_node.call(node.nodes[0])
				dealed = true
		if not dealed and node.nodes[0] is ExpressionSQLInputNode and not node.nodes[0].value_set:
			if node.nodes[0].name == input_name and node.nodes[0].subname == sub_name:
				tree[op_names[node.op]] = parse_node.call(node.nodes[1])
				dealed = true
			if not dealed and node.nodes[0].name == sub_name and (node.nodes[0].subname == "" or 
			node.nodes[0].subname == sub_name ):
				# 这里不考虑input_name了，因为node.nodes[0]所代表的字段，虽然有可能是
				# 其他表的字段（在联表且多个表有相同名称的字段的情况下），但同样可能就是
				# 我们要的表的字段，这里即便多返回了一些数据，最终还是会对每条数据进行一次
				# 判断。重要的是现在要尽可能限制初始数据的条数。
				tree[op_names[node.op]] = parse_node.call(node.nodes[1])
				dealed = true
			if not dealed and node.nodes[0].info.has(input_name) and node.nodes[0].name == sub_name:
				if node.nodes[0].subname == "":
					tree[op_names[node.op]] = parse_node.call(node.nodes[1])
					dealed = true
				else:
					tree[op_names[node.op]] = null # null表示复杂情况，比如对字段的值做了属性调用
					dealed = true
		if not dealed and node.nodes[1] is ExpressionSQLInputNode and not node.nodes[1].value_set:
			if node.nodes[1].name == input_name and node.nodes[1].subname == sub_name:
				tree[op_names[node.op]] = parse_node.call(node.nodes[0])
				dealed = true
			if not dealed and node.nodes[1].name == sub_name and (node.nodes[1].subname == "" or 
			node.nodes[1].subname == sub_name):
				tree[op_names[node.op]] = parse_node.call(node.nodes[0])
				dealed = true
			if not dealed and node.nodes[1].info.has(input_name) and node.nodes[1].name == sub_name:
				if node.nodes[1].subname == "":
					tree[op_names[node.op]] = parse_node.call(node.nodes[0])
					dealed = true
				else:
					tree[op_names[node.op]] = null # null表示复杂情况，比如对字段的值做了属性调用
					dealed = true
		if not dealed and node.nodes[0] is ExpressionNamedIndexNode:
			if node.nodes[0].base is ExpressionInputNode and \
			node.nodes[0].base.index == input_index and node.nodes[0].name == sub_name:
				tree[op_names[node.op]] = parse_node.call(node.nodes[1])
				dealed = true
			if not dealed and node.nodes[0].base is ExpressionSQLInputNode and \
			node.nodes[0].base.name == input_name and node.nodes[0].base.subname == sub_name:
				tree[op_names[node.op]] = parse_node.call(node.nodes[1])
				dealed = true
			if not dealed and node.nodes[1] is ExpressionNamedIndexNode:
				if node.nodes[1].base is ExpressionInputNode and \
				node.nodes[1].base.index == input_index and node.nodes[1].name == sub_name:
					# 'r'表示操作数是反着的，比如：t.id > 1，符号是'>'，而1 > t.id，符号是'r>'
					tree['r' + op_names[node.op]] = parse_node.call(node.nodes[0])
					dealed = true
				if not dealed and node.nodes[1].base is ExpressionSQLInputNode and \
				node.nodes[1].base.name == input_name and node.nodes[1].base.subname == sub_name:
					tree['r' + op_names[node.op]] = parse_node.call(node.nodes[0])
					dealed = true
		if not dealed and node.nodes[1] is ExpressionNamedIndexNode:
			if node.nodes[1].base is ExpressionInputNode and \
			node.nodes[1].base.index == input_index and node.nodes[1].name == sub_name:
				tree['r' + op_names[node.op]] = parse_node.call(node.nodes[0])
				dealed = true
			if not dealed and node.nodes[1].base is ExpressionSQLInputNode and \
			node.nodes[1].base.name == input_name and node.nodes[1].base.subname == sub_name:
				tree['r' + op_names[node.op]] = parse_node.call(node.nodes[0])
				dealed = true
			if not dealed and node.nodes[0] is ExpressionNamedIndexNode:
				if node.nodes[0].base is ExpressionInputNode and \
				node.nodes[0].base.index == input_index and node.nodes[0].name == sub_name:
					tree['r' + op_names[node.op]] = parse_node.call(node.nodes[1])
					dealed = true
				if not dealed and node.nodes[0].base is ExpressionSQLInputNode and \
				node.nodes[0].base.name == input_name and node.nodes[0].base.subname == sub_name:
					tree['r' + op_names[node.op]] = parse_node.call(node.nodes[1])
					dealed = true
		if not dealed:
			# 检查这个分支和要查的字段有没有关系，如果有关系，设置为null，没有关系，就把这个操作忽略
			if contains_input_name(node.nodes[0], input_name, sub_name) or \
			contains_input_name(node.nodes[1], input_name, sub_name):
				tree['r' + op_names[node.op]] = null # null表示复杂情况
				
func contains_input_name(p_node, input_name: String, sub_name: String) -> bool:
	match (p_node.type) :
		ExpressionENode.Type.TYPE_INPUT:
			var input_index = input_names.find(input_name)
			var sub_index = input_names.find(sub_name)
			var _in = p_node as ExpressionInputNode
			return _in.index == input_index or _in.index == sub_index
		ExpressionENode.Type.TYPE_CONSTANT:
			return false
		ExpressionENode.Type.TYPE_SELF:
			return false
		ExpressionENode.Type.TYPE_OPERATOR:
			var op = p_node as ExpressionOperatorNode
			var ret = contains_input_name(op.nodes[0], input_name, sub_name)
			if (ret) :
				return true
				
			if (op.nodes[1]) :
				ret = contains_input_name(op.nodes[1], input_name, sub_name)
				if (ret) :
					return true
			return false
		ExpressionENode.Type.TYPE_INDEX:
			var index = p_node as ExpressionIndexNode
			var ret = contains_input_name(index.base, input_name, sub_name)
			if (ret) :
				return true
				
			ret = contains_input_name(index.index, input_name, sub_name)
			if (ret) :
				return true
			return false
		ExpressionENode.Type.TYPE_NAMED_INDEX:
			var index = p_node as ExpressionNamedIndexNode
			if index.base is String:
				if index.base == input_name and index.name == sub_name:
					return true
			else:
				var ret = contains_input_name(index.base, input_name, sub_name)
				if ret and index.name == sub_name:
					return true
			return false
		ExpressionENode.Type.TYPE_ARRAY:
			var array = p_node as ExpressionArrayNode
			for i in array.array:
				var ret = contains_input_name(i, input_name, sub_name)
				if (ret) :
					return true
			return false
		ExpressionENode.Type.TYPE_DICTIONARY:
			var dictionary = p_node as ExpressionDictionaryNode
			for i in dictionary.dict:
				var ret = contains_input_name(i, input_name, sub_name)
				if (ret) :
					return true
			return false
		ExpressionENode.Type.TYPE_CONSTRUCTOR:
			var constructor = p_node as ExpressionConstructorNode
			for i in constructor.arguments:
				var ret = contains_input_name(i, input_name, sub_name)
				if (ret) :
					return true
			return false
		ExpressionENode.Type.TYPE_BUILTIN_FUNC:
			var bifunc = p_node as ExpressionBuiltinFuncNode
			for i in bifunc.arguments:
				var ret = contains_input_name(i, input_name, sub_name)
				if (ret) :
					return true
			return false
		ExpressionENode.Type.TYPE_BUILTIN_FUNC_CALLABLE:
			return false
		ExpressionENode.Type.TYPE_CLASS:
			return false
		ExpressionENode.Type.TYPE_CALL:
			var _call = p_node as ExpressionCallNode
			var ret = contains_input_name(_call.base, input_name, sub_name)
			if (ret) :
				return true
				
			for i in _call.arguments:
				ret = contains_input_name(i, input_name, sub_name)
				if (ret) :
					return true
					
			if _call.method is ExpressionENode:
				ret = contains_input_name(_call.method, input_name, sub_name)
				if (ret):
					return true
					
			return false
		ExpressionENode.Type.TYPE_SQL_SELECT:
			var select = p_node as ExpressionSelectNode
			if select.value and select.value is GDSQL.QueryResult:
				if select.value.get_lack_tables().has(input_name):
					return true
				return false
			if select.expression:
				return select.expression.contains_input_name(
					select.expression.root, input_name, sub_name)
			assert(false, "Inner error 3996 in expression.gd") # 没考虑到的情况？
			return false
		ExpressionENode.Type.TYPE_SQL_INPUT:
			var input = p_node as ExpressionSQLInputNode
			if input.value_set:
				return false
			# input.info结构：
			#     {
			#         true: ['a', 'b'],	# true表示x是一个普通表名，value是一个数组表示x中的字段（可能是多个表合并起来的）
			#         false: index,		# false表示x是一个补充表名（来自BaseDao的__input_names）
			#         'y': 0,			# 字符串表示x是一个普通表y中的一个字段
			#         N: 0,				# 整数表示x是一个补充表中的一个字段，N表示该表在__input_names中的位置
			#     }
			if input.name == input_name:
				if input.subname == sub_name:
					return true
				elif input.subname == "":
					if input.info.has(true):
						return true
			if input.name == sub_name:
				for k in input.info:
					if k is String and k == input_name:
						return true
			return false
	return false
	
func all_constant_node(p_node):
	match (p_node.type) :
		ExpressionENode.Type.TYPE_INPUT:
			return false
		ExpressionENode.Type.TYPE_CONSTANT:
			return true
		ExpressionENode.Type.TYPE_SELF:
			return false
		ExpressionENode.Type.TYPE_OPERATOR:
			var op = p_node as ExpressionOperatorNode
			var ret = all_constant_node(op.nodes[0])
			if not ret:
				return false
				
			if (op.nodes[1]) :
				ret = all_constant_node(op.nodes[1])
				if (not ret) :
					return false
			return true
		ExpressionENode.Type.TYPE_INDEX:
			var index = p_node as ExpressionIndexNode
			var ret = all_constant_node(index.base)
			if (not ret) :
				return false
				
			ret = all_constant_node(index.index)
			if (not ret) :
				return false
			return true
		ExpressionENode.Type.TYPE_NAMED_INDEX:
			return false
		ExpressionENode.Type.TYPE_ARRAY:
			var array = p_node as ExpressionArrayNode
			for i in array.array:
				var ret = all_constant_node(i)
				if (not ret) :
					return false
			return true
		ExpressionENode.Type.TYPE_DICTIONARY:
			var dictionary = p_node as ExpressionDictionaryNode
			for i in dictionary.dict:
				var ret = all_constant_node(i)
				if (not ret) :
					return false
			return true
		ExpressionENode.Type.TYPE_CONSTRUCTOR:
			var constructor = p_node as ExpressionConstructorNode
			for i in constructor.arguments:
				var ret = all_constant_node(i)
				if (not ret) :
					return false
			return true
		ExpressionENode.Type.TYPE_BUILTIN_FUNC:
			var bifunc = p_node as ExpressionBuiltinFuncNode
			for i in bifunc.arguments:
				var ret = all_constant_node(i)
				if (not ret) :
					return false
			return true
		ExpressionENode.Type.TYPE_BUILTIN_FUNC_CALLABLE:
			return true
		ExpressionENode.Type.TYPE_CLASS:
			return true
		ExpressionENode.Type.TYPE_CALL:
			var _call = p_node as ExpressionCallNode
			var ret = all_constant_node(_call.base)
			if (not ret) :
				return false
				
			for i in _call.arguments:
				ret = all_constant_node(i)
				if (not ret) :
					return false
					
			if _call.method is ExpressionENode:
				ret = all_constant_node(_call.method)
				if (not ret):
					return false
					
			return true
		ExpressionENode.Type.TYPE_SQL_SELECT:
			var select = p_node as ExpressionSelectNode
			if select.value and select.value is GDSQL.QueryResult:
				return true
			if select.expression:
				return select.expression.all_constant_node(select.expression.root)
			assert(false, "Inner error 4042 in expression.gd") # 没考虑到的情况？
			return true
	assert(false, "Inner error 4063 in expression.gd") # 没考虑到的情况？
	return false
	
func _compile_expression() -> bool:
	if (!expression_dirty) :
		return error_set
	

	if (nodes) :
		#memdelete(nodes)
		nodes = null
		root = null
	

	error_str = ""
	error_set = false
	str_ofs = 0

	root = _parse_expression()

	if (error_set) :
		root = null
		if (nodes) :
			pass #memdelete(nodes)
		
		nodes = null
		return true
	

	expression_dirty = false
	return false


func _execute(p_inputs: Array, p_sql_varying_inputs: Dictionary, p_instance: Object, p_node, r_ret: Array, p_const_calls_only: bool, r_error_str: Array) -> bool:
	match (p_node.type) :
		ExpressionENode.Type.TYPE_INPUT:
			var _in = p_node as ExpressionInputNode
			if (_in.index < 0 || _in.index >= p_inputs.size()) :
				r_error_str[0] = tr("Invalid input %d (not passed) in expression") % _in.index
				return true

			r_ret[0] = p_inputs[_in.index]
			#break
		ExpressionENode.Type.TYPE_CONSTANT:
			var c = p_node as ExpressionConstantNode
			r_ret[0] = c.value

			#break
		ExpressionENode.Type.TYPE_SELF:
			if (!p_instance) :
				var sn = p_node as ExpressionSelfNode
				if sn.possible_global_enum:
					r_ret[0] = GLOBAL_ENUM_AND_FLAG
				else:
					r_error_str[0] = tr("self can't be used because instance is null (not passed)")
					return true
			else:
				r_ret[0] = p_instance
			#break
		ExpressionENode.Type.TYPE_OPERATOR:
			var op = p_node as ExpressionOperatorNode

			var a = [null]
			var ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, op.nodes[0], a, p_const_calls_only, r_error_str)
			if (ret) :
				return true
				
			# a[0] == null is ok
			if sql_mode and a[0] is GDSQL.AggregateFunctions:
				r_ret[0] = a[0]
				return false


			var b = [null]

			if (op.nodes[1]) :
				ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, op.nodes[1], b, p_const_calls_only, r_error_str)
				if (ret) :
					return true
					
				# b[0] == null is ok
				if sql_mode and b[0] is GDSQL.AggregateFunctions:
					r_ret[0] = b[0]
					return false
					
			if sql_mode and (a[0] is GDSQL.QueryResult or b[0] is GDSQL.QueryResult):
				# Any row contains null make the final result a null
				# NOTICE Bad for discover possible error so comment these codes.
				#if a[0] is GDSQL.QueryResult:
					#for row in a[0].get_data():
						#for i in row:
							#if i == null:
								#r_ret[0] = null
								#return false
				#if b[0] is GDSQL.QueryResult:
					#for row in b[0].get_data():
						#for i in row:
							#if i == null:
								#r_ret[0] = null
								#return false
				match op.op:
					OP_EQUAL, OP_NOT_EQUAL:
						if a[0] is GDSQL.QueryResult and b[0] is GDSQL.QueryResult and \
						a[0].get_columns_count() != b[0].get_columns_count():
							r_error_str[0] = tr("Operand should contain %d column(s)" % 
								a[0].get_columns_count())
							return true
						var a_and_b = [a, b]
						for i in 2:
							var c = a_and_b[0]
							var d = a_and_b[1]
							if c[0] is GDSQL.QueryResult:
								if d[0] is GDSQL.QueryResult:
									c[0] = c[0].get_data()
									d[0] = d[0].get_data()
								elif d[0] is Array:
									if d[0].is_empty():
										# 当数据集为空时，也算该数据集等于一个空数组;
										# 当数据集不为空时，随便c[0].get_data()是什么值，
										# 都不会影响OP_EQUAL、OP_NOT_EQUAL的判断结果
										c[0] = c[0].get_data()
									# WARNING 从使用习惯上来说，d[0][0]和c[0]大概率是
									# 一个字段的数据进行比较，那么把二维数组转为一维数组。
									# 当然，这个假设是有漏洞的，但是确实没有办法覆盖所有场景。
									# 但是用户可以通过调用QueryResult的方法来规避不明确的问题，
									# 比如：[[1, "peter"], [2, "tom"]] == (select * from UserData.t_user).get_data()
									# 来比较二维数组。
									# 比如：[1, 2, 3] == (select * from UserData.t_user).get_column(0, []).sort()
									# 来比较一维数组。
									else:
										var rows = c[0].get_data()
										if rows.is_empty():
											c[0] = rows
										elif rows[0].size() != 1:
											r_error_str[0] = tr("Subquery returns more than 1 column.")
											return true
										else:
											c[0] = c[0].get_column(0)
								else:
									if _deal_query_result(c, r_error_str):
										return true
								break
							else:
								a_and_b.reverse()
								
					OP_LESS, OP_LESS_EQUAL, OP_GREATER, OP_GREATER_EQUAL, \
					OP_ADD, OP_SUBTRACT, OP_MULTIPLY, OP_DIVIDE, OP_MODULE, \
					OP_POWER, OP_SHIFT_LEFT, OP_SHIFT_RIGHT, OP_BIT_AND, \
					OP_BIT_OR, OP_BIT_XOR, OP_BIT_NEGATE, OP_AND, OP_OR:
						var a_and_b = [a, b]
						for i in a_and_b.size():
							if a_and_b[i][0] is GDSQL.QueryResult and _deal_query_result(a_and_b[i], r_error_str):
								return true
					OP_IN:
						if a[0] is GDSQL.QueryResult and b[0] is GDSQL.QueryResult and \
						a[0].get_columns_count() != b[0].get_columns_count():
							r_error_str[0] = tr("Operand should contain %d column(s)" % 
								a[0].get_columns_count())
							return true
						elif a[0] is GDSQL.QueryResult:
							if a[0].get_columns_count() != 1:
								r_error_str[0] = tr("Operand should contain 1 column.")
								return true
							a[0] = a[0].get_column(0, [])
						elif b[0] is GDSQL.QueryResult:
							if b[0].get_columns_count() != 1:
								r_error_str[0] = tr("Operand should contain 1 column.")
								return true
							b[0] = b[0].get_column(0, [])
					OP_NEGATE, OP_POSITIVE, OP_BIT_NEGATE, OP_NOT:
						if a[0] is GDSQL.QueryResult and _deal_query_result(a, r_error_str):
							return true
					OP_XOR: # 逻辑异或运算符（未在 GDScript 中实现）
						pass
					_: # 其他运算符，在下面进行拦截，这里不拦截了
						pass
						
			var valid = true
			#evaluate(op.op, a[0], b[0], r_ret, valid)
			match op.op:
				OP_EQUAL: # = 0 相等运算符（==）。
					if sql_mode:
						r_ret[0] = typeof(a[0]) == typeof(b[0]) and a[0] == b[0]
					else:
						r_ret[0] = a[0] == b[0]
				OP_NOT_EQUAL: # = 1 不等运算符（!=）。
					r_ret[0] = a[0] != b[0]
				OP_LESS: # = 2 小于运算符（<）。
					r_ret[0] = a[0] < b[0]
				OP_LESS_EQUAL: # = 3 小于等于运算符（<=）。
					r_ret[0] = a[0] <= b[0]
				OP_GREATER: # = 4 大于运算符（>）。
					r_ret[0] = a[0] > b[0]
				OP_GREATER_EQUAL: # = 5 大于等于运算符（>=）。
					r_ret[0] = a[0] >= b[0]
				OP_ADD: # = 6 加法运算符（+）。
					r_ret[0] = a[0] + b[0]
				OP_SUBTRACT: # = 7 减法运算符（-）。
					r_ret[0] = a[0] - b[0]
				OP_MULTIPLY: # = 8 乘法运算符（*）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_MULTIPLY") % a[0]
							return true
					if b[0] is String:
						if (b[0] as String).is_valid_int():
							b[0] = (b[0] as String).to_int()
						elif (b[0] as String).is_valid_float():
							b[0] = (b[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_MULTIPLY") % b[0]
							return true
					r_ret[0] = a[0] * b[0]
				OP_DIVIDE: # = 9 除法运算符（/）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_DIVIDE") % a[0]
							return true
					if b[0] is String:
						if (b[0] as String).is_valid_int():
							b[0] = (b[0] as String).to_int()
						elif (b[0] as String).is_valid_float():
							b[0] = (b[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_DIVIDE") % b[0]
							return true
					r_ret[0] = a[0] / b[0]
				OP_NEGATE: # = 10 一元减号运算符（-）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_NEGATE") % a[0]
							return true
					r_ret[0] = -a[0]
				OP_POSITIVE: # = 11 一元加号运算符（+）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_POSITIVE") % a[0]
							return true
					r_ret[0] = a[0]
				OP_MODULE: # = 12 余数/取模运算符（%）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_MODULE") % a[0]
							return true
					if b[0] is String:
						if (b[0] as String).is_valid_int():
							b[0] = (b[0] as String).to_int()
						elif (b[0] as String).is_valid_float():
							b[0] = (b[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_MODULE") % b[0]
							return true
					r_ret[0] = a[0] % b[0]
				OP_POWER: # = 13 幂运算符（**）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_POWER") % a[0]
							return true
					if b[0] is String:
						if (b[0] as String).is_valid_int():
							b[0] = (b[0] as String).to_int()
						elif (b[0] as String).is_valid_float():
							b[0] = (b[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_POWER") % b[0]
							return true
					r_ret[0] = a[0] ** b[0]
				OP_SHIFT_LEFT: # = 14 左移运算符（<<）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_SHIFT_LEFT") % a[0]
							return true
					if b[0] is String:
						if (b[0] as String).is_valid_int():
							b[0] = (b[0] as String).to_int()
						elif (b[0] as String).is_valid_float():
							b[0] = (b[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_SHIFT_LEFT") % b[0]
							return true
					r_ret[0] = a[0] << b[0]
				OP_SHIFT_RIGHT: # = 15 右移运算符（>>）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_SHIFT_RIGHT") % a[0]
							return true
					if b[0] is String:
						if (b[0] as String).is_valid_int():
							b[0] = (b[0] as String).to_int()
						elif (b[0] as String).is_valid_float():
							b[0] = (b[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_SHIFT_RIGHT") % b[0]
							return true
					r_ret[0] = a[0] >> b[0]
				OP_BIT_AND: # = 16 按位与运算符（&）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_BIT_AND") % a[0]
							return true
					if b[0] is String:
						if (b[0] as String).is_valid_int():
							b[0] = (b[0] as String).to_int()
						elif (b[0] as String).is_valid_float():
							b[0] = (b[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_BIT_AND") % b[0]
							return true
					r_ret[0] = a[0] & b[0]
				OP_BIT_OR: # = 17 按位或运算符（|）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_BIT_OR") % a[0]
							return true
					if b[0] is String:
						if (b[0] as String).is_valid_int():
							b[0] = (b[0] as String).to_int()
						elif (b[0] as String).is_valid_float():
							b[0] = (b[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_BIT_OR") % b[0]
							return true
					r_ret[0] = a[0] | b[0]
				OP_BIT_XOR: # = 18 按位异或运算符（^）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_BIT_XOR") % a[0]
							return true
					if b[0] is String:
						if (b[0] as String).is_valid_int():
							b[0] = (b[0] as String).to_int()
						elif (b[0] as String).is_valid_float():
							b[0] = (b[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_BIT_XOR") % b[0]
							return true
					r_ret[0] = a[0] ^ b[0]
				OP_BIT_NEGATE: # = 19 按位非运算符（~）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_BIT_NEGATE") % a[0]
							return true
					r_ret[0] = ~a[0]
				OP_AND: # = 20 逻辑与运算符（and 或 &&）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						elif a[0] == "true":
							a[0] = true
						elif a[0] == "false":
							a[0] = false
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_AND") % a[0]
							return true
					if b[0] is String:
						if (b[0] as String).is_valid_int():
							b[0] = (b[0] as String).to_int()
						elif (b[0] as String).is_valid_float():
							b[0] = (b[0] as String).to_float()
						elif b[0] == "true":
							b[0] = true
						elif b[0] == "false":
							b[0] = false
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_AND") % b[0]
							return true
					r_ret[0] = a[0] and b[0]
				OP_OR: # = 21 逻辑或运算符（or 或 ||）。
					if a[0] is String:
						if (a[0] as String).is_valid_int():
							a[0] = (a[0] as String).to_int()
						elif (a[0] as String).is_valid_float():
							a[0] = (a[0] as String).to_float()
						elif a[0] == "true":
							a[0] = true
						elif a[0] == "false":
							a[0] = false
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_AND") % a[0]
							return true
					if b[0] is String:
						if (b[0] as String).is_valid_int():
							b[0] = (b[0] as String).to_int()
						elif (b[0] as String).is_valid_float():
							b[0] = (b[0] as String).to_float()
						elif b[0] == "true":
							b[0] = true
						elif b[0] == "false":
							b[0] = false
						else:
							r_error_str[0] = tr("Invalid String: '%s' in OP_AND") % b[0]
							return true
					r_ret[0] = a[0] or b[0]
				OP_XOR: # = 22 逻辑异或运算符（未在 GDScript 中实现）。
					pass
				OP_NOT: # = 23 逻辑非运算符（not 或 !）。
					r_ret[0] = not a[0]
				OP_IN: # = 24 逻辑 IN 运算符（in）。
					r_ret[0] = a[0] in b[0]
				_:
					valid = false
			if (!valid) :
				r_error_str[0] = tr("Invalid operands to operator %s, %s and %s.") % [get_operator_name(op.op), type_string(typeof(a)), type_string(typeof(b))]
				return true


			#break
		ExpressionENode.Type.TYPE_INDEX:
			var index = p_node as ExpressionIndexNode

			var base = [null]
			var ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, index.base, base, p_const_calls_only, r_error_str)
			if (ret) :
				return true
				
			if sql_mode and (base[0] == null or base[0] is GDSQL.AggregateFunctions):
				r_ret[0] = base[0]
				return false
				
			if sql_mode and base[0] is GDSQL.QueryResult and _deal_query_result(base, r_error_str):
				return true

			var idx = [null]

			ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, index.index, idx, p_const_calls_only, r_error_str)
			if (ret) :
				return true
				
			if sql_mode and (idx[0] == null or idx[0] is GDSQL.AggregateFunctions):
				r_ret[0] = idx[0]
				return false


			if sql_mode and idx[0] is GDSQL.QueryResult and _deal_query_result(idx, r_error_str):
				return true
				
			#var valid
			#r_ret[0] = base[0].get(idx[0], valid) # base.get(idx, &valid)
			#if (!valid) :
				#r_error_str[0] = tr("Invalid index of type %s for base type %s") % [type_string(typeof(idx)), type_string(typeof(base))]
				#return true
			if base[0] is Array or base[0] is Dictionary or base[0] is PackedByteArray or \
			base[0] is PackedColorArray or base[0] is PackedFloat32Array or \
			base[0] is PackedFloat64Array or base[0] is PackedInt32Array or \
			base[0] is PackedInt64Array or base[0] is PackedStringArray or \
			base[0] is PackedVector2Array or base[0] is PackedVector3Array or \
			base[0] is PackedVector4Array:
				r_ret[0] = base[0][idx[0]]
			elif base[0] is Object:
				if idx[0] is String or idx[0] is StringName:
					if idx[0] in (base[0] as Object):
						r_ret[0] = (base[0] as Object).get(idx[0])
					else:
						r_error_str[0] = "Invalid access to property or key '" + idx[0] + "' on a base object of type '" + _get_var_type(base[0]) + "'."
						return true
				else:
					r_error_str[0] = 'Only "String" or "StringName" can be used as index for type "%s", but received "%s"' % [_get_var_type(base[0]), type_string(typeof(idx[0]))]
					return true
			else:
				push_warning("Unrecognized type: %s in 4732 in expression.gd" % typeof(idx[0]))
				var idxstr = var_to_str(idx[0])
				var ex_key = "a[" + idxstr + "]"
				var ex = EXPRESSION_CACHE.get_value(ex_key)
				if not ex:
					ex = Expression.new()
					var err = ex.parse(ex_key, ["a"])
					if err != OK:
						r_error_str[0] = ex.get_error_text()
						return true
					EXPRESSION_CACHE.put_value(ex_key, ex)
				var v = ex.execute([base[0], idxstr], null, false)
				if ex.has_execute_failed():
					r_error_str[0] = ex.get_error_text()
					return true
				r_ret[0] = v
				

			#break
		ExpressionENode.Type.TYPE_NAMED_INDEX:
			var index = p_node as ExpressionNamedIndexNode

			var base = [null]
			var ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, index.base, base, p_const_calls_only, r_error_str)
			if (ret) :
				return true
				
			if sql_mode and (base[0] == null or base[0] is GDSQL.AggregateFunctions):
				r_ret[0] = base[0]
				return false
				
			if sql_mode and base[0] is GDSQL.QueryResult and _deal_query_result(base, r_error_str):
				return true


			var named_index = [index.name]
			# NOTICE Discard the idea that index.name may not be a String/StringName.
			## fix index.name is an input node
			#if named_index[0] is ExpressionENode:
				#ret = _execute(p_inputs, p_instance, index.name, named_index, p_const_calls_only, r_error_str)
				#if ret:
					#return true
				#named_index[0] = input_names[named_index[0]]
				
			#if sql_mode and (named_index[0] == null or named_index[0] is GDSQL.AggregateFunctions):
				#r_ret[0] = named_index[0]
				#return false
				
			#var valid
			#r_ret[0] = base[0].get_named(index.name, valid)
			#if (!valid) :
				#r_error_str[0] = tr("Invalid named index '%s' for base type %s") % [str(index.name), type_string(base.get_type())]
				#return true
			if base[0] is Object:
				if named_index[0] is String or named_index[0] is StringName:
					if named_index[0] in (base[0] as Object):
						r_ret[0] = (base[0] as Object).get(named_index[0])
					else:
						r_error_str[0] = tr("Invalid access to property or key '%s' on a base object of type '%s'.") % [
							named_index[0], _get_var_type(base[0])]
						return true
				else:
					r_error_str[0] = tr('Only "String" or "StringName" can be used as index for type "%s", but received "%s"') % [
						_get_var_type(base[0]), type_string(typeof(named_index[0]))]
					return true
			elif base[0] is Dictionary:
				if base[0].has(named_index[0]):
					r_ret[0] = base[0].get(named_index[0])
				else:
					if index.base is ExpressionSQLInputNode:
						r_error_str[0] = tr("Unknown column: %s.%s in expression: %s") % [index.base.name, index.name, expression]
					else:
						r_error_str[0] = tr("Invalid access to property or key '%s' on a base object of type '%s'.") % [
							named_index[0], _get_var_type(base[0])]
					return true
			else:
				push_warning("Unrecognized type: %s in 4782 in expression.gd" % typeof(base[0]))
				var ex_key = "a." + named_index[0]
				var ex = EXPRESSION_CACHE.get_value(ex_key)
				if not ex:
					ex = Expression.new()
					var err = ex.parse(ex_key, ["a"])
					if err != OK:
						r_error_str[0] = ex.get_error_text()
						return true
					EXPRESSION_CACHE.put_value(ex_key, ex)
					
				var v = ex.execute([base[0], named_index[0]], null, false)
				if ex.has_execute_failed():
					r_error_str[0] = ex.get_error_text()
					return true
				r_ret[0] = v


			#break
		ExpressionENode.Type.TYPE_ARRAY:
			var array = p_node as ExpressionArrayNode

			var arr = []
			arr.resize(array.array.size())
			for i in array.array.size():
				var value = [null]
				var ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, array.array[i], value, p_const_calls_only, r_error_str)

				if (ret) :
					return true
					
				if sql_mode and value[0] is GDSQL.QueryResult and _deal_query_result(value, r_error_str):
					return true
					
				arr[i] = value[0]


			r_ret[0] = arr

			#break
		ExpressionENode.Type.TYPE_DICTIONARY:
			var dictionary = p_node as ExpressionDictionaryNode

			var d = {}
			for i in range(0, dictionary.dict.size(), 2):
				var key = [null]
				var ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, dictionary.dict[i + 0], key, p_const_calls_only, r_error_str)

				if (ret) :
					return true
	
				if sql_mode and key[0] is GDSQL.QueryResult and _deal_query_result(key, r_error_str):
					return true

				var value = [null]
				ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, dictionary.dict[i + 1], value, p_const_calls_only, r_error_str)
				if (ret) :
					return true

				if sql_mode and value[0] is GDSQL.QueryResult and _deal_query_result(value, r_error_str):
					return true

				d[key[0]] = value[0]


			r_ret[0] = d
			#break
		ExpressionENode.Type.TYPE_CONSTRUCTOR:
			var constructor = p_node as ExpressionConstructorNode

			var arr = []
			#var argp = []
			arr.resize(constructor.arguments.size())
			#argp.resize(constructor.arguments.size())

			for i in constructor.arguments.size():
				var value = [null]
				var ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, constructor.arguments[i], value, p_const_calls_only, r_error_str)

				if (ret) :
					return true
	
				if sql_mode and (value[0] == null or value[0] is GDSQL.AggregateFunctions):
					r_ret[0] = value[0]
					return false

				if sql_mode and value[0] is GDSQL.QueryResult and _deal_query_result(value, r_error_str):
					return true
					
				arr[i] = value[0]
				#argp[i] = arr[i] # argp.write[i] = &arr[i];


			#Callable.CallError ce
			#construct(constructor.data_type, r_ret, (const Variant **)argp.ptr(), argp.size(), ce)

			#if (ce.error != Callable.CallError.CALL_OK) :
				#r_error_str[0] = vformat(RTR("Invalid arguments to construct '%s'"), get_type_name(constructor.data_type))
				#return true
				
			match constructor.data_type:
				TYPE_BOOL:
					match arr.size():
						0: r_ret[0] = bool()
						1: r_ret[0] = bool(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_INT:
					match arr.size():
						0: r_ret[0] = int()
						1: r_ret[0] = int(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_FLOAT:
					match arr.size():
						0: r_ret[0] = float()
						1: r_ret[0] = float(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_STRING:
					match arr.size():
						0: r_ret[0] = String()
						1: r_ret[0] = String(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_VECTOR2:
					match arr.size():
						0: r_ret[0] = Vector2()
						1: r_ret[0] = Vector2(arr[0])
						2: r_ret[0] = Vector2(arr[0], arr[1])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_VECTOR2I:
					match arr.size():
						0: r_ret[0] = Vector2i()
						1: r_ret[0] = Vector2i(arr[0])
						2: r_ret[0] = Vector2i(arr[0], arr[1])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_VECTOR3:
					match arr.size():
						0: r_ret[0] = Vector3()
						1: r_ret[0] = Vector3(arr[0])
						3: r_ret[0] = Vector3(arr[0], arr[1], arr[2])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_VECTOR3I:
					match arr.size():
						0: r_ret[0] = Vector3i()
						1: r_ret[0] = Vector3i(arr[0])
						3: r_ret[0] = Vector3i(arr[0], arr[1], arr[2])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_VECTOR4:
					match arr.size():
						0: r_ret[0] = Vector4()
						1: r_ret[0] = Vector4(arr[0])
						4: r_ret[0] = Vector4(arr[0], arr[1], arr[2], arr[3])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_VECTOR4I:
					match arr.size():
						0: r_ret[0] = Vector4i()
						1: r_ret[0] = Vector4i(arr[0])
						4: r_ret[0] = Vector4i(arr[0], arr[1], arr[2], arr[3])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_PLANE:
					match arr.size():
						0: r_ret[0] = Plane()
						1: r_ret[0] = Plane(arr[0])
						2: r_ret[0] = Plane(arr[0], arr[1])
						3: r_ret[0] = Plane(arr[0], arr[1], arr[2])
						4: r_ret[0] = Plane(arr[0], arr[1], arr[2], arr[3])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_QUATERNION:
					match arr.size():
						0: r_ret[0] = Quaternion()
						1: r_ret[0] = Quaternion(arr[0])
						2: r_ret[0] = Quaternion(arr[0], arr[1])
						4: r_ret[0] = Quaternion(arr[0], arr[1], arr[2], arr[3])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_AABB:
					match arr.size():
						0: r_ret[0] = AABB()
						1: r_ret[0] = AABB(arr[0])
						2: r_ret[0] = AABB(arr[0], arr[1])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_BASIS:
					match arr.size():
						0: r_ret[0] = Basis()
						1: r_ret[0] = Basis(arr[0])
						2: r_ret[0] = Basis(arr[0], arr[1])
						3: r_ret[0] = Basis(arr[0], arr[1], arr[2])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_TRANSFORM3D:
					match arr.size():
						0: r_ret[0] = Transform3D()
						1: r_ret[0] = Transform3D(arr[0])
						2: r_ret[0] = Transform3D(arr[0], arr[1])
						4: r_ret[0] = Transform3D(arr[0], arr[1], arr[2], arr[3])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_PROJECTION:
					match arr.size():
						0: r_ret[0] = Projection()
						1: r_ret[0] = Projection(arr[0])
						4: r_ret[0] = Projection(arr[0], arr[1], arr[2], arr[3])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_COLOR:
					match arr.size():
						0: r_ret[0] = Color()
						1: r_ret[0] = Color(arr[0])
						2: r_ret[0] = Color(arr[0], arr[1])
						3: r_ret[0] = Color(arr[0], arr[1], arr[2])
						4: r_ret[0] = Color(arr[0], arr[1], arr[2], arr[3])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_STRING_NAME:
					match arr.size():
						0: r_ret[0] = StringName()
						1: r_ret[0] = StringName(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_NODE_PATH:
					match arr.size():
						0: r_ret[0] = NodePath()
						1: r_ret[0] = NodePath(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_RID:
					match arr.size():
						0: r_ret[0] = RID()
						1: r_ret[0] = RID(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_CALLABLE:
					match arr.size():
						0: r_ret[0] = Callable()
						1: r_ret[0] = Callable(arr[0])
						2: r_ret[0] = Callable(arr[0], arr[1])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_SIGNAL:
					match arr.size():
						0: r_ret[0] = Signal()
						1: r_ret[0] = Signal(arr[0])
						2: r_ret[0] = Signal(arr[0], arr[1])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_DICTIONARY:
					match arr.size():
						0: r_ret[0] = Dictionary()
						1: r_ret[0] = Dictionary(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_ARRAY:
					r_ret[0] = Array(arr)
				TYPE_PACKED_BYTE_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedByteArray()
						1: r_ret[0] = PackedByteArray(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_PACKED_INT32_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedInt32Array()
						1: r_ret[0] = PackedInt32Array(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_PACKED_INT64_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedInt64Array()
						1: r_ret[0] = PackedInt64Array(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_PACKED_FLOAT32_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedFloat32Array()
						1: r_ret[0] = PackedFloat32Array(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_PACKED_FLOAT64_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedFloat64Array()
						1: r_ret[0] = PackedFloat64Array(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_PACKED_STRING_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedStringArray()
						1: r_ret[0] = PackedStringArray(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_PACKED_VECTOR2_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedVector2Array()
						1: r_ret[0] = PackedVector2Array(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_PACKED_VECTOR3_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedVector3Array()
						1: r_ret[0] = PackedVector3Array(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_PACKED_COLOR_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedColorArray()
						1: r_ret[0] = PackedColorArray(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				TYPE_PACKED_VECTOR4_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedVector4Array()
						1: r_ret[0] = PackedVector4Array(arr[0])
						_:
							r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
							return true
				_:
					r_error_str[0] = "Inner error expression.gd 4305"
					return true


			#break
		ExpressionENode.Type.TYPE_BUILTIN_FUNC:
			var bifunc = p_node as ExpressionBuiltinFuncNode

			var arr = []
			#var argp = []
			arr.resize(bifunc.arguments.size())
			#argp.resize(bifunc.arguments.size())

			for i in bifunc.arguments.size():
				var value = [null]
				var ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, bifunc.arguments[i], value, p_const_calls_only, r_error_str)
				if (ret) :
					return true
	
				if sql_mode and (value[0] == null or value[0] is GDSQL.AggregateFunctions):
					r_ret[0] = value[0]
					return false
					
				if sql_mode and value[0] is GDSQL.QueryResult and _deal_query_result(value, r_error_str):
					return true
					
				arr[i] = value[0]
				#argp[i] = arr[i] # argp.write[i] = &arr[i];


			r_ret[0] = utility_function_table[bifunc._func][2].callv(arr)
			#if (ce.error != Callable.CallError.CALL_OK) :
				#r_error_str[0] = "Builtin call failed: " + get_call_error_text(bifunc._func, (const Variant **)argp.ptr(), argp.size(), ce)
				#return true


			#break
		ExpressionENode.Type.TYPE_BUILTIN_FUNC_CALLABLE:
			var bifunccall = p_node as ExpressionBuiltinFuncCallableNode
			# Fix bifunccall._func is a property/method of the p_instance
			if p_instance:
				if bifunccall._func in p_instance:
					r_ret[0] = p_instance[bifunccall._func]
					return false
			r_ret[0] = utility_function_table[bifunccall._func][2]


			#break
		ExpressionENode.Type.TYPE_CLASS:
			var clazz = p_node as ExpressionClassNode
			
			var script = GDSQL.GDSQLUtils.gdscript
			script.source_code = "extends Object\nvar value = " + clazz._class
			var err = script.reload()
			if err != OK:
				r_error_str[0] = "Identifier \"" + clazz._class + "\" not declared in the current scope."
				return true
				
			var obj = script.new()
			r_ret[0] = obj.value
			obj.free()


			#break
		ExpressionENode.Type.TYPE_CALL:
			var _call = p_node as ExpressionCallNode

			var base = [null]
			var ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, _call.base, base, p_const_calls_only, r_error_str)

			if (ret) :
				return true
				
			# base[0] is AggregateFunctions is ok
			if sql_mode and base[0] == null:
				r_ret[0] = null
				return false
				
			if sql_mode and base[0] is GDSQL.QueryResult and _deal_query_result(base, r_error_str):
				return true


			var arr = []
			#var argp = []
			#arr.resize(_call.arguments.size())
			#argp.resize(_call.arguments.size())

			for i in _call.arguments.size():
				var value = [null]
				ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, _call.arguments[i], value, p_const_calls_only, r_error_str)

				if (ret) :
					return true
					
				# value[0] == null is ok
				if sql_mode and value[0] is GDSQL.AggregateFunctions:
					if not base[0] is GDSQL.AggregateFunctions:
						r_ret[0] = value[0]
						return false
						
				if sql_mode and value[0] is GDSQL.QueryResult and _deal_query_result(value, r_error_str):
					return true
					
				arr.push_back(value[0])
				#argp[i] = arr[i] # argp.write[i] = &arr[i]


			# fix _call.method is from input
			var method = [_call.method]
			if method[0] is ExpressionENode:
				ret = _execute(p_inputs, p_sql_varying_inputs, p_instance, _call.method, method, p_const_calls_only, r_error_str)

				if (ret):
					return true
					
				if sql_mode and method[0] is GDSQL.QueryResult and _deal_query_result(method, r_error_str):
					return true
					
			# support group_concat
			if sql_mode and method[0].contains('group_concat') and base[0] is GDSQL.AggregateFunctions:
				var index = -1
				var param = []
				for i in _call.arguments[0].arguments:
					index += 1
					if i is ExpressionExpressionNode:
						param.push_back(arr[index])
					elif i is ExpressionConstantNode:
						param.push_back(i.value)
					elif i is ExpressionInputNode:
						param.push_back(input_names[i.index])
					elif i is ExpressionNamedIndexNode:
						if i.name is ExpressionInputNode:
							param.push_back(i.base_name + '.' + input_names[i.name.index])
						else:
							param.push_back(i.base_name + '.' + i.name) # 点号左右可能有空白字符，但是不常见，这里不处理，让aggregate_function里尽量处理一下
					elif i is ExpressionCallNode:
						param.push_back(1) # ALERT not support actually
					elif i is ExpressionBuiltinFuncNode:
						param.push_back(1) # ALERT not support actually
					elif i is ExpressionConstructorNode:
						param.push_back(1) # ALERT not support actually
					elif i is ExpressionSQLInputNode:
						if i.subname != "":
							param.push_back(i.name + '.' + i.subname)
						else:
							param.push_back(i.name)
					else:
						r_error_str[0] = tr("Not support this: '%s' in group_concat") % i
						return true
				arr.push_back(param)
				
			#Callable.CallError ce
			if (p_const_calls_only) : # p_const_calls_only makes no difference here
				r_ret[0] = Callable.create(base[0], method[0]).callv(arr)
			else:
				r_ret[0] = Callable.create(base[0], method[0]).callv(arr)


			#if (ce.error != Callable.CallError.CALL_OK) :
				#r_error_str[0] = vformat(RTR("On call to '%s':"), String(call.method))
				#return true


			#break
		ExpressionENode.Type.TYPE_SQL_SELECT:
			var select = p_node as ExpressionSelectNode
			
			return select.cal(p_inputs, p_sql_varying_inputs, p_instance, 
				r_ret, p_const_calls_only, r_error_str)
				
		ExpressionENode.Type.TYPE_SQL_INPUT:
			var input_node = p_node as ExpressionSQLInputNode
			
			# 满足`补充表名.字段`的形式
			if input_node.value_set:
				r_ret[0] = input_node.value
				return false
				
			# sql_input_names的结构：
			# {
			#     'x': {
			#         true: ['a', 'b'],	# true表示x是一个普通表名，value是一个数组表示x中的字段（可能是多个表合并起来的）
			#         false: index,		# false表示x是一个补充表名（来自__input_names）
			#         'y': 0,			# 字符串表示x是一个普通表y中的一个字段
			#         N: 0,				# 整数表示x是一个补充表中的一个字段，N表示该表在__input_names中的位置
			#     }
			# }
			if input_node.subname == "":
				# 满足`普通表名.字段`的形式
				for k in input_node.info:
					if k is String:
						r_ret[0] = p_sql_varying_inputs[k][input_node.name] # 这里就不检查ambigious了，parse的时候检查过了
						return false
				r_error_str[0] = tr("Unknown column: %s in expression: %s") % [input_node.name, expression]
				return true
			else:
				# 优先满足`普通表名.字段`的形式
				for k in input_node.info:
					if k is bool and k:
						if p_sql_varying_inputs[input_node.name].has(input_node.subname):
							r_ret[0] = p_sql_varying_inputs[input_node.name]
							return false
						else:
							break
				# 其次满足`补充表名.字段`的形式 NOTICE parse的时候已经处理过了，跳过
				# 再次满足`普通表名`的形式
				for k in input_node.info:
					if k is bool and k:
						r_ret[0] = p_sql_varying_inputs[input_node.name]
						return false
				# 最后满足`补充表名`的形式
				for k in input_node.info:
					if k is bool and not k:
						r_ret[0] = sql_static_inputs[input_node.info[k]]
						return false
				r_error_str[0] = tr("Unknown column: %s.%s in expression: %s") % [
					input_node.name, input_node.subname, expression]
				return true
				
	return false

## 把QueryResult返回成一个具体的元素
func _deal_query_result(res: Array, r_error_str: Array) -> bool:
	var rows = res[0].get_data()
	if rows.is_empty():
		res[0] = null
		return false
	elif rows[0].size() != 1:
		r_error_str[0] = tr("Subquery returns more than 1 column.")
		return true
	elif rows.size() > 1:
		r_error_str[0] = tr("Subquery returns more than 1 row.")
		return true
	else:
		res[0] = rows[0][0]
		return false

func set_sql_input_names(p_input_names: Dictionary):
	sql_input_names = p_input_names
	
func set_nested_sql_queries(p_nested_sql_queries: Dictionary):
	nested_sql_queries = p_nested_sql_queries
	
func parse(p_expression, p_input_names = [], p_sql_static_inputs = []) -> Error:
	if (nodes) :
		#memdelete(nodes)
		nodes = null
		root = null
	

	error_str = String()
	error_set = false
	str_ofs = 0
	input_names = p_input_names
	sql_static_inputs = p_sql_static_inputs

	for i in p_input_names:
		if not (i is String or i is StringName):
			_set_error("input_names must contain only String or StringName")
			return ERR_INVALID_PARAMETER
		if _is_global_enum_or_flag(i):
			_set_error("input_names contains a global enum: " + i)
			return ERR_INVALID_PARAMETER
		if _is_class(i):
			_set_error("input_names contains a Class name: " + i)
			return ERR_INVALID_PARAMETER
		if has_utility_function(i):
			_set_error("input_names contains a builtin function: " + i)
			return ERR_INVALID_PARAMETER
		if ["in", "null", "true", "false", "PI", "TAU", "INF", "NAN", "not", "or", "and"].has(i):
			_set_error("input_names contains a keyword: " + i)
			return ERR_INVALID_PARAMETER
			
	expression = p_expression
	root = _parse_expression()

	if (error_set) :
		root = null
		#if (nodes) :
			#memdelete(nodes)
		
		nodes = null
		return ERR_INVALID_PARAMETER
	

	return OK


func execute(p_inputs: Array = [], p_sql_varying_inputs: Dictionary = {}, 
p_base: Object = null, p_show_error = true, p_const_calls_only = false) :
	if error_set:
		push_error("There was previously a parse error: " + error_str + ".")
		return null

	show_error = p_show_error
	execution_error = false
	var output = [null]
	var error_txt = [null]
	var err = _execute(p_inputs, p_sql_varying_inputs, p_base, root, output, p_const_calls_only, error_txt)
	if (err) :
		execution_error = true
		error_str = error_txt[0]
		if p_show_error:
			push_error(error_str)
			return null
	

	return output[0]


func has_execute_failed() -> bool:
	return execution_error


func get_error_text() -> String:
	return error_str

func _get_var_type(obj: Object) -> String:
	if str(obj) == '<Freed Object>':
		return 'previously freed'
	if str(obj) == '<null>':
		return 'null instance'
	if not obj:
		return 'null instance'
	var basestr = obj.get_class()
	if obj.get_script() and obj.get_script().get_global_name() != "":
		basestr += '(' + obj.get_script().get_global_name() + ')'
	return basestr
	
func _is_global_enum_or_flag(p_name: String) -> bool:
	if GLOBAL_ENUM_AND_FLAG.has(p_name):
		return true
		
	for i in GLOBAL_ENUM_AND_FLAG:
		if GLOBAL_ENUM_AND_FLAG[i].has(p_name):
			return true
			
	return false
	
func _is_class(p_name) -> bool:
	if not (p_name is String or p_name is StringName):
		return false
		
	# Native class
	if ClassDB.class_exists(p_name):
		return true
		
	# User custom class
	for i in ProjectSettings.get_global_class_list():
		if i.class == p_name:
			return true
			
	# Autoload.
	if ProjectSettings.has_setting("autoload/" + p_name):
		return true
		
	return false

func _identifier_to_input_if_match(identifier, r_err: Array):
	var input_index = input_names.find(identifier)
	#for i in input_names.size():
		#if (input_names[i] == identifier) :
			#input_index = i
			#break
			
	if (input_index != -1) :
		var input = alloc_node('InputNode')
		input.index = input_index
		identifier = input
	elif sql_mode:
		if sql_input_names.has(identifier):
			var input = alloc_node('SQLInputNode')
			input.name = identifier
			input.info = sql_input_names[identifier]
			identifier = input
		elif nested_sql_queries.has(identifier):
			var input = alloc_node("SelectNode")
			input.parse(sql_input_names, sql_static_inputs, nested_sql_queries[identifier], r_err)
			identifier = input
			
	return identifier
	
static func is_expression_e_node(obj) -> bool:
	return obj is ExpressionENode
	
static func is_none_const_expression_e_node(obj, r_ret: Array) -> bool:
	if obj is ExpressionSelectNode:
		if obj.value is GDSQL.QueryResult:
			r_ret[0] = obj.value
			return false
		return true
	if obj is ExpressionSQLInputNode:
		if obj.value_set:
			r_ret[0] = obj.value
			return false
		return true
	return obj is ExpressionENode
	
class ExpressionInput extends RefCounted:
	var type: int = TYPE_NIL
	var name: String
	
class ExpressionToken extends RefCounted:
	var type: TokenType
	var value
	var may_be_global_enum = false
	
class ExpressionENode extends RefCounted:
	enum Type {
		TYPE_INPUT,
		TYPE_CONSTANT,
		TYPE_SELF,
		TYPE_OPERATOR,
		TYPE_INDEX,
		TYPE_NAMED_INDEX,
		TYPE_ARRAY,
		TYPE_DICTIONARY,
		TYPE_CONSTRUCTOR,
		TYPE_BUILTIN_FUNC,
		TYPE_BUILTIN_FUNC_CALLABLE, # 函数本身
		TYPE_CLASS, # 类名
		TYPE_CALL,
		TYPE_SQL_SELECT,
		TYPE_SQL_INPUT,
	}

	var next: ExpressionENode

	var type: Type
	
class ExpressionExpressionNode extends RefCounted:
	var is_op = false
	var op: Variant.Operator
	var node: ExpressionENode
	
class ExpressionInputNode extends ExpressionENode:
	var index = 0
	func _init() -> void:
		type = ExpressionENode.Type.TYPE_INPUT
		
class ExpressionConstantNode extends ExpressionENode:
	var value
	func _init() -> void:
		type = ExpressionENode.Type.TYPE_CONSTANT
	


class ExpressionOperatorNode extends ExpressionENode:
	var op = OP_ADD

	var nodes = [null, null]

	func _init() -> void:
		type = ExpressionENode.Type.TYPE_OPERATOR
	


class ExpressionSelfNode extends ExpressionENode:
	var possible_global_enum = false
	func _init() -> void:
		type = ExpressionENode.Type.TYPE_SELF
	


class ExpressionIndexNode extends ExpressionENode:
	var base = null
	var index = null

	func _init() -> void:
		type = ExpressionENode.Type.TYPE_INDEX
	


class ExpressionNamedIndexNode extends ExpressionENode:
	var base = null
	var name
	var base_name # for sql_mode

	func _init() -> void:
		type = ExpressionENode.Type.TYPE_NAMED_INDEX
	


class ExpressionConstructorNode extends ExpressionENode:
	var data_type = TYPE_NIL
	var arguments: Array

	func _init() -> void:
		type = ExpressionENode.Type.TYPE_CONSTRUCTOR
	


class ExpressionCallNode extends ExpressionENode:
	var base = null
	var method
	var arguments: Array

	func _init() -> void:
		type = ExpressionENode.Type.TYPE_CALL
	


class ExpressionArrayNode extends ExpressionENode:
	var array: Array
	func _init() -> void:
		type = ExpressionENode.Type.TYPE_ARRAY
	


class ExpressionDictionaryNode extends ExpressionENode:
	var dict: Array
	func _init() -> void:
		type = ExpressionENode.Type.TYPE_DICTIONARY
	


class ExpressionBuiltinFuncNode extends ExpressionENode:
	@warning_ignore("unused_private_class_variable")
	var _func: StringName
	var arguments: Array
	func _init() -> void:
		type = ExpressionENode.Type.TYPE_BUILTIN_FUNC
	

class ExpressionBuiltinFuncCallableNode extends ExpressionENode:
	@warning_ignore("unused_private_class_variable")
	var _func: StringName
	func _init() -> void:
		type = ExpressionENode.Type.TYPE_BUILTIN_FUNC_CALLABLE


class ExpressionClassNode extends ExpressionENode:
	@warning_ignore("unused_private_class_variable")
	var _class: StringName
	func _init() -> void:
		type = ExpressionENode.Type.TYPE_CLASS

class ExpressionSelectNode extends ExpressionENode:
	var sql_input_names: Dictionary
	var sql_static_inputs: Array
	var info # QueryResult / {"sql": String, ___Rep0___: QueryResult, ___Rep1___: {"sql": String, ...}
	var value
	var expression#: GDSQL.SQLExpression
	
	func _init() -> void:
		type = ExpressionENode.Type.TYPE_SQL_SELECT
		
	func cal(p_inputs: Array, p_sql_varying_inputs: Dictionary, p_instance: Object, 
	r_ret: Array, p_const_calls_only: bool, r_error_str: Array):
		if value != null:
			r_ret[0] = value
			return false
			
		if expression:
			return expression._execute(p_inputs, p_sql_varying_inputs, p_instance, 
				expression.root, r_ret, p_const_calls_only, r_error_str)
				
		if info is Dictionary:
			# info's structure like:
			# {
			#     sql: select id from UserData.t_user where create_time == (___Rep1___)
			#     ___Rep1___: QueryResult
			# }
			var reps = info.duplicate()
			reps.erase("sql")
			# 如果是select开头的嵌套查询，就不能用expression
			if info.sql.length() > 6 and info.sql.countn("select", 0, 6) and \
			info.sql[6].strip_edges() == "":
				var input_names = [] # 补充表名
				var inputs = [] # 补充数据
				# sql_input_names 的结构：
				# {
				#     'x': {
				#         true: ['a', 'b'],	# true表示x是一个普通表名，value是一个数组表示x中的字段（可能是多个表合并起来的）
				#         false: index,		# false表示x是一个补充表名（来自__input_names）
				#         'y': 0,			# 字符串表示x是一个普通表y中的一个字段
				#         N: 0,				# 整数表示x是一个补充表中的一个字段，N表示该表在__input_names中的位置
				#     }
				# }
				for t in sql_input_names:
					if sql_input_names[t].has(true):
						input_names.push_back(t)
						inputs.push_back(p_sql_varying_inputs[t])
					if sql_input_names[t].has(false):
						if not input_names.has(t): # 优先级低于普通表名
							input_names.push_back(t)
							inputs.push_back(sql_static_inputs[sql_input_names[t][false]])
					# NOTICE 不管字段，因为inputs里包含了字段的数据，在子查询dao里，会自己重新构造input_names结构
					
				# 如果涉及其他表的数据，现在不能query怎么办？
				# 比如 select * from t where t.id == a.id，
				# 这里的办法是QueryResult增加lack_tables属性。
				var dao = GDSQL.SQLParser.parse_to_dao(info.sql)
				dao.set_collect_lack_table_mode(true)
				dao.set_need_head(false)
				dao.set_input_names(input_names)
				dao.set_inputs(inputs)
				dao.set_sub_queries(reps)
				value = dao.query()
				
				if value == null or not value.ok():
					r_error_str[0] = tr("Error occur in subquery: %s") % \
						info.sql if value == null else value.get_err()
					return true
					
				r_ret[0] = value
				return false
			# info.sql类似：1 + (__Rep0__)
			else:
				expression = GDSQL.SQLExpression.new()
				expression.sql_mode = true
				expression.set_sql_input_names(sql_input_names)
				expression.set_nested_sql_queries(reps)
				expression.parse(info.sql, [], sql_static_inputs)
				return expression._execute(p_inputs, p_sql_varying_inputs, p_instance, 
					expression.root, r_ret, p_const_calls_only, r_error_str)
		else:
			r_error_str[0] = tr("Inner error %s in expression.gd") % 5759 # 没考虑到的情况？
			return true
			
	func parse(p_sql_input_names: Dictionary, p_sql_static_inputs: Array, p_info, r_error_str: Array):
		sql_input_names = p_sql_input_names
		sql_static_inputs = p_sql_static_inputs
		info = p_info
		
		# QueryResult
		if info is GDSQL.QueryResult:
			value = info
		# Dictionary
		elif info is Dictionary:
			# info's structure like:
			# {
			#     sql: select id from UserData.t_user where create_time == (___Rep1___)
			#     ___Rep1___: QueryResult
			# }
			var reps = info.duplicate()
			reps.erase("sql")
			# 如果是select开头的嵌套查询，就不能用expression
			if info.sql.length() > 6 and info.sql.countn("select", 0, 6) and \
			info.sql[6].strip_edges() == "":
				var input_names = [] # 补充表名
				var inputs = [] # 补充数据
				# sql_input_names 的结构：
				# {
				#     'x': {
				#         true: ['a', 'b'],	# true表示x是一个普通表名，value是一个数组表示x中的字段（可能是多个表合并起来的）
				#         false: index,		# false表示x是一个补充表名（来自__input_names）
				#         'y': 0,			# 字符串表示x是一个普通表y中的一个字段
				#         N: 0,				# 整数表示x是一个补充表中的一个字段，N表示该表在__input_names中的位置
				#     }
				# }
				for t in sql_input_names:
					if sql_input_names[t].has(true):
						continue # parse阶段缺表缺数据，如果计算确实需要这部分数据的话，后面dao会反馈这一点
					if sql_input_names[t].has(false):
						if not input_names.has(t): # 优先级低于普通表名
							input_names.push_back(t)
							inputs.push_back(sql_static_inputs[sql_input_names[t][false]])
					# NOTICE 不管字段，因为inputs里包含了字段的数据，在子查询dao里，会自己重新构造input_names结构
					
				# 如果涉及其他表的数据，现在不能query怎么办？
				# 比如 select * from t where t.id == a.id，
				# 这里的办法是QueryResult增加lack_tables属性。
				var dao = GDSQL.SQLParser.parse_to_dao(info.sql)
				dao.set_collect_lack_table_mode(true)
				dao.set_need_head(false)
				dao.set_input_names(input_names)
				dao.set_inputs(inputs)
				dao.set_sub_queries(reps)
				value = dao.query()
				
				if value == null or not value.ok():
					if value and value.lack_data():
						# parse阶段缺数据没事，这个dao没啥用，不要了
						value = null
					else:
						r_error_str[0] = tr("Error occur in subquery: %s") % \
							info.sql if value == null else value.get_err()
			# info.sql类似：1 + (__Rep0__)
			else:
				expression = GDSQL.SQLExpression.new()
				expression.sql_mode = true
				expression.set_sql_input_names(sql_input_names)
				expression.set_nested_sql_queries(reps)
				expression.parse(info.sql, [], sql_static_inputs)
		else:
			r_error_str[0] = tr("Inner error %s in expression.gd") % 5828 # 没考虑到的情况？
			
class ExpressionSQLInputNode extends ExpressionENode:
	var name: String
	var subname: String # 可能存在
	var info: Dictionary
	var value # 当属于补充表的字段时，其实可以当作一个常量
	var value_set: bool = false
	
	func _init() -> void:
		type = ExpressionENode.Type.TYPE_SQL_INPUT
		
	## 该函数的目标是：判断该节点是否代表一个补充表中的字段，这样就能设置value为一个常数
	func parse(sql_input_names: Dictionary, sql_static_inputs: Array, r_error_str: Array):
		if subname == "":
			# 优先满足`普通表名.字段`的形式
			var flag = false
			for k in sql_input_names[name]:
				if k is String:
					if not flag:
						flag = true
					else:
						r_error_str[0] = tr("Ambigious column: %s") % name
						return
			if flag:
				return # 不能当常量，因为跟每一行的数据有关系，所以不设置value
				
			# 其次满足`补充表名.字段`的形式
			for k in sql_input_names[name]:
				if k is int:
					if not value_set:
						value = sql_static_inputs[k]
						value_set = true
					else:
						r_error_str[0] = tr("Ambigious column: %s") % name
						return
		else:
			# 优先满足`普通表名.字段`的形式
			for k in sql_input_names[name]:
				if k is bool and k:
					if sql_input_names[name].has(subname):
						return
					else:
						break
			# 其次满足`补充表名.字段`的形式
			for k in sql_input_names[name]:
				if k is bool and not k:
					if sql_static_inputs[sql_input_names[name][k]].has(subname):
						value = sql_static_inputs[sql_input_names[name][k]]
						value_set = true
						return
					else:
						break
						
class ExpressionCacheNode extends RefCounted:
	var key
	var value: Variant
	var prev: ExpressionCacheNode
	var next: ExpressionCacheNode
	
class ExpressionLRULink extends RefCounted:
	var cache: Dictionary
	var capacity: int
	var head: ExpressionCacheNode = ExpressionCacheNode.new()
	var tail: ExpressionCacheNode = ExpressionCacheNode.new()
	
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
		var node = cache[key] as ExpressionCacheNode
		move_to_tail(node)
		return node.value
		
	func remove_value(key):
		if not has_key(key):
			return
		var node = cache[key] as ExpressionCacheNode
		remove_node(node)
		cache.erase(key)
		
	func put_value(key, value: Variant):
		if cache.has(key):
			var node = cache[key] as ExpressionCacheNode
			node.value = value
			move_to_tail(node)
		else:
			var node = ExpressionCacheNode.new()
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
				
	func add_to_tail(node: ExpressionCacheNode):
		var prev_node = tail.prev
		prev_node.next = node
		node.prev = prev_node
		node.next = tail
		tail.prev = node
		
	func remove_node(node: ExpressionCacheNode):
		var prev_node = node.prev
		var next_node = node.next
		prev_node.next = next_node
		next_node.prev = prev_node
		
	func move_to_tail(node: ExpressionCacheNode):
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
		

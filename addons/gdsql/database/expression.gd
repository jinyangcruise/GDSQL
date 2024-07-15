@tool
extends RefCounted
class_name GDSQLExpression

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
	TK_PARENTHESIS_CLOSE,
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
	TK_OP_SUB,
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

var token_name: Array = [
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

var _op_names = [
	"==",
	"!=",
	"<",
	"<=",
	">",
	">=",
	"+",
	"-",
	"*",
	"/",
	"unary-",
	"unary+",
	"%",
	"**",
	"<<",
	">>",
	"&",
	"|",
	"^",
	"~",
	"and",
	"or",
	"xor",
	"not",
	"in"
]

var error_str
var error_set = true

var root: ExpressionENode
var nodes: ExpressionENode

var input_names: Array
var execution_error = false

const READING_SIGN = 0
const READING_INT = 1
const READING_HEX = 2
const READING_BIN = 3
const READING_DEC = 4
const READING_EXP = 5
const READING_DONE = 6

var xid_start = [
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

var xid_continue = [
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

var utility_function_table = {
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
	'max': [0, ' FUNCBINDVARARG(max, sarray(), Variant::UTILITY_FUNC_TYPE_MATH);', max],
	'maxi': [2, ' FUNCBINDR(maxi, sarray("a", "b"), Variant::UTILITY_FUNC_TYPE_MATH);', maxi],
	'maxf': [2, ' FUNCBINDR(maxf, sarray("a", "b"), Variant::UTILITY_FUNC_TYPE_MATH);', maxf],
	'min': [0, ' FUNCBINDVARARG(min, sarray(), Variant::UTILITY_FUNC_TYPE_MATH);', min],
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
	'str': [1, ' FUNCBINDVARARGS(str, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', str],
	'error_string': [1, ' FUNCBINDR(error_string, sarray("error"), Variant::UTILITY_FUNC_TYPE_GENERAL);', error_string],
	'type_string': [1, ' FUNCBINDR(type_string, sarray("type"), Variant::UTILITY_FUNC_TYPE_GENERAL);', type_string],
	'print': [1, ' FUNCBINDVARARGV(print, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', print],
	'print_rich': [1, ' FUNCBINDVARARGV(print_rich, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', print_rich],
	'printerr': [1, ' FUNCBINDVARARGV(printerr, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', printerr],
	'printt': [1, ' FUNCBINDVARARGV(printt, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', printt],
	'prints': [1, ' FUNCBINDVARARGV(prints, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', prints],
	'printraw': [1, ' FUNCBINDVARARGV(printraw, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', printraw],
	'print_verbose': [1, ' FUNCBINDVARARGV(print_verbose, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', print_verbose],
	'push_error': [1, ' FUNCBINDVARARGV(push_error, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', push_error],
	'push_warning': [1, ' FUNCBINDVARARGV(push_warning, sarray(), Variant::UTILITY_FUNC_TYPE_GENERAL);', push_warning],
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
}

func get_operator_name(p_op):
	return _op_names[p_op]
	
func _set_error(p_err):
	if error_set:
		return
		
	error_str = p_err
	error_set = true
	
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
		_:
			assert(false, "Inner error 1100.")
	node.next = nodes
	nodes = node
	return node

func GET_CHAR():
	if str_ofs >= expression.length():
		return ''
	var ret = expression[str_ofs]
	str_ofs += 1
	return ret

func ERR_FAIL_V(m_retval):
	push_error("Method/function failed. Returning: %s" % m_retval)
	return m_retval

func is_digit(c: String) -> bool:
	return c >= '0' and c <= '9'
	
func is_hex_digit(c: String):
	return (is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))

func is_unicode_identifier_start(c: String) -> bool:
	return BSEARCH_CHAR_RANGE(xid_start, c)
	
func is_binary_digit(c: String) -> bool:
	return (c == '0' || c == '1')
	
func is_unicode_identifier_continue(c: String) -> bool:
	return BSEARCH_CHAR_RANGE(xid_continue, c)
	
func BSEARCH_CHAR_RANGE(m_array, c: String):
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
	
func has_utility_function(p_name) -> bool:
	return utility_function_table.has(p_name)
	
func is_utility_function_vararg(p_name) -> bool:
	if not utility_function_table.has(p_name):
		return false
	return utility_function_table[p_name][1].begins_with("FUNCBINDVARARG(") or \
	utility_function_table[p_name][1].begins_with("FUNCBINDVARARGS(") or \
	utility_function_table[p_name][1].begins_with("FUNCBINDVARARGV(")
	
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
					if (!is_digit(expression[str_ofs])) :
						_set_error("Expected number after '$'")
						r_token.type = TokenType.TK_ERROR
						return ERR_PARSE_ERROR
		
					index *= 10
					index += int(expression[str_ofs]) # index += expression[str_ofs] - '0';
					str_ofs += 1

					if not is_digit(expression[str_ofs]):
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
					elif (ch == '\\') :
						# escaped characters...

						var next = GET_CHAR()
						if (next == '') :
							_set_error("Unterminated String")
							r_token.type = TokenType.TK_ERROR
							return ERR_PARSE_ERROR
			
						var res = 0

						match next :
							'b':
								res = 8
								#break
							't':
								res = 9
								#break
							'n':
								res = 10
								#break
							'f':
								res = 12
								#break
							'r':
								res = 13
								#break
							#'U':
							'U', 'u':
								#  Hexadecimal sequence.
								var hex_len = 6 if (next == 'U') else 4
								for j in hex_len :
									var c = GET_CHAR()

									if (c == '') :
										_set_error("Unterminated String")
										r_token.type = TokenType.TK_ERROR
										return ERR_PARSE_ERROR
						
									if (!is_hex_digit(c)) :
										_set_error("Malformed hex constant in string")
										r_token.type = TokenType.TK_ERROR
										return ERR_PARSE_ERROR
						
									var v
									if (is_digit(c)) :
										v = c.unicode_at(0) - '0'.unicode_at(0);
									elif (c >= 'a' && c <= 'f') :
										v = c.unicode_at(0) - 'a'.unicode_at(0)
										v += 10
									elif (c >= 'A' && c <= 'F') :
										v = c.unicode_at(0) - 'A'.unicode_at(0)
										v += 10
									else:
										push_error("Bug parsing hex constant.")
										v = 0
						

									res <<= 4
									res |= v
					

				 				#break
							_:
								res = next
				 				#break
			

						#  Parse UTF-16 pair.
						if ((res & 0xfffffc00) == 0xd800) :
							if (prev == 0) :
								prev = res
								continue
							else:
								_set_error("Invalid UTF-16 sequence in string, unpaired lead surrogate")
								r_token.type = TokenType.TK_ERROR
								return ERR_PARSE_ERROR
				
						elif ((res & 0xfffffc00) == 0xdc00) :
							if (prev == 0) :
								_set_error("Invalid UTF-16 sequence in string, unpaired trail surrogate")
								r_token.type = TokenType.TK_ERROR
								return ERR_PARSE_ERROR
						else:
								res = (prev << 10) + res - ((0xd800 << 10) + 0xdc00 - 0x10000)
								prev = 0
				
			
						if (prev != 0) :
							_set_error("Invalid UTF-16 sequence in string, unpaired lead surrogate")
							r_token.type = TokenType.TK_ERROR
							return ERR_PARSE_ERROR
			
						_str += res
					else:
						if (prev != 0) :
							_set_error("Invalid UTF-16 sequence in string, unpaired lead surrogate")
							r_token.type = TokenType.TK_ERROR
							return ERR_PARSE_ERROR
			
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
										if (next_char == 'b') :
											reading = READING_BIN
										elif (next_char == 'x') :
											reading = READING_HEX
							
						
								elif (c == '.') :
									reading = READING_DEC
									is_float = true
								elif (c == 'e') :
									reading = READING_EXP
									is_float = true
								else:
									reading = READING_DONE
					

								#break
							READING_BIN:
								if (bin_beg && !is_binary_digit(c)) :
									reading = READING_DONE
								elif (c == 'b') :
									bin_beg = true
					

								#break
							READING_HEX:
								if (hex_beg && !is_hex_digit(c)) :
									reading = READING_DONE
								elif (c == 'x') :
									hex_beg = true
					

								#break
							READING_DEC:
								if (is_digit(c)) : pass
								elif (c == 'e') :
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
					var id = (cchar)
					cchar = GET_CHAR()

					while (is_unicode_identifier_continue(cchar)) :
						id += (cchar)
						cchar = GET_CHAR()
		

					str_ofs -= 1 # go back one

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
						for i in TYPE_MAX:
							if (id == type_string(i)) :
								r_token.type = TokenType.TK_BASIC_TYPE
								r_token.value = i
								return OK
				
			

						if (has_utility_function(id)) :
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
				var identifier = tk.value

				var cofs = str_ofs
				_get_token(tk)
				if (tk.type == TokenType.TK_PARENTHESIS_OPEN) :
					# function call
					var func_call = alloc_node('CallNode')
					func_call.method = identifier
					var self_node = alloc_node('SelfNode')
					func_call.base = self_node

					while (true) :
						var cofs2 = str_ofs
						_get_token(tk)
						if (tk.type == TokenType.TK_PARENTHESIS_CLOSE) :
							break
			
						str_ofs = cofs2 # revert
						# parse an expression
						var subexpr = _parse_expression()
						if (!subexpr) :
							return null
			

						func_call.arguments.push_back(subexpr)

						cofs2 = str_ofs
						_get_token(tk)
						if (tk.type == TokenType.TK_COMMA) :
							pass # all good
						elif (tk.type == TokenType.TK_PARENTHESIS_CLOSE) :
							str_ofs = cofs2
						else:
							_set_error("Expected ',' or ')'")
			
		

					expr = func_call
				else:
					# named indexing
					str_ofs = cofs

					var input_index = -1
					for i in input_names.size():
						if (input_names[i] == identifier) :
							input_index = i
							break
			
		

					if (input_index != -1) :
						var input = alloc_node('InputNode')
						input.index = input_index
						expr = input
					else:
						var index = alloc_node('NamedIndexNode')
						var self_node = alloc_node('SelfNode')
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
		
	

				if (!is_utility_function_vararg(bifunc.func)) :
					var expected_args = get_utility_function_argument_count(bifunc.func)
					if (expected_args != bifunc.arguments.size()) :
						_set_error("Builtin func '" + str(bifunc.func) + "' expects " + str(expected_args) + " arguments.")
		
	

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
					if (tk.type != TokenType.TK_IDENTIFIER && tk.type != TokenType.TK_BUILTIN_FUNC) :
						_set_error("Expected identifier after '.'")
						return null
		

					var identifier = tk.value

					var cofs = str_ofs
					_get_token(tk)
					if (tk.type == TokenType.TK_PARENTHESIS_OPEN) :
						# function call
						var func_call = alloc_node('CallNode')
						func_call.method = identifier
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
				
			

						expr = func_call
					else:
						# named indexing
						str_ofs = cofs

						var index = alloc_node('NamedIndexNode')
						index.base = expr
						index.name = identifier
						expr = index
		

					#break
				_: # default:
					str_ofs = cofs2
					done = true
	 				#break


			if (done) :
				break

		

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

# TODO r_ret, r_error_str IS reference FIXME
func _execute(p_inputs: Array, p_instance: Object, p_node, r_ret: Array, p_const_calls_only: bool, r_error_str: Array) -> bool:
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
				r_error_str[0] = tr("self can't be used because instance is null (not passed)")
				return true

			r_ret[0] = p_instance
			#break
		ExpressionENode.Type.TYPE_OPERATOR:
			var op = p_node as ExpressionOperatorNode

			var a = [null]
			var ret = _execute(p_inputs, p_instance, op.nodes[0], a, p_const_calls_only, r_error_str)
			if (ret) :
				return true


			var b = [null]

			if (op.nodes[1]) :
				ret = _execute(p_inputs, p_instance, op.nodes[1], b, p_const_calls_only, r_error_str)
				if (ret) :
					return true
	


			var valid = true
			#evaluate(op.op, a[0], b[0], r_ret, valid)# TODO
			match op.op:
				OP_EQUAL: # = 0 相等运算符（==）。
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
					r_ret[0] = a[0] * b[0]
				OP_DIVIDE: # = 9 除法运算符（/）。
					r_ret[0] = a[0] / b[0]
				OP_NEGATE: # = 10 一元减号运算符（-）。
					r_ret[0] = -a[0] # TODO
				OP_POSITIVE: # = 11 一元加号运算符（+）。
					r_ret[0] = a[0] # TODO
				OP_MODULE: # = 12 余数/取模运算符（%）。
					r_ret[0] = a[0] % b[0]
				OP_POWER: # = 13 幂运算符（**）。
					r_ret[0] = a[0] ** b[0]
				OP_SHIFT_LEFT: # = 14 左移运算符（<<）。
					r_ret[0] = a[0] << b[0]
				OP_SHIFT_RIGHT: # = 15 右移运算符（>>）。
					r_ret[0] = a[0] >> b[0]
				OP_BIT_AND: # = 16 按位与运算符（&）。
					r_ret[0] = a[0] & b[0]
				OP_BIT_OR: # = 17 按位或运算符（|）。
					r_ret[0] = a[0] | b[0]
				OP_BIT_XOR: # = 18 按位异或运算符（^）。
					r_ret[0] = a[0] ^ b[0]
				OP_BIT_NEGATE: # = 19 按位非运算符（~）。
					r_ret[0] = ~a[0] # TODO
				OP_AND: # = 20 逻辑与运算符（and 或 &&）。
					r_ret[0] = a[0] and b[0]
				OP_OR: # = 21 逻辑或运算符（or 或 ||）。
					r_ret[0] = a[0] or b[0]
				OP_XOR: # = 22 逻辑异或运算符（未在 GDScript 中实现）。
					pass
				OP_NOT: # = 23 逻辑非运算符（not 或 !）。
					r_ret[0] = not a[0] # TODO
				OP_IN: # = 24 逻辑 IN 运算符（in）。
					r_ret[0] = a[0] in b[0]
				_:
					pass
			if (!valid) :
				r_error_str[0] = tr("Invalid operands to operator %s, %s and %s.") % [get_operator_name(op.op), type_string(typeof(a)), type_string(typeof(b))]
				return true


			#break
		ExpressionENode.Type.TYPE_INDEX:
			var index = p_node as ExpressionIndexNode

			var base = [null]
			var ret = _execute(p_inputs, p_instance, index.base, base, p_const_calls_only, r_error_str)
			if (ret) :
				return true


			var idx = [null]

			ret = _execute(p_inputs, p_instance, index.index, idx, p_const_calls_only, r_error_str)
			if (ret) :
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
			base[0] is PackedVector2Array or base[0] is PackedVector3Array:
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
				var ex = Expression.new()
				var err = ex.parse("a[%s]" % var_to_str(idx[0]), ["a"])
				if err != OK:
					r_error_str[0] = ex.get_error_text()
					return true
				var v = ex.execute([base[0]], null, false)
				if ex.has_execute_failed():
					r_error_str[0] = ex.get_error_text()
					return true
				r_ret[0] = v
				

			#break
		ExpressionENode.Type.TYPE_NAMED_INDEX:
			var index = p_node as ExpressionNamedIndexNode

			var base = [null]
			var ret = _execute(p_inputs, p_instance, index.base, base, p_const_calls_only, r_error_str)
			if (ret) :
				return true


			#var valid
			#r_ret[0] = base[0].get_named(index.name, valid)
			#if (!valid) :
				#r_error_str[0] = tr("Invalid named index '%s' for base type %s") % [str(index.name), type_string(base.get_type())]
				#return true
			var ex = Expression.new()
			var err = ex.parse("a.%s" % index.name, ["a"])
			if err != OK:
				r_error_str[0] = ex.get_error_text()
				return true
			var v = ex.execute([base[0]], null, false)
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
				var ret = _execute(p_inputs, p_instance, array.array[i], value, p_const_calls_only, r_error_str)

				if (ret) :
					return true
	
				arr[i] = value[0]


			r_ret[0] = arr

			#break
		ExpressionENode.Type.TYPE_DICTIONARY:
			var dictionary = p_node as ExpressionDictionaryNode

			var d = {}
			for i in range(0, dictionary.dict.size(), 2):
				var key = [null]
				var ret = _execute(p_inputs, p_instance, dictionary.dict[i + 0], key, p_const_calls_only, r_error_str)

				if (ret) :
					return true
	

				var value = [null]
				ret = _execute(p_inputs, p_instance, dictionary.dict[i + 1], value, p_const_calls_only, r_error_str)
				if (ret) :
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
				var ret = _execute(p_inputs, p_instance, constructor.arguments[i], value, p_const_calls_only, r_error_str)

				if (ret) :
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
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_INT:
					match arr.size():
						0: r_ret[0] = int()
						1: r_ret[0] = int(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_FLOAT:
					match arr.size():
						0: r_ret[0] = float()
						1: r_ret[0] = float(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_STRING:
					match arr.size():
						0: r_ret[0] = String()
						1: r_ret[0] = String(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_VECTOR2:
					match arr.size():
						0: r_ret[0] = Vector2()
						1: r_ret[0] = Vector2(arr[0])
						2: r_ret[0] = Vector2(arr[0], arr[1])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_VECTOR2I:
					match arr.size():
						0: r_ret[0] = Vector2i()
						1: r_ret[0] = Vector2i(arr[0])
						2: r_ret[0] = Vector2i(arr[0], arr[1])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_VECTOR3:
					match arr.size():
						0: r_ret[0] = Vector3()
						1: r_ret[0] = Vector3(arr[0])
						3: r_ret[0] = Vector3(arr[0], arr[1], arr[2])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_VECTOR3I:
					match arr.size():
						0: r_ret[0] = Vector3i()
						1: r_ret[0] = Vector3i(arr[0])
						3: r_ret[0] = Vector3i(arr[0], arr[1], arr[2])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_VECTOR4:
					match arr.size():
						0: r_ret[0] = Vector4()
						1: r_ret[0] = Vector4(arr[0])
						4: r_ret[0] = Vector4(arr[0], arr[1], arr[2], arr[3])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_VECTOR4I:
					match arr.size():
						0: r_ret[0] = Vector4i()
						1: r_ret[0] = Vector4i(arr[0])
						4: r_ret[0] = Vector4i(arr[0], arr[1], arr[2], arr[3])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_PLANE:
					match arr.size():
						0: r_ret[0] = Plane()
						1: r_ret[0] = Plane(arr[0])
						2: r_ret[0] = Plane(arr[0], arr[1])
						3: r_ret[0] = Plane(arr[0], arr[1], arr[2])
						4: r_ret[0] = Plane(arr[0], arr[1], arr[2], arr[3])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_QUATERNION:
					match arr.size():
						0: r_ret[0] = Quaternion()
						1: r_ret[0] = Quaternion(arr[0])
						2: r_ret[0] = Quaternion(arr[0], arr[1])
						4: r_ret[0] = Quaternion(arr[0], arr[1], arr[2], arr[3])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_AABB:
					match arr.size():
						0: r_ret[0] = AABB()
						1: r_ret[0] = AABB(arr[0])
						2: r_ret[0] = AABB(arr[0], arr[1])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_BASIS:
					match arr.size():
						0: r_ret[0] = Basis()
						1: r_ret[0] = Basis(arr[0])
						2: r_ret[0] = Basis(arr[0], arr[1])
						3: r_ret[0] = Basis(arr[0], arr[1], arr[2])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_TRANSFORM3D:
					match arr.size():
						0: r_ret[0] = Transform3D()
						1: r_ret[0] = Transform3D(arr[0])
						2: r_ret[0] = Transform3D(arr[0], arr[1])
						4: r_ret[0] = Transform3D(arr[0], arr[1], arr[2], arr[3])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_PROJECTION:
					match arr.size():
						0: r_ret[0] = Projection()
						1: r_ret[0] = Projection(arr[0])
						4: r_ret[0] = Projection(arr[0], arr[1], arr[2], arr[3])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_COLOR:
					match arr.size():
						0: r_ret[0] = Color()
						1: r_ret[0] = Color(arr[0])
						2: r_ret[0] = Color(arr[0], arr[1])
						3: r_ret[0] = Color(arr[0], arr[1], arr[2])
						4: r_ret[0] = Color(arr[0], arr[1], arr[2], arr[3])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_STRING_NAME:
					match arr.size():
						0: r_ret[0] = StringName()
						1: r_ret[0] = StringName(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_NODE_PATH:
					match arr.size():
						0: r_ret[0] = NodePath()
						1: r_ret[0] = NodePath(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_RID:
					match arr.size():
						0: r_ret[0] = RID()
						1: r_ret[0] = RID(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_CALLABLE:
					match arr.size():
						0: r_ret[0] = Callable()
						1: r_ret[0] = Callable(arr[0])
						2: r_ret[0] = Callable(arr[0], arr[1])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_SIGNAL:
					match arr.size():
						0: r_ret[0] = Signal()
						1: r_ret[0] = Signal(arr[0])
						2: r_ret[0] = Signal(arr[0], arr[1])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_DICTIONARY:
					match arr.size():
						0: r_ret[0] = Dictionary()
						1: r_ret[0] = Dictionary(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_ARRAY:
					match arr.size():
						0: r_ret[0] = Array()
						1: r_ret[0] = Array(arr[0])
						4: r_ret[0] = Array(arr[0], arr[1], arr[2], arr[3])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_PACKED_BYTE_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedByteArray()
						1: r_ret[0] = PackedByteArray(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_PACKED_INT32_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedInt32Array()
						1: r_ret[0] = PackedInt32Array(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_PACKED_INT64_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedInt64Array()
						1: r_ret[0] = PackedInt64Array(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_PACKED_FLOAT32_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedFloat32Array()
						1: r_ret[0] = PackedFloat32Array(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_PACKED_FLOAT64_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedFloat64Array()
						1: r_ret[0] = PackedFloat64Array(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_PACKED_STRING_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedStringArray()
						1: r_ret[0] = PackedStringArray(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_PACKED_VECTOR2_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedVector2Array()
						1: r_ret[0] = PackedVector2Array(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_PACKED_VECTOR3_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedVector3Array()
						1: r_ret[0] = PackedVector3Array(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				TYPE_PACKED_COLOR_ARRAY:
					match arr.size():
						0: r_ret[0] = PackedColorArray()
						1: r_ret[0] = PackedColorArray(arr[0])
						_: r_error_str[0] = tr("Invalid arguments to construct '%s'") % type_string(constructor.data_type)
				_:
					r_error_str[0] = "Inner error 3280."


			#break
		ExpressionENode.Type.TYPE_BUILTIN_FUNC:
			var bifunc = p_node as ExpressionBuiltinFuncNode

			var arr = []
			#var argp = []
			arr.resize(bifunc.arguments.size())
			#argp.resize(bifunc.arguments.size())

			for i in bifunc.arguments.size():
				var value = [null]
				var ret = _execute(p_inputs, p_instance, bifunc.arguments[i], value, p_const_calls_only, r_error_str)
				if (ret) :
					return true
	
				arr[i] = value[0]
				#argp[i] = arr[i] # argp.write[i] = &arr[i];


			r_ret[0] = utility_function_table[bifunc._func][0].callv(arr)
			#if (ce.error != Callable.CallError.CALL_OK) :
				#r_error_str[0] = "Builtin call failed: " + get_call_error_text(bifunc._func, (const Variant **)argp.ptr(), argp.size(), ce)
				#return true


			#break
		ExpressionENode.Type.TYPE_CALL:
			var _call = p_node as ExpressionCallNode

			var base = [null]
			var ret = _execute(p_inputs, p_instance, _call.base, base, p_const_calls_only, r_error_str)

			if (ret) :
				return true


			var arr = []
			#var argp = []
			arr.resize(_call.arguments.size())
			#argp.resize(_call.arguments.size())

			for i in _call.arguments.size():
				var value = [null]
				ret = _execute(p_inputs, p_instance, _call.arguments[i], value, p_const_calls_only, r_error_str)

				if (ret) :
					return true
	
				arr[i] = value[0]
				#argp[i] = arr[i] # argp.write[i] = &arr[i]


			#Callable.CallError ce
			if (p_const_calls_only) : # p_const_calls_only makes no difference here
				r_ret[0] = base[0].call(_call.method, arr)
			else:
				r_ret[0] = base[0].call(_call.method, arr)


			#if (ce.error != Callable.CallError.CALL_OK) :
				#r_error_str[0] = vformat(RTR("On call to '%s':"), String(call.method))
				#return true


			#break
	
	return false


func parse(p_expression, p_input_names = []) -> Error:
	if (nodes) :
		#memdelete(nodes)
		nodes = null
		root = null
	

	error_str = String()
	error_set = false
	str_ofs = 0
	input_names = p_input_names

	expression = p_expression
	root = _parse_expression()

	if (error_set) :
		root = null
		#if (nodes) :
			#memdelete(nodes)
		
		nodes = null
		return ERR_INVALID_PARAMETER
	

	return OK


func execute(p_inputs: Array = [], p_base: Object = null, p_show_error = true, p_const_calls_only = false) :
	if error_set:
		push_error("There was previously a parse error: " + error_str + ".")
		return null

	execution_error = false
	var output = [null]
	var error_txt = [null]
	var err = _execute(p_inputs, p_base, root, output, p_const_calls_only, error_txt)
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

class ExpressionInput extends RefCounted:
	var type: int = TYPE_NIL
	var name: String
	
class ExpressionToken:
	var type: TokenType
	var value
	
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
		TYPE_CALL
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

	func _init() -> void:
		type = ExpressionENode.Type.TYPE_NAMED_INDEX
	


class ExpressionConstructorNode extends ExpressionENode:
	var data_type = TYPE_NIL
	var arguments: Array

	func _init() -> void:
		type = ExpressionENode.Type.TYPE_CONSTRUCTOR
	


class ExpressionCallNode extends ExpressionENode:
	var base = null
	var method: StringName
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
	

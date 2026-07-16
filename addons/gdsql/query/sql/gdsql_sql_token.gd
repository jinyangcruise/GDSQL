class_name GDSQLSqlToken
extends RefCounted

enum TokenType { KEYWORD, IDENTIFIER, LITERAL, OPERATOR, SEPARATOR, COMMENT, END_OF_INPUT }

var type: TokenType
var text: String = ""
var value: Variant
var span: GDSQLSourceSpan

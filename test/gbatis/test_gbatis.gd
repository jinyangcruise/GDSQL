@tool
extends Node2D
var _pass := 0; var _fail := 0
func _ready():
    print("\n"+"="*60+"\n  Test: GBatis\n"+"="*60+"\n")
    t_xml_load(); t_parse_select(); t_parse_insert(); t_parse_update()
    t_parse_delete(); t_parse_foreach(); t_parse_if(); _summary()
func ok(d): _pass+=1; print("  [PASS] "+d)
func nt(d,s=""): _fail+=1; printerr("  [FAIL] "+d+" - "+s)
func _summary(): print("\n  %d passed, %d failed\n%s\n" % [_pass,_fail,"="*60])
func _has_elem(txt, name):
    var p := XMLParser.new()
    if p.open_buffer(txt.to_utf8_buffer()) != OK: return false
    while p.read() == OK:
        if p.get_node_type()==XMLParser.NODE_ELEMENT and p.get_node_name()==name: return true
    return false
func t_xml_load():
    var xml := GDSQL.GXML.new()
    if xml != null: ok("Create GXML resource")
    var txt := '<?xml version="1.0"?><mapper namespace="T"><select id="a">select 1</select></mapper>'
    var p := XMLParser.new()
    if p.open_buffer(txt.to_utf8_buffer())==OK: ok("Parse XML string")
func t_parse_select():
    if _has_elem('<select id="byId">select * from t where id==#{id}</select>',"select"): ok("<select> element")
func t_parse_insert():
    if _has_elem('<insert id="ins">insert into t values ({id},{n})</insert>',"insert"): ok("<insert> element")
func t_parse_update():
    if _has_elem('<update id="upd">update t set hp={hp} where id=={id}</update>',"update"): ok("<update> element")
func t_parse_delete():
    if _has_elem('<delete id="del">delete from t where id=={id}</delete>',"delete"): ok("<delete> element")
func t_parse_foreach():
    var txt := '<select id="byIds">select * from t <where>id in <foreach collection="ids" item="v" open="(" separator="," close=")">#{v}</foreach></where></select>'
    if _has_elem(txt,"foreach"): ok("<foreach> element")
func t_parse_if():
    var txt := '<select id="cond"><where><if test="hp!=null">hp>=#{hp}</if></where></select>'
    if _has_elem(txt,"if"): ok("<if> element")

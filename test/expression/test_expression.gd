@tool
extends Node2D
var _pass := 0; var _fail := 0
func _ready():
    print("\n"+"="*60+"\n  Test: Expression\n"+"="*60+"\n")
    t_arith(); t_cmp(); t_logic(); t_null(); t_string(); t_func(); t_nest(); _summary()
func ok(d): _pass+=1; print("  [PASS] "+d)
func nt(d,s=""): _fail+=1; printerr("  [FAIL] "+d+" - "+s)
func _summary(): print("\n  %d passed, %d failed\n%s\n" % [_pass,_fail,"="*60])
func _eval(s,inp={}):
    var e := Expression.new()
    if e.parse(s)!=OK: return null
    return e.execute(inp.values(),inp.keys())
func t_arith():
    if _eval("1+1")==2: ok("1+1==2")
    if _eval("5*3")==15: ok("5*3==15")
    if _eval("2+3*4")==14: ok("2+3*4==14 (precedence)")
func t_cmp():
    if _eval("5>3")==true: ok("5>3")
    if _eval("'abc'=='abc'")==true: ok("string ==")
func t_logic():
    if _eval("true and true")==true: ok("AND")
    if _eval("not true")==false: ok("NOT")
func t_null():
    if _eval("null==null")==true: ok("null==null")
func t_string():
    if _eval("'hello'+' world'")=="hello world": ok("concat")
    if _eval("'abc'.length()")==3: ok("length()")
func t_func():
    if _eval("abs(-5)")==5: ok("abs(-5)")
    if _eval("max(10,20)")==20: ok("max()")
    if _eval("clamp(150,0,100)")==100: ok("clamp()")
func t_nest():
    if _eval("(1+2)*(3+4)")==21: ok("(1+2)*(3+4)")
    if _eval("max(10,min(20,15))")==15: ok("nested func")

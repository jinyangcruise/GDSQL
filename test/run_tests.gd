extends SceneTree

## Hosts gdUnit4's command line runner (GdUnitTestCIRunner is a Node, so it cannot be
## started with `--script`; it needs a SceneTree/MainLoop to live in).
##
## Usage:
##   godot --headless --path <project> --script res://test/run_tests.gd -- <args for gdUnit4>
##
## Anything after `--` is forwarded verbatim to gdUnit4, e.g.:
##   ... -- --ignoreHeadlessMode -a res://test/gbatis/test_gbatis_entity.gd

const RUNNER := "res://addons/gdUnit4/src/core/runners/GdUnitTestCIRunner.gd"


func _initialize() -> void:
	var runner: Node = (load(RUNNER) as GDScript).new()
	runner.name = "GdUnitCmdTool"
	root.add_child(runner)
	runner.call("init_runner")

@echo off
REM Run the GDSQL gdUnit4 suite headlessly.
REM Usage:  test\run_tests.cmd [extra gdUnit4 args...]
REM   test\run_tests.cmd                                  -> whole suite
REM   test\run_tests.cmd -a res://test/gbatis             -> one directory
REM   test\run_tests.cmd -a res://test/gbatis/test_user.gd
setlocal
set GODOT="D:\Program Files\Godot\Godot_v4.7.1-rc1_win64.exe"
set PROJ=%~dp0..
if "%~1"=="" (
  %GODOT% --headless --path "%PROJ%" --script res://test/run_tests.gd GdUnitCmdTool.gd --ignoreHeadlessMode -c -a res://test/core -a res://test/admin -a res://test/gbatis -a res://test/gxml
) else (
  %GODOT% --headless --path "%PROJ%" --script res://test/run_tests.gd GdUnitCmdTool.gd --ignoreHeadlessMode -c %*
)
endlocal

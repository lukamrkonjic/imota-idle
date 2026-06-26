@echo off
REM Rebuild the Godot class cache (.godot\). Run this after a fresh clone, or after
REM adding a new `class_name` or a new .glb. Mirrors what dev.sh does on macOS.
REM Override the engine path by setting GODOT_CONSOLE before calling.
setlocal
if "%GODOT_CONSOLE%"=="" set "GODOT_CONSOLE=C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe"
echo [import] Rebuilding Godot class cache via --import ...
"%GODOT_CONSOLE%" --headless --path "%~dp0." --import
endlocal

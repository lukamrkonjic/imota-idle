@echo off
REM Launch Imota. On a fresh clone there is no class cache (.godot\ is gitignored), which
REM nulls out autoloads and breaks the game; so build the cache once first if it's missing.
REM Override the engine path by setting GODOT before calling.
setlocal
if "%GODOT%"=="" set "GODOT=C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe"
if not exist "%~dp0.godot" (
  echo [run] No class cache found - building it once before launch...
  call "%~dp0import.bat"
)
"%GODOT%" --path "%~dp0."
endlocal

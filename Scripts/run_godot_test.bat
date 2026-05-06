@echo off
setlocal EnableDelayedExpansion

set "GODOT_EXE=%GODOT_EXE%"
if "%GODOT_EXE%"=="" set "GODOT_EXE=C:\Tools\Godot\godot.exe"

if "%~1"=="" (
    echo Usage: Scripts\run_godot_test.bat res://Tests/test_name.gd
    exit /b 2
)

set "TEST_PATH=%~1"
set "LOG_NAME=%~n1.log"
set "RUN_MODE=--script"

if /I "%~x1"==".tscn" set "RUN_MODE=--scene"
if /I "%~x1"==".gd" (
    set "SCENE_CANDIDATE=%~dp0..\Tests\%~n1.tscn"
    if exist "!SCENE_CANDIDATE!" (
        set "TEST_PATH=res://Tests/%~n1.tscn"
        set "RUN_MODE=--scene"
    )
)

"%GODOT_EXE%" --headless --path "%~dp0.." --log-file "%LOG_NAME%" %RUN_MODE% "%TEST_PATH%" --quit-after 600
exit /b %ERRORLEVEL%

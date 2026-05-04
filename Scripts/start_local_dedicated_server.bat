@echo off
REM Start the Godot dedicated server locally with the same command-file control path
REM used by Fly. Set GODOT_EXE first if Godot is not installed at C:\Tools\Godot.

setlocal
set "PROJECT_ROOT=%~dp0.."

if "%GODOT_EXE%"=="" set "GODOT_EXE=C:\Tools\Godot\godot.exe"
if not exist "%GODOT_EXE%" set "GODOT_EXE=godot"

if "%SERVER_COMMAND_FILE%"=="" set "SERVER_COMMAND_FILE=%PROJECT_ROOT%\local-server-commands.txt"
if "%PORT%"=="" set "PORT=24567"

if not exist "%SERVER_COMMAND_FILE%" type nul > "%SERVER_COMMAND_FILE%"
if not exist "%APPDATA%\Godot\app_userdata\FPMager\logs" mkdir "%APPDATA%\Godot\app_userdata\FPMager\logs" >nul 2>nul

set "GODOT_LOG_FILE=%PROJECT_ROOT%\local-server-godot.log"

echo Starting local dedicated server
echo Project: %PROJECT_ROOT%
echo Command file: %SERVER_COMMAND_FILE%
echo Port: %PORT%
echo.
echo In another PowerShell window, run:
echo   Scripts\local_server_command.bat status
echo   Scripts\local_server_command.bat boss replace health=2400 respawn=on
echo.

pushd "%PROJECT_ROOT%"
"%GODOT_EXE%" --headless --path "%PROJECT_ROOT%" --log-file "%GODOT_LOG_FILE%" --server
set "EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %EXIT_CODE%
